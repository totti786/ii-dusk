import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

QtObject {
    id: root
    readonly property bool speaking: speaker.running
    property string messageId: ""
    property string errorText: ""
    property string pendingText: ""
    property string phase: ""
    property real level: 0
    signal finished(bool ok)

    function speak(text: string, id: string) {
        if (speaker.running)
            return;
        const plain = String(text).replace(/<think>[\s\S]*?<\/think>/g, "")
            .replace(/```[\s\S]*?```/g, " Code block omitted. ")
            .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
            .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
            .replace(/[#*_`>]/g, "").trim().slice(0, 4000);
        if (!plain.length)
            return;
        root.messageId = id;
        root.errorText = "";
        root.pendingText = plain;
        root.phase = "preparing";
        root.level = 0;
        speaker.stdinEnabled = true;
        speaker.running = true;
    }

    function stop() {
        if (speaker.running)
            speaker.signal(15);
    }

    property Process speaker: Process {
        id: speaker
        command: ["python3", Directories.scriptPath + "/ai/companion_tools.py"]
        stdinEnabled: true
        onStarted: {
            speaker.write(JSON.stringify({text: root.pendingText}) + "\n");
            speaker.stdinEnabled = false;
        }
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    if (result.event === "phase") root.phase = String(result.phase);
                    if (result.event === "level") root.level = Number(result.level);
                    if (result.isError)
                        root.errorText = String(result.text);
                } catch (e) {}
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.errorText.length === 0)
                root.errorText = "Speech could not play. Check the local companion voice service and audio output.";
            root.messageId = "";
            root.phase = "";
            root.level = 0;
            root.finished(code === 0 && root.errorText.length === 0);
        }
    }
}
