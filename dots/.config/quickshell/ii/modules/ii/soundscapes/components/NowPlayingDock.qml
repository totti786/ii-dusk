import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * The mix, always in reach: a floating card over the bottom of every page but the mix
 * itself, with what is playing, the master volume, the sleep timer and play / pause.
 */
Item {
    id: root

    property bool compact: false
    property bool shown: true
    signal openMix()

    readonly property var ids: SoundscapesService.active
    readonly property string title: {
        const names = root.ids.map(id => SoundscapesService.sound(id)?.name ?? id);
        if (names.length <= 2)
            return names.join(" & ");
        return `${names[0]}, ${names[1]} ${Translation.tr("& %1 more").arg(names.length - 2)}`;
    }
    readonly property string subtitle: {
        const parts = [SoundscapesService.countLabel(root.ids.length)];
        if (SoundscapesService.timerRunning)
            parts.push(Translation.tr("%1 left").arg(SoundscapesService.formatTime(SoundscapesService.timerLeft)));
        else if (SoundscapesService.paused)
            parts.push(Translation.tr("Paused"));
        return parts.join(" · ");
    }

    implicitHeight: 72
    visible: opacity > 0.01
    opacity: root.shown ? 1 : 0
    transform: Translate {
        y: root.shown ? 0 : 24
        Behavior on y {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
        }
    }
    Behavior on opacity {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: ClockStyle.radiusCard
        color: Appearance.m3colors.m3surfaceContainerHighest
        border.width: 1
        border.color: ColorUtils.transparentize(ClockStyle.colOutline, 0.4)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openMix()
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gap
            }
            spacing: ClockStyle.gap

            AvatarStack {
                ids: root.ids
                size: 40
                maxShown: root.compact ? 3 : 4
                ringColor: card.color
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            RowLayout {
                visible: !root.compact
                spacing: ClockStyle.gapSmall
                MaterialSymbol {
                    text: "volume_up"
                    iconSize: ClockStyle.iconNormal
                    color: ClockStyle.colOnSurfaceVariant
                }
                StyledSlider {
                    Layout.preferredWidth: 150
                    from: 0
                    to: 1
                    value: SoundscapesService.master
                    configuration: StyledSlider.Configuration.XS
                    stopIndicatorValues: []
                    handleColor: ClockStyle.colPrimary
                    highlightColor: ClockStyle.colPrimary
                    tooltipContent: `${Math.round(value * 100)}%`
                    onMoved: SoundscapesService.setMaster(value)
                }
            }

            ClockPlayButton {
                size: 52
                running: SoundscapesService.playing
                colIdle: ClockStyle.colPrimary
                colIdleHover: ClockStyle.colPrimaryHover
                colIdleActive: ClockStyle.colPrimaryActive
                colOnIdle: ClockStyle.colOnPrimary
                colRunning: ClockStyle.colPrimary
                colRunningHover: ClockStyle.colPrimaryHover
                colRunningActive: ClockStyle.colPrimaryActive
                colOnRunning: ClockStyle.colOnPrimary
                onClicked: SoundscapesService.togglePlay()
            }
        }
    }
}
