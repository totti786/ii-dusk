use serde::{Deserialize, Serialize};
use tokio::net::{TcpListener, TcpStream};
use std::net::IpAddr;
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::broadcast::Sender;
use tokio::sync::mpsc::Receiver;
use tokio::sync::{watch, Semaphore};
use tokio_util::sync::CancellationToken;

use crate::channel::{ChannelDirection, ChannelMessage};
use crate::errors::AppError;
use crate::hdl::{InboundRequest, OutboundPayload, OutboundRequest, State, Visibility};
use crate::utils::RemoteDeviceInfo;

const INNER_NAME: &str = "TcpServer";

/// Inbound connections served at once; the rest are dropped at accept.
const MAX_INBOUND: usize = 16;
/// A peer that connects and never starts the handshake is cut after this long.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(30);

/// Quick Share is a LAN protocol: refuse peers that are not on a local network.
fn is_local_peer(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => v4.is_private() || v4.is_loopback() || v4.is_link_local(),
        IpAddr::V6(v6) => {
            if let Some(v4) = v6.to_ipv4_mapped() {
                return v4.is_private() || v4.is_loopback() || v4.is_link_local();
            }
            let seg = v6.segments()[0];
            v6.is_loopback() || (seg & 0xfe00) == 0xfc00 || (seg & 0xffc0) == 0xfe80
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
pub struct SendInfo {
    pub id: String,
    pub name: String,
    pub addr: String,
    pub ob: OutboundPayload,
}

pub struct TcpServer {
    endpoint_id: [u8; 4],
    tcp_listener: TcpListener,
    sender: Sender<ChannelMessage>,
    connect_receiver: Receiver<SendInfo>,
    visibility: watch::Receiver<Visibility>,
    inbound_slots: Arc<Semaphore>,
}

impl TcpServer {
    pub fn new(
        endpoint_id: [u8; 4],
        tcp_listener: TcpListener,
        sender: Sender<ChannelMessage>,
        connect_receiver: Receiver<SendInfo>,
        visibility: watch::Receiver<Visibility>,
    ) -> Result<Self, anyhow::Error> {
        Ok(Self {
            endpoint_id,
            tcp_listener,
            sender,
            connect_receiver,
            visibility,
            inbound_slots: Arc::new(Semaphore::new(MAX_INBOUND)),
        })
    }

    pub async fn run(&mut self, ctk: CancellationToken) -> Result<(), anyhow::Error> {
        info!("{INNER_NAME}: service starting");
        let mut accept_errors: u32 = 0;

        loop {
            tokio::select! {
                _ = ctk.cancelled() => {
                    info!("{INNER_NAME}: tracker cancelled, breaking");
                    break;
                }
                Some(i) = self.connect_receiver.recv() => {
                    // Each send is its own task: a long transfer must not stop the
                    // listener from accepting, nor the next send from starting.
                    info!("{INNER_NAME}: connect_receiver: got {:?}", i);
                    let (eid, sender, cctk) = (self.endpoint_id, self.sender.clone(), ctk.clone());
                    tokio::spawn(async move {
                        if let Err(e) = Self::connect(eid, sender, cctk, i).await {
                            error!("{INNER_NAME}: error sending: {}", e);
                        }
                    });
                }
                r = self.tcp_listener.accept() => {
                    match r {
                        Ok((socket, remote_addr)) => {
                            accept_errors = 0;
                            // Nobody can learn our port unless we advertise it, so while
                            // hidden (or for a peer off the local network) just close.
                            if *self.visibility.borrow() == Visibility::Invisible
                                || !is_local_peer(remote_addr.ip())
                            {
                                debug!("{INNER_NAME}: dropped {remote_addr} (hidden or not local)");
                                continue;
                            }
                            let Ok(permit) = self.inbound_slots.clone().try_acquire_owned() else {
                                warn!("{INNER_NAME}: too many inbound connections, dropped {remote_addr}");
                                continue;
                            };
                            let csender = self.sender.clone();
                            tokio::spawn(async move {
                                let _permit = permit;
                                Self::serve_inbound(socket, remote_addr.to_string(), csender).await;
                            });
                        },
                        Err(err) => {
                            // Usually fd exhaustion or a peer that reset mid-accept. Giving
                            // up here would leave a daemon that looks alive but receives
                            // nothing, so back off and keep listening.
                            accept_errors = accept_errors.saturating_add(1);
                            let wait = Duration::from_millis(100u64 << accept_errors.min(6));
                            error!("{INNER_NAME}: error accepting ({accept_errors}): {err}; retry in {wait:?}");
                            tokio::select! {
                                _ = ctk.cancelled() => break,
                                _ = tokio::time::sleep(wait) => {}
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    async fn serve_inbound(socket: TcpStream, remote: String, csender: Sender<ChannelMessage>) {
        let mut ir = InboundRequest::new(socket, remote.clone(), csender.clone());

        loop {
            let res = if ir.state.state == State::Initial {
                match tokio::time::timeout(HANDSHAKE_TIMEOUT, ir.handle()).await {
                    Ok(r) => r,
                    Err(_) => {
                        debug!("{INNER_NAME}: {remote} sent nothing for {HANDSHAKE_TIMEOUT:?}, closing");
                        break;
                    }
                }
            } else {
                ir.handle().await
            };

            match res {
                Ok(_) => {}
                Err(e) => match e.downcast_ref() {
                    Some(AppError::NotAnError) => break,
                    None => {
                        if ir.state.state == State::Initial {
                            break;
                        }

                        if ir.state.state != State::Finished {
                            let _ = csender.send(ChannelMessage {
                                id: remote.clone(),
                                direction: ChannelDirection::LibToFront,
                                state: Some(State::Disconnected),
                                ..Default::default()
                            });
                        }
                        error!("{INNER_NAME}: error while handling client: {e} ({:?})", ir.state.state);
                        break;
                    }
                },
            }
        }
    }

    pub async fn connect(
        endpoint_id: [u8; 4],
        sender: Sender<ChannelMessage>,
        ctk: CancellationToken,
        si: SendInfo,
    ) -> Result<(), anyhow::Error> {
        debug!("{INNER_NAME}: Connecting to: {}", si.addr);
        let socket = tokio::time::timeout(Duration::from_secs(15), TcpStream::connect(si.addr.clone()))
            .await
            .map_err(|_| anyhow::anyhow!("connecting to {} timed out", si.addr))??;

        let mut or = OutboundRequest::new(
            endpoint_id,
            socket,
            si.id,
            sender.clone(),
            si.ob,
            RemoteDeviceInfo {
                device_type: crate::DeviceType::Unknown,
                name: si.name,
            },
        );

        // Send connection request
        or.send_connection_request().await?;
        // Send UKEY init
        or.send_ukey2_client_init().await?;

        loop {
            tokio::select! {
                _ = ctk.cancelled() => {
                    info!("{INNER_NAME}: tracker cancelled, breaking");
                    break;
                },
                r = or.handle() => {
                    if let Err(e) = r {
                        match e.downcast_ref() {
                            Some(AppError::NotAnError) => break,
                            None => {
                                if or.state.state == State::Initial {
                                    break;
                                }

                                if or.state.state != State::Finished && or.state.state != State::Cancelled {
                                    let _ = sender.send(ChannelMessage {
                                        id: si.addr,
                                        direction: ChannelDirection::LibToFront,
                                        state: Some(State::Disconnected),
                                        ..Default::default()
                                    });
                                }
                                error!("{INNER_NAME}: error while handling client: {e} ({:?})", or.state.state);
                                break;
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }
}
