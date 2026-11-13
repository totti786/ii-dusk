import QtQuick
import QtQuick.Controls

import qs.modules.common

MenuSeparator {
    implicitHeight: 9
    topPadding: 4
    bottomPadding: 4
    leftPadding: 4
    rightPadding: 4
    contentItem: Rectangle {
        implicitHeight: 1
        color: Appearance.colors.colLayer0Border
        opacity: 0.7
    }
}
