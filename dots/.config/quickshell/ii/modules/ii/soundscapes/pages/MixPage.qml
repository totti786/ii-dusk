pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."
import "../components"

/**
 * What is playing: a big play / pause with the layers that make the mix, the master
 * volume, a volume (and for some sounds a spacing) slider for each layer and the sleep
 * timer. This is the app's front page once something is on.
 */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: width

    signal browseRequested()
    signal saveRequested()

    readonly property var ids: SoundscapesService.active
    readonly property bool has: SoundscapesService.hasMix
    readonly property bool wide: root.layoutWidth >= 940
    readonly property string headline: {
        if (!root.has)
            return Translation.tr("Silence, for now");
        const preset = SoundscapesService.presets.find(p => p.id === SoundscapesService.preset);
        if (preset)
            return preset.name;
        const names = root.ids.map(id => SoundscapesService.sound(id)?.name ?? id);
        return names.length <= 3 ? names.join(", ") : `${names.slice(0, 2).join(", ")} ${Translation.tr("& %1 more").arg(names.length - 2)}`;
    }
    readonly property string detail: {
        if (!root.has)
            return Translation.tr("Pick a few sounds from the library, or let the app choose for you.");
        const state = SoundscapesService.playing ? Translation.tr("Playing") : Translation.tr("Paused");
        return `${state} · ${SoundscapesService.countLabel(root.ids.length)}`;
    }

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: list
            width: flick.width
            spacing: ClockStyle.paneGap

            // ── The player ──────────────────────────────────────────────
            Rectangle {
                id: player
                Layout.fillWidth: true
                implicitHeight: playerBody.implicitHeight + ClockStyle.gapHuge * 2
                radius: ClockStyle.radiusCard
                color: root.has ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                // Two big shapes drift behind the content; a mask of the card rounds their clip
                Item {
                    id: ornament
                    anchors.fill: parent
                    visible: false
                    MaterialShape {
                        width: 320
                        height: width
                        x: player.width - width * 0.7
                        y: -height * 0.34
                        shapeString: "Cookie12Sided"
                        color: ClockStyle.colOnPrimaryContainer
                        NumberAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 90000
                            loops: Animation.Infinite
                            running: SoundscapesService.playing && !ClockStyle.reducedMotion
                        }
                    }
                    MaterialShape {
                        width: 200
                        height: width
                        x: -width * 0.35
                        y: player.height - height * 0.62
                        shapeString: "Clover8Leaf"
                        color: ClockStyle.colOnPrimaryContainer
                        NumberAnimation on rotation {
                            from: 360
                            to: 0
                            duration: 70000
                            loops: Animation.Infinite
                            running: SoundscapesService.playing && !ClockStyle.reducedMotion
                        }
                    }
                }
                Rectangle {
                    id: playerMask
                    anchors.fill: parent
                    radius: player.radius
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: ornament
                    maskEnabled: true
                    maskSource: playerMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    opacity: root.has ? 0.1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                }

                ColumnLayout {
                    id: playerBody
                    anchors {
                        fill: parent
                        margins: ClockStyle.gapHuge
                    }
                    spacing: ClockStyle.gapLarge

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapLarge

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: ClockStyle.gapSmall

                            AvatarStack {
                                visible: root.has
                                ids: root.ids
                                size: root.compact ? 44 : 56
                                maxShown: root.compact ? 4 : 7
                                ringColor: player.color
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.headline
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.title
                                font.variableAxes: ({ "wght": 760, "wdth": 100, "ROND": 100 })
                                font.pixelSize: root.compact ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.huge + 10
                                color: root.has ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.detail
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: root.has ? ClockStyle.colOnPrimaryContainer : ClockStyle.colSubtext
                                opacity: 0.85
                            }
                        }

                        ClockPlayButton {
                            visible: root.has
                            size: root.compact ? 72 : ClockStyle.fabSizeLarge
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

                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        ClockButton {
                            symbol: root.has ? "casino" : "library_music"
                            label: root.has ? Translation.tr("Surprise me") : Translation.tr("Browse sounds")
                            variant: root.has ? "tonal" : "filled"
                            onClicked: root.has ? SoundscapesService.surprise() : root.browseRequested()
                        }
                        ClockButton {
                            visible: !root.has
                            symbol: "casino"
                            label: Translation.tr("Surprise me")
                            variant: "tonal"
                            onClicked: SoundscapesService.surprise()
                        }
                        ClockButton {
                            visible: root.has
                            symbol: "bookmark_add"
                            label: Translation.tr("Save this mix")
                            variant: "tonal"
                            onClicked: root.saveRequested()
                        }
                        ClockButton {
                            visible: root.has
                            symbol: "layers_clear"
                            label: Translation.tr("Clear")
                            variant: "text"
                            onClicked: SoundscapesService.stopAll()
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: ClockStyle.paneGap
                rowSpacing: ClockStyle.paneGap

                // ── Layers ──────────────────────────────────────────────
                ClockPane {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.columnSpan: 1
                    Layout.preferredWidth: 10
                    visible: root.has
                    title: Translation.tr("Layers")
                    symbol: "layers"
                    shape: MaterialShape.Shape.SoftBurst
                    count: root.ids.length

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        // Master volume leads the layers
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: masterRow.implicitHeight + ClockStyle.gap * 2
                            radius: ClockStyle.radiusLarge
                            color: ClockStyle.colSurfaceHigh
                            RowLayout {
                                id: masterRow
                                anchors {
                                    fill: parent
                                    margins: ClockStyle.gap
                                }
                                spacing: ClockStyle.gap
                                ClockBadge {
                                    size: 48
                                    text: "volume_up"
                                    shape: MaterialShape.Shape.Circle
                                    color: ClockStyle.colSecondaryContainer
                                    colSymbol: ClockStyle.colOnSecondaryContainer
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Master volume")
                                            font.family: Appearance.font.family.title
                                            font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                            font.pixelSize: ClockStyle.textLarge
                                            color: ClockStyle.colOnSurface
                                        }
                                        StyledText {
                                            text: `${Math.round(SoundscapesService.master * 100)}%`
                                            font.family: Appearance.font.family.numbers
                                            font.pixelSize: ClockStyle.textNormal
                                            color: ClockStyle.colOnSurfaceVariant
                                        }
                                    }
                                    StyledSlider {
                                        Layout.fillWidth: true
                                        from: 0
                                        to: 1
                                        value: SoundscapesService.master
                                        configuration: StyledSlider.Configuration.Wavy
                                        animateWave: SoundscapesService.playing && !ClockStyle.reducedMotion
                                        stopIndicatorValues: []
                                        tooltipContent: `${Math.round(value * 100)}%`
                                        onMoved: SoundscapesService.setMaster(value)
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.ids
                            delegate: MixRow {
                                id: mixRow
                                required property string modelData
                                readonly property var info: SoundscapesService.sound(modelData)
                                Layout.fillWidth: true
                                visible: info !== null
                                sound: info ?? ({ id: modelData, name: modelData, group: "", groupId: "", icon: "", silence: 0 })
                                volume: SoundscapesService.stateOf(modelData).vol
                                spacing: SoundscapesService.stateOf(modelData).spacing
                                playing: SoundscapesService.playing
                                onVolumeMoved: value => SoundscapesService.setVolume(modelData, value)
                                onSpacingMoved: value => SoundscapesService.setSpacing(modelData, value)
                                onRemoved: SoundscapesService.toggle(modelData)
                            }
                        }
                    }
                }

                SleepTimerPane {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 10
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapLarge
                visible: !root.has
                symbol: "equalizer"
                shape: "SoftBurst"
                title: Translation.tr("Nothing layered yet")
                subtitle: Translation.tr("Sounds you turn on appear here with their own sliders")
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: ClockStyle.gap
            }
        }
    }
}
