//! ii-quickshare: headless Quick Share daemon for the ii shell.
//!
//! JSON lines over $XDG_RUNTIME_DIR/ii-quickshare.sock.
//!   client -> daemon: {"cmd":"snapshot"} | {"cmd":"visibility","value":"visible|invisible|temporarily"}
//!     | {"cmd":"accept|reject|cancel","id":..} | {"cmd":"discover","on":bool}
//!     | {"cmd":"send","id":..,"name":..,"addr":"ip:port","files":[..]}
//!   daemon -> client: {"ev":"snapshot",..} | {"ev":"transfer",..} | {"ev":"endpoint",..} | {"ev":"visibility",..}
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use rqs_lib::channel::{ChannelAction, ChannelDirection, ChannelMessage, TransferType};
use rqs_lib::{EndpointInfo, OutboundPayload, SendInfo, State, Visibility, RQS};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, mpsc, Mutex};

fn vis_name(v: Visibility) -> &'static str {
    match v {
        Visibility::Visible => "visible",
        Visibility::Invisible => "invisible",
        Visibility::Temporarily => "temporarily",
    }
}

struct Shared {
    rqs: Mutex<RQS>,
    send_tx: mpsc::Sender<SendInfo>,
    out: broadcast::Sender<Value>,
    transfers: Mutex<HashMap<String, Value>>,
    endpoints: Mutex<HashMap<String, Value>>,
    visibility: Mutex<Visibility>,
    discovering: Mutex<bool>,
    ep_tx: broadcast::Sender<EndpointInfo>,
}

impl Shared {
    async fn snapshot(&self) -> Value {
        json!({
            "ev": "snapshot",
            "visibility": vis_name(*self.visibility.lock().await),
            "discovering": *self.discovering.lock().await,
            "transfers": self.transfers.lock().await.values().cloned().collect::<Vec<_>>(),
            "endpoints": self.endpoints.lock().await.values().cloned().collect::<Vec<_>>(),
        })
    }

    async fn set_visibility(&self, v: Visibility) {
        self.rqs.lock().await.change_visibility(v);
        *self.visibility.lock().await = v;
        let _ = self.out.send(json!({"ev":"visibility","value":vis_name(v)}));
    }
}

fn terminal(s: &State) -> bool {
    matches!(
        s,
        State::Finished | State::Rejected | State::Cancelled | State::Disconnected
    )
}

async fn pump_transfers(sh: Arc<Shared>, mut rx: broadcast::Receiver<ChannelMessage>) {
    loop {
        let m = match rx.recv().await {
            Ok(m) => m,
            Err(broadcast::error::RecvError::Lagged(_)) => continue,
            Err(_) => break,
        };
        if m.direction != ChannelDirection::LibToFront {
            continue;
        }
        let state = m.state.clone().unwrap_or_default();
        let rtype = match m.rtype {
            Some(TransferType::Inbound) => "inbound",
            Some(TransferType::Outbound) => "outbound",
            None => "",
        };
        let mut map = sh.transfers.lock().await;
        // Updates sometimes arrive without rtype/meta; merge into what we know.
        let prev = map.get(&m.id).cloned().unwrap_or(json!({}));
        let rtype = if rtype.is_empty() {
            prev["rtype"].as_str().unwrap_or("").to_string()
        } else {
            rtype.to_string()
        };
        let meta = match &m.meta {
            Some(meta) => serde_json::to_value(meta).unwrap_or(Value::Null),
            None => prev.get("meta").cloned().unwrap_or(Value::Null),
        };
        let ev = json!({
            "ev": "transfer",
            "id": m.id,
            "rtype": rtype,
            "state": format!("{:?}", state),
            "done": terminal(&state),
            "meta": meta,
        });
        if terminal(&state) {
            // Keep it briefly so a late client still sees the outcome, then drop.
            map.insert(m.id.clone(), ev.clone());
            let sh2 = sh.clone();
            let id = m.id.clone();
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_secs(20)).await;
                sh2.transfers.lock().await.remove(&id);
            });
        } else {
            map.insert(m.id.clone(), ev.clone());
        }
        drop(map);
        let _ = sh.out.send(ev);
    }
}

async fn pump_endpoints(sh: Arc<Shared>, mut rx: broadcast::Receiver<EndpointInfo>) {
    loop {
        let e = match rx.recv().await {
            Ok(e) => e,
            Err(broadcast::error::RecvError::Lagged(_)) => continue,
            Err(_) => break,
        };
        let present = e.present.unwrap_or(false);
        let ev = json!({
            "ev": "endpoint",
            "id": e.id,
            "name": e.name,
            "ip": e.ip,
            "port": e.port,
            "rtype": e.rtype.map(|t| format!("{:?}", t).to_lowercase()),
            "present": present,
        });
        let mut map = sh.endpoints.lock().await;
        if present {
            map.insert(e.id.clone(), ev.clone());
        } else {
            map.remove(&e.id);
        }
        drop(map);
        let _ = sh.out.send(ev);
    }
}

