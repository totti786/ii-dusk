import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppProviders.js" as Providers

/**
 * The provider-independent weather glyph. Every source is normalized to a WMO code;
 * WeatherIcons owns the actual artwork and its day/night variants.
 */
Item {
    id: root

    property var code: 0
    property bool isDay: true
    property real iconSize: 48
    property bool showFallback: true

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    readonly property url source: WeatherIcons.getWeatherIcon(Providers.wmoToWwo(root.code), !root.isDay)

    Image {
        id: icon
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(Math.max(1, Math.round(root.iconSize * 2)), Math.max(1, Math.round(root.iconSize * 2)))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.showFallback && icon.status === Image.Error
        text: root.isDay ? "sunny" : "bedtime"
        iconSize: root.iconSize * 0.8
        color: WeatherStyle.colOnSurfaceVariant
    }
}
