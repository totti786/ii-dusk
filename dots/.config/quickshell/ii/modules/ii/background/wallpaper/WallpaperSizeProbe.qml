import QtQuick
import Quickshell.Io

Process {
    id: probe
    property string path
    
    signal sizeDetected(int width, int height)
    
    command: ["magick", "identify", "-ping", "-format", "%w %h", (path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".mkv") || path.endsWith(".avi") || path.endsWith(".mov")) ? path + "[0]" : path]

    stdout: StdioCollector {
        id: collector
        onStreamFinished: {
            const output = collector.text.trim();
            if (!output) return;
            const parts = output.split(/\s+/);
            if (parts.length >= 2) {
                const w = Number(parts[0]);
                const h = Number(parts[1]);
                if (!isNaN(w) && !isNaN(h) && w > 0 && h > 0) {
                    probe.sizeDetected(w, h);
                }
            }
        }
    }
}