async fn handle_cmd(sh: &Arc<Shared>, v: &Value) -> Option<Value> {
    let id = v["id"].as_str().unwrap_or("").to_string();
    let act = |a: ChannelAction| {
        let rqs = sh.clone();
        let id = id.clone();
        async move {
            let _ = rqs.rqs.lock().await.message_sender.send(ChannelMessage {
                id,
                direction: ChannelDirection::FrontToLib,
                action: Some(a),
                ..Default::default()
            });
        }
    };
    match v["cmd"].as_str()? {
        "snapshot" => return Some(sh.snapshot().await),
        "visibility" => {
            let nv = match v["value"].as_str()? {
                "visible" => Visibility::Visible,
                "invisible" => Visibility::Invisible,
                "temporarily" => Visibility::Temporarily,
                _ => return Some(json!({"ev":"error","error":"bad visibility"})),
            };
            sh.set_visibility(nv).await;
        }
        "quit" => {
            let _ = std::fs::remove_file(sock_path());
            std::process::exit(0);
        }
        "accept" => act(ChannelAction::AcceptTransfer).await,
        "reject" => act(ChannelAction::RejectTransfer).await,
        "cancel" => act(ChannelAction::CancelTransfer).await,
        "discover" => {
            let on = v["on"].as_bool().unwrap_or(true);
            let mut cur = sh.discovering.lock().await;
            if on && !*cur {
                sh.endpoints.lock().await.clear();
                if let Err(e) = sh.rqs.lock().await.discovery(sh.ep_tx.clone()) {
                    return Some(json!({"ev":"error","error":e.to_string()}));
                }
                *cur = true;
            } else if !on && *cur {
                sh.rqs.lock().await.stop_discovery();
                sh.endpoints.lock().await.clear();
                *cur = false;
            }
            let _ = sh.out.send(json!({"ev":"discovering","on":*cur}));
        }
        "send" => {
            let files: Vec<String> = v["files"]
                .as_array()?
                .iter()
                .filter_map(|f| f.as_str().map(String::from))
                .collect();
            if files.is_empty() {
                return Some(json!({"ev":"error","error":"no files"}));
            }
            let si = SendInfo {
                id: v["addr"].as_str()?.to_string(),
                name: v["name"].as_str().unwrap_or("").to_string(),
                addr: v["addr"].as_str()?.to_string(),
                ob: OutboundPayload::Files(files),
            };
            let _ = sh.send_tx.send(si).await;
        }
        _ => return Some(json!({"ev":"error","error":"unknown cmd"})),
    }
    None
}

async fn client(sh: Arc<Shared>, s: UnixStream) {
    let (r, mut w) = s.into_split();
    let mut lines = BufReader::new(r).lines();
    let mut rx = sh.out.subscribe();
    let first = sh.snapshot().await;
    if w.write_all(format!("{first}\n").as_bytes()).await.is_err() {
        return;
    }
    loop {
        tokio::select! {
            l = lines.next_line() => {
                let Ok(Some(l)) = l else { break };
                let Ok(v) = serde_json::from_str::<Value>(&l) else { continue };
                if let Some(reply) = handle_cmd(&sh, &v).await {
                    if w.write_all(format!("{reply}\n").as_bytes()).await.is_err() { break; }
                }
            }
            ev = rx.recv() => {
                match ev {
                    Ok(ev) => { if w.write_all(format!("{ev}\n").as_bytes()).await.is_err() { break; } }
                    Err(broadcast::error::RecvError::Lagged(_)) => {
                        let s = sh.snapshot().await;
                        if w.write_all(format!("{s}\n").as_bytes()).await.is_err() { break; }
                    }
                    Err(_) => break,
                }
            }
        }
    }
}

fn sock_path() -> PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(dir).join("ii-quickshare.sock")
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info,mdns_sd=error,polling=error,neli=error");
    }
    tracing_subscriber::fmt::init();

    let mut download: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--download-dir" => download = args.next().map(PathBuf::from),
            "--help" | "-h" => {
                println!("ii-quickshare [--download-dir DIR]\nQuick Share daemon; JSON lines on $XDG_RUNTIME_DIR/ii-quickshare.sock");
                return Ok(());
            }
            other => {
                eprintln!("ii-quickshare: unknown argument {other}");
                std::process::exit(2);
            }
        }
    }

    // One daemon per user. A second one would unlink the live socket and leave the first
    // running but unreachable, so if somebody already answers there, stand down.
    if UnixStream::connect(sock_path()).await.is_ok() {
        log::info!("already running on {}", sock_path().display());
        return Ok(());
    }

    let mut rqs = RQS::new(Visibility::Invisible, None, download);
    let message_rx = rqs.message_sender.subscribe();
    let (send_tx, _ble) = rqs.run().await?;
    let (ep_tx, ep_rx) = broadcast::channel(32);
    let (out, _) = broadcast::channel(256);

    let sh = Arc::new(Shared {
        rqs: Mutex::new(rqs),
        send_tx,
        out,
        transfers: Mutex::new(HashMap::new()),
        endpoints: Mutex::new(HashMap::new()),
        visibility: Mutex::new(Visibility::Invisible),
        discovering: Mutex::new(false),
        ep_tx,
    });
    tokio::spawn(pump_transfers(sh.clone(), message_rx));
    tokio::spawn(pump_endpoints(sh.clone(), ep_rx));

    let path = sock_path();
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
    }
    log::info!("listening on {}", path.display());

    // SIGTERM (pkill, a service stop, logout) must clean up as well as Ctrl-C, or the
    // socket file is left behind for the next start to trip over.
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    loop {
        tokio::select! {
            r = listener.accept() => {
                if let Ok((s, _)) = r { tokio::spawn(client(sh.clone(), s)); }
            }
            _ = tokio::signal::ctrl_c() => break,
            _ = term.recv() => break,
        }
    }
    let _ = std::fs::remove_file(&path);
    sh.rqs.lock().await.stop().await;
    Ok(())
}
