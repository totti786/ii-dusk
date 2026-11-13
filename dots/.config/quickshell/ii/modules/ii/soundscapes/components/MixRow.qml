import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * A sound that is in the mix: its mark, a volume slider whose wave moves while it plays
 * and, for a sound that comes and goes (thunder, wolves, seagulls), how often it comes.
 */
Rectangle {
    id: root

    required property var sound
    property real volume: 0.6
    property real spacing: 0.1
    property bool playing: false

    signal volumeMoved(real value)
    signal spacingMoved(real value)
    signal removed()

    readonly property var look: SoundscapesService.styleOf(root.sound.groupId)
    readonly property int tone: root.look.tone
    readonly property bool gapped: root.sound.silence > 0

    implicitHeight: column.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colSurfaceHigh

    ColumnLayout {
        id: column
        anchors {
            fill: parent
            margins: ClockStyle.gap
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            SoundBadge {
                size: 48
                icon: root.sound.icon
                shapeName: SoundscapesStyle.morphOf(root.look.shape)
                colShape: SoundscapesStyle.accent(root.tone)
                colIcon: SoundscapesStyle.onAccent(root.tone)
                spinning: root.playing
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.sound.name
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.gapped ? `${root.sound.group} · ${Translation.tr("plays now and then")}` : `${root.sound.group} · ${Translation.tr("plays continuously")}`
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }
            StyledText {
                text: `${Math.round(root.volume * 100)}%`
                font.family: Appearance.font.family.numbers
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurfaceVariant
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
            }
            ClockIconButton {
                symbol: "close"
                size: 36
                iconSize: 20
                tooltip: Translation.tr("Remove from the mix")
                onClicked: root.removed()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall
            MaterialSymbol {
                text: root.volume <= 0.001 ? "volume_mute" : root.volume < 0.5 ? "volume_down" : "volume_up"
                iconSize: ClockStyle.iconNormal
                color: ClockStyle.colOnSurfaceVariant
            }
            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: root.volume
                configuration: StyledSlider.Configuration.Wavy
                animateWave: root.playing && !ClockStyle.reducedMotion
                stopIndicatorValues: []
                highlightColor: SoundscapesStyle.accent(root.tone)
                handleColor: SoundscapesStyle.accent(root.tone)
                trackColor: ColorUtils.transparentize(SoundscapesStyle.accent(root.tone), 0.78)
                tooltipContent: `${Math.round(value * 100)}%`
                onMoved: root.volumeMoved(value)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.gapped
            spacing: ClockStyle.gapSmall
            MaterialSymbol {
                text: "timelapse"
                iconSize: ClockStyle.iconNormal
                color: ClockStyle.colOnSurfaceVariant
            }
            StyledText {
                text: Translation.tr("Often")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: root.spacing
                configuration: StyledSlider.Configuration.XS
                stopIndicatorValues: []
                highlightColor: ClockStyle.colOnSurfaceVariant
                handleColor: ClockStyle.colOnSurfaceVariant
                trackColor: ColorUtils.transparentize(ClockStyle.colOnSurfaceVariant, 0.82)
                usePercentTooltip: false
                tooltipContent: Translation.tr("How long it stays quiet between plays")
                onMoved: root.spacingMoved(value)
            }
            StyledText {
                text: Translation.tr("Rarely")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }
}
