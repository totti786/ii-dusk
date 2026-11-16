pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ai
import "CompanionFiles.js" as Files

DropArea {
    id: root
    keys: ["text/uri-list"]
    onEntered: drag => {
        const supported = Files.localPaths(drag.urls).length > 0;
        if (supported) drag.accept(Qt.CopyAction);
        else drag.accepted = false;
        AiCompanionUi.fileHover = supported;
    }
    onPositionChanged: drag => {
        if (AiCompanionUi.fileHover) drag.accept(Qt.CopyAction);
    }
    onExited: AiCompanionUi.fileHover = false
    onDropped: drop => {
        AiCompanionUi.fileHover = false;
        const paths = Files.localPaths(drop.urls);
        if (!paths.length) { drop.accepted = false; return; }
        drop.accept(Qt.CopyAction);
        // Opening another surface inside the native drop callback can
        // interrupt same-process drag completion and leave its cursor set.
        Qt.callLater(() => AiCompanionUi.attachFiles(paths));
    }
    Component.onDestruction: AiCompanionUi.fileHover = false
}
