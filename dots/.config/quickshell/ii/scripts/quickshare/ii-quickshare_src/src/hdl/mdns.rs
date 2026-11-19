use std::sync::{Arc, Mutex};
use std::time::Duration;

use mdns_sd::{AddrType, ServiceDaemon, ServiceInfo};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast::Receiver;
use tokio::sync::watch;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

use crate::utils::{gen_mdns_endpoint_info, gen_mdns_name, DeviceType};

const INNER_NAME: &str = "MDnsServer";
/// How long "temporarily" stays visible; the shell's tile says ten minutes.
const TEMP_VISIBLE: Duration = Duration::from_secs(600);

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum Visibility {
    Visible = 0,
    Invisible = 1,
    Temporarily = 2,
}

#[allow(dead_code)]
impl Visibility {
    pub fn from_raw_value(value: u64) -> Self {
        match value {
            0 => Visibility::Visible,
            1 => Visibility::Invisible,
            2 => Visibility::Temporarily,
            _ => unreachable!(),
        }
    }
}

pub struct MDnsServer {
    daemon: ServiceDaemon,
    service_info: ServiceInfo,
    ble_receiver: Receiver<()>,
    visibility_sender: Arc<Mutex<watch::Sender<Visibility>>>,
    visibility_receiver: watch::Receiver<Visibility>,
}

impl MDnsServer {
    pub fn new(
        endpoint_id: [u8; 4],
        service_port: u16,
        ble_receiver: Receiver<()>,
        visibility_sender: Arc<Mutex<watch::Sender<Visibility>>>,
        visibility_receiver: watch::Receiver<Visibility>,
    ) -> Result<Self, anyhow::Error> {
        let service_info = Self::build_service(endpoint_id, service_port, DeviceType::Laptop)?;

        Ok(Self {
            daemon: ServiceDaemon::new()?,
            service_info,
            ble_receiver,
            visibility_sender,
            visibility_receiver,
        })
    }

    /// Registration and shutdown must never take the whole mDNS task down: a failed
    /// register or a daemon thread that died is logged and retried, not returned.
    fn register(&self) -> bool {
        match self.daemon.register(self.service_info.clone()) {
            Ok(()) => true,
            Err(e) => {
                warn!("{INNER_NAME}: register failed: {e}");
                false
            }
        }
    }

    fn unregister(&self) {
        match self.daemon.unregister(self.service_info.get_fullname()) {
            // Wait for the daemon to confirm, but never forever.
            Ok(rx) => {
                let _ = rx.recv_timeout(Duration::from_secs(2));
            }
            Err(e) => warn!("{INNER_NAME}: unregister failed: {e}"),
        }
    }

    pub async fn run(&mut self, ctk: CancellationToken) -> Result<(), anyhow::Error> {
        info!("{INNER_NAME}: service starting");
        let mut visibility = *self.visibility_receiver.borrow();
        let mut registered = false;
        // When "temporarily" ends. None while not in that mode.
        let mut temp_deadline: Option<Instant> = None;
        let mut monitor = self.daemon.monitor()?;

        loop {
            let temp_sleep = async {
                match temp_deadline {
                    Some(d) => tokio::time::sleep_until(d).await,
                    None => std::future::pending::<()>().await,
                }
            };
            tokio::select! {
                _ = ctk.cancelled() => {
                    info!("{INNER_NAME}: tracker cancelled, breaking");
                    break;
                }
                r = monitor.recv_async() => {
                    if r.is_err() {
                        // The mdns-sd thread is gone. Start a fresh one and announce again.
                        error!("{INNER_NAME}: mDNS daemon stopped, restarting it");
                        tokio::time::sleep(Duration::from_secs(2)).await;
                        match ServiceDaemon::new() {
                            Ok(d) => {
                                self.daemon = d;
                                registered = false;
                                match self.daemon.monitor() {
                                    Ok(m) => monitor = m,
                                    Err(e) => { error!("{INNER_NAME}: monitor failed: {e}"); continue; }
                                }
                                if visibility != Visibility::Invisible {
                                    registered = self.register();
                                }
                            }
                            Err(e) => error!("{INNER_NAME}: cannot restart mDNS daemon: {e}"),
                        }
                    }
                },
                _ = self.visibility_receiver.changed() => {
                    visibility = *self.visibility_receiver.borrow_and_update();
                    debug!("{INNER_NAME}: visibility changed: {visibility:?}");
                    match visibility {
                        Visibility::Visible => {
                            temp_deadline = None;
                            if !registered { registered = self.register(); }
                        }
                        Visibility::Invisible => {
                            temp_deadline = None;
                            if registered { self.unregister(); registered = false; }
                        }
                        Visibility::Temporarily => {
                            temp_deadline = Some(Instant::now() + TEMP_VISIBLE);
                            if !registered { registered = self.register(); }
                        }
                    }
                }
                _ = ble_recv(&mut self.ble_receiver) => {
                    if visibility == Visibility::Invisible || !registered {
                        continue;
                    }
                    // Android can miss an mDNS service that was running BEFORE its
                    // Discovery phase began, so announce again.
                    if let Err(e) = self.daemon.register_resend(self.service_info.get_fullname()) {
                        warn!("{INNER_NAME}: re-announce failed: {e}");
                    }
                },
                _ = temp_sleep => {
                    temp_deadline = None;
                    if visibility == Visibility::Temporarily {
                        if registered { self.unregister(); registered = false; }
                        // Tells everyone else (the shell included) we went hidden.
                        let _ = self.visibility_sender.lock().unwrap().send(Visibility::Invisible);
                    }
                }
            }
        }

        // We're shutting down: withdraw the announcement.
        if registered {
            self.unregister();
        }

        Ok(())
    }

    fn build_service(
        endpoint_id: [u8; 4],
        service_port: u16,
        device_type: DeviceType,
    ) -> Result<ServiceInfo, anyhow::Error> {
        let name = gen_mdns_name(endpoint_id);
        let hostname = crate::utils::hostname()?;
        info!("Broadcasting with: {hostname}");
        let endpoint_info = gen_mdns_endpoint_info(device_type as u8, &hostname);

        let properties = [("n", endpoint_info)];
        let si = ServiceInfo::new(
            "_FC9F5ED42C8A._tcp.local.",
            &name,
            &hostname,
            "",
            service_port,
            &properties[..],
        )?
        .enable_addr_auto(AddrType::V4);

        Ok(si)
    }
}

/// A lagging or closed broadcast must not end the loop; wait for the next real nudge.
async fn ble_recv(rx: &mut Receiver<()>) {
    use tokio::sync::broadcast::error::RecvError;
    loop {
        match rx.recv().await {
            Ok(()) | Err(RecvError::Lagged(_)) => return,
            Err(RecvError::Closed) => std::future::pending::<()>().await,
        }
    }
}
