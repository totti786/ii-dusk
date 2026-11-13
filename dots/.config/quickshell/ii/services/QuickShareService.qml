pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Quick Share (Android's Nearby Share) behind the Quick Share window.
 *
 * The protocol runs in `scripts/quickshare/ii-quickshare` (built here from its _src), a detached daemon (mDNS, BLE nudge, UKEY2
 * handshake, AES/HMAC channel) that talks JSON lines on $XDG_RUNTIME_DIR/ii-quickshare.sock.
 * It is detached on purpose, so a shell reload never drops a transfer. This service starts
 * it when Quick Share is enabled, mirrors its state, and sends commands.
 *
 * The PC is invisible until the user says otherwise: "visible" and "10 minutes" are the only
 * ways anybody else can send here.
 */
Singleton {
    id: root

    readonly property string binary: Quickshell.shellPath("scripts/quickshare/ii-quickshare")
    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/ii-quickshare.sock`
    readonly property bool enabled: Config.options?.quickShare?.enable ?? false

    // ── The daemon binary: compiled here, like the shell's other Rust helpers ─────────
    // Nothing compiled is shipped. The source sits in scripts/quickshare/ii-quickshare_src and
    // rust-helpers.sh builds it (stamped, installed through a rename). Turning Quick Share on
    // is the request for it, so a missing binary is built then, with progress in Settings;
    // a failed build is not retried by itself, only by the Retry button.
    property bool binaryExists: false
    readonly property bool building: root.helperBuild.building
    readonly property bool needsBuild: root.enabled && !root.binaryExists
    readonly property RustHelperBuild helperBuild: RustHelperBuild {
        id: build
        label: "QuickShare"
        sourceDir: Quickshell.shellPath("scripts/quickshare/ii-quickshare_src")
        crateName: "ii-quickshare"
        onFinished: ok => root.checkBinary(ok)
        onCargoAvailableChanged: if (root.enabled) root.ensureRunning()
    }
    Process {
        id: binaryCheck
        property bool restartAfter: false
        command: ["test", "-x", root.binary]
        onExited: code => {
            root.binaryExists = (code === 0);
            // A rebuilt daemon replaces the running one, but never under a transfer.
            if (binaryCheck.restartAfter && root.binaryExists && root.linked) {
                restartDebounce.restart();
            }
            binaryCheck.restartAfter = false;
            if (root.enabled)
                root.ensureRunning();
        }
    }
    function checkBinary(rebuilt: bool): void {
        binaryCheck.restartAfter = rebuilt === true;
        binaryCheck.running = true;
    }

    // The window, or anything that watches, asks for device discovery.
    property int discoverers: 0
    function discover(): void { root.discoverers++; }
    function stopDiscover(): void { root.discoverers = Math.max(0, root.discoverers - 1); }

    property bool linked: false
    property string visibility: "invisible"       // invisible | temporarily | visible
    property bool discovering: false
    property var transfers: []                    // newest first
    property var pending: []                      // files chosen to send, waiting for a device
    property var endpoints: []                    // nearby devices, when discovering
    property string errorText: ""

    // Visibility "10 minutes" is the daemon's; the countdown is only for display.
    property real tempSince: 0
    onVisibilityChanged: root.tempSince = root.visibility === "temporarily" ? Date.now() : 0
    readonly property real tempMs: 10 * 60 * 1000

    // Files waiting for a device (from Files, a drop, the clipboard, IPC) hold discovery open.
    function stage(files: var): void {
        root.pending = files;
        if (!root.enabled && files.length > 0)
            Config.options.quickShare.enable = true;
    }
    readonly property bool wantDiscover: root.discoverers > 0 || root.pending.length > 0

    // Why the island shows it: someone can send here, something is moving, or files wait for a target.
    readonly property bool present: root.linked && (root.visibility !== "invisible" || root.busy
        || root.pending.length > 0 || root.incoming.length > 0)

    readonly property var incoming: root.transfers.filter(t => t.rtype === "inbound" && t.state === "WaitingForUserConsent")
    readonly property var active: root.transfers.filter(t => !t.done)
    readonly property bool busy: root.active.length > 0

    // ── Commands ─────────────────────────────────────────────────────────────
    function send(msg: var): void {
        if (!sock.connected)
            return;
        sock.write(JSON.stringify(msg) + "\n");
        sock.flush();
    }
    function setVisibility(v: string): void { root.send({ cmd: "visibility", value: v }); }

    // The tile: hidden <-> ten minutes. The first tap also turns Quick Share on, and the
    // visibility is applied once the daemon is up.
    property string afterLink: ""
    function toggleVisible(): void {
        if (!root.enabled) {
            root.afterLink = "temporarily";
            Config.options.quickShare.enable = true;
            return;
        }
        root.setVisibility(root.visibility === "invisible" ? "temporarily" : "invisible");
    }
    function accept(id: string): void { root.send({ cmd: "accept", id: id }); }
    function reject(id: string): void { root.send({ cmd: "reject", id: id }); }
    function cancel(id: string): void { root.send({ cmd: "cancel", id: id }); }
    function sendFiles(endpoint: var, files: var): void {
        root.send({ cmd: "send", name: endpoint.name ?? "", addr: endpoint.id, files: files });
        root.pending = [];
    }

    // ── Things to send that are not files yet ────────────────────────────────
    // The clipboard (an image, or text as a .txt) and the newest screenshot become files in a
    // private cache folder, then wait for a device like any other.
    readonly property string stash: `${Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")}/quickshare-out`
    function shareClipboard(): void { clipProc.running = true; }
    function shareLastScreenshot(): void { shotProc.running = true; }

    Process {
        id: clipProc
        command: ["sh", "-c", `d='${root.stash}'; mkdir -p "$d"; t=$(wl-paste --list-types 2>/dev/null); ` +
            `if printf '%s' "$t" | grep -q '^image/png'; then f="$d/clipboard-$(date +%H%M%S).png"; wl-paste --type image/png > "$f"; ` +
            `elif [ -n "$t" ]; then f="$d/clipboard-$(date +%H%M%S).txt"; wl-paste --no-newline > "$f"; fi; [ -s "$f" ] && printf '%s' "$f"`]
        stdout: StdioCollector { id: clipOut }
        onExited: {
            const f = clipOut.text.trim();
            if (f !== "")
                root.stage([f]);
        }
    }
    Process {
        id: shotProc
        command: ["sh", "-c", `ls -t "$HOME/Pictures/Screenshots"/* 2>/dev/null | head -n1`]
        stdout: StdioCollector { id: shotOut }
        onExited: {
            const f = shotOut.text.trim();
            if (f !== "")
                root.stage([f]);
        }
    }

    // ── State ────────────────────────────────────────────────────────────────
    function applyTransfer(ev: var): void {
        const rest = root.transfers.filter(t => t.id !== ev.id);
        if (ev.done && !(ev.id in root.seen))
            root.finished(ev);
        root.transfers = [ev].concat(rest).sort((a, b) => (a.done ? 1 : 0) - (b.done ? 1 : 0));
    }
    property var seen: ({})
    signal finished(var ev)

    function applySnapshot(s: var): void {
        root.visibility = s.visibility ?? "invisible";
        root.discovering = s.discovering === true;
        root.transfers = s.transfers ?? [];
        root.endpoints = s.endpoints ?? [];
        for (const t of root.transfers)
            if (t.done)
                root.seen[t.id] = true;
        if (root.afterLink !== "") {
            root.setVisibility(root.afterLink);
            root.afterLink = "";
        }
    }

    function applyEndpoint(ev: var): void {
        const rest = root.endpoints.filter(e => e.id !== ev.id);
        root.endpoints = ev.present ? rest.concat([ev]) : rest;
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: false
        parser: SplitParser {
            onRead: line => {
                let msg = null;
                try { msg = JSON.parse(line); } catch (e) { return; }
                switch (msg.ev) {
                case "snapshot": root.applySnapshot(msg); break;
                case "transfer": root.applyTransfer(msg); break;
                case "endpoint": root.applyEndpoint(msg); break;
                case "visibility": root.visibility = msg.value; break;
                case "discovering": root.discovering = msg.on === true; break;
                case "error": root.errorText = msg.error ?? ""; break;
                }
            }
        }
        onConnectedChanged: {
            root.linked = sock.connected;
            if (sock.connected) {
                root.syncDiscover();
            } else {
                root.transfers = [];
                root.endpoints = [];
                root.discovering = false;
                root.visibility = "invisible";
            }
        }
        onError: root.linked = false
    }

    function syncDiscover(): void {
        if (sock.connected && root.wantDiscover !== root.discovering)
            root.send({ cmd: "discover", on: root.wantDiscover });
    }
    onWantDiscoverChanged: syncDiscover()

    // ── Daemon lifecycle ─────────────────────────────────────────────────────
    // Start it when enabled and absent (setsid: it outlives the shell), then attach.
    Process {
        id: startProc
        onExited: attachTimer.restart()
    }

    function ensureRunning(): void {
        if (!root.enabled || sock.connected || startProc.running)
            return;
        if (!root.binaryExists) {
            if (!build.building && build.buildResult !== "failed" && build.cargoAvailable)
                build.build();
            return;
        }
        const dir = root.downloadDir;
        const args = dir !== "" ? ` --download-dir '${dir.replace(/'/g, "'\\''")}'` : "";
        startProc.command = ["sh", "-c",
            `pgrep -x ii-quickshare >/dev/null && exit 0; rm -f "$XDG_RUNTIME_DIR/ii-quickshare.sock"; ` +
            `l="\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"; mkdir -p "$l"; ` +
            `[ -f "$l/ii-quickshare.log" ] && mv -f "$l/ii-quickshare.log" "$l/ii-quickshare.log.1"; ` +
            `setsid '${root.binary}'${args} >"$l/ii-quickshare.log" 2>&1 &`];
        startProc.running = true;
    }

    Timer {
        id: attachTimer
        interval: 700
        onTriggered: sock.connected = root.enabled
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.checkBinary(false);
        } else {
            root.stopDaemon();
        }
    }

    // Disabled means gone: ask it to quit, and end any that is still there (one left from before
    // a shell restart, or one the shell was not attached to).
    Process {
        id: killProc
        command: ["pkill", "-x", "ii-quickshare"]
        // Also the "restart" half of a changed option: once it is gone, bring it back.
        onExited: if (root.enabled) root.ensureRunning()
    }

    // The daemon reads the download folder once at startup, so a change restarts it, but never
    // under a transfer in flight; that waits until it is idle.
    readonly property string downloadDir: String(Config.options?.quickShare?.downloadDir ?? "").trim()
    onDownloadDirChanged: restartDebounce.restart()
    Timer {
        id: restartDebounce
        interval: 1500
        onTriggered: {
            if (!root.enabled || !root.linked)
                return;
            if (root.busy) {
                restartDebounce.restart();
                return;
            }
            root.send({ cmd: "quit" });
            sock.connected = false;
            killProc.running = true;
        }
    }
    function stopDaemon(): void {
        root.send({ cmd: "quit" });
        sock.connected = false;
        killProc.running = true;
    }
    Component.onCompleted: {
        if (root.enabled)
            root.checkBinary(false);
        else
            killProc.running = true;
    }

    // Reattach if the daemon dies and comes back, or was never up.
    Timer {
        interval: 8000
        repeat: true
        running: root.enabled && !root.linked
        // Re-check the binary too: it may have been built, or deleted, since the last look.
        onTriggered: root.checkBinary(false)
    }

    // ── Incoming: a notification with Accept / Decline ───────────────────────
    // notify-send waits for the action and prints its key, so no extra UI is needed for the
    // common case; the window shows the same request for anyone who missed it.
    property var prompted: ({})
    onIncomingChanged: {
        for (const t of root.incoming) {
            if (t.id in root.prompted)
                continue;
            root.prompted[t.id] = true;
            root.prompt(t);
        }
    }

    function describe(t: var): string {
        const m = t.meta ?? {};
        if (m.files && m.files.length > 0)
            return m.files.length === 1 ? m.files[0] : `${m.files.length} files`;
        return m.text_description ?? "";
    }

    function prompt(t: var): void {
        const who = t.meta?.source?.name ?? "A nearby device";
        const pin = t.meta?.pin_code ? ` · PIN ${t.meta.pin_code}` : "";
        const p = promptComponent.createObject(root, {
            transferId: t.id,
            summary: `${who} wants to share${pin}`,
            body: root.describe(t),
        });
        p.running = true;
    }

    Component {
        id: promptComponent
        Process {
            id: p
            property string transferId: ""
            property string summary: ""
            property string body: ""
            command: ["notify-send", "-a", "Quick Share", "-i", "send_to_mobile", "-u", "critical",
                "-A", "accept=Accept", "-A", "reject=Decline", "-t", "60000", p.summary, p.body]
            stdout: StdioCollector { id: out }
            onExited: {
                const key = out.text.trim();
                if (key === "accept")
                    root.accept(p.transferId);
                else if (key === "reject")
                    root.reject(p.transferId);
                p.destroy();
            }
        }
    }

    // Finished transfers get a quiet notification.
    onFinished: ev => {
        root.seen[ev.id] = true;
        if (ev.state !== "Finished")
            return;
        const m = ev.meta ?? {};
        const what = root.describe(ev);
        const text = ev.rtype === "inbound"
            ? (m.destination ? `Saved to ${m.destination}` : what)
            : `Sent ${what}`;
        doneNotify.command = ["notify-send", "-a", "Quick Share", "-i", "check_circle",
            ev.rtype === "inbound" ? `Received ${what}` : "Sent", text];
        doneNotify.running = true;
    }
    Process { id: doneNotify }
}
