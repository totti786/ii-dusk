pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.soundscapes.components

/**
 * The ambient mix, expanded inside the auxiliary bubble's card: a mixer in small.
 *
 * The lead sound and what is playing, then play / pause with the master volume, a volume
 * slider for each of the first few sounds (the pictogram turns that sound off), and the
 * sleep timer as chips. The corner buttons shuffle a new mix and open the app.
 *
 * Self-contained on purpose: the bubble loads faces by URL, and such a file gets none of
 * its directory's types. It reads SoundscapesService, which the island already watches.
 */
Item {
    id: root

    readonly property var ids: SoundscapesService.active
    readonly property var shownIds: root.ids.slice(0, root.maxRows)
    readonly property int maxRows: 4
    readonly property var lead: SoundscapesService.sound(root.ids[0] ?? "")
    readonly property bool playing: SoundscapesService.playing
    readonly property var heroItems: [leadDisc]

    function toneColor(tone: int): color {
        return tone === 1 ? Appearance.colors.colSecondaryContainer
            : tone === 2 ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer;
    }
    function onToneColor(tone: int): color {
        return tone === 1 ? Appearance.colors.colOnSecondaryContainer
            : tone === 2 ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer;
    }
    function toneOf(id: string): int {
        return SoundscapesService.styleOf(SoundscapesService.sound(id)?.groupId ?? "").tone;
    }

    readonly property string title: {
        if (SoundscapesService.preset !== "") {
            const named = SoundscapesService.presets.find(p => p.id === SoundscapesService.preset);
            if (named?.name)
                return named.name;
        }
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

    // ── Geometry: declared, so the box answers to the content and not to the card ──
    readonly property real margin: 14
    readonly property real preferredExpandedWidth: 340
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    // The scroll that rested on the bubble to open this card carries on here as the volume.
    property real wheelDelta: 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.wheelDelta += event.angleDelta.y;
            if (Math.abs(root.wheelDelta) < 40)
                return;
            SoundscapesService.setMaster(Math.max(0, Math.min(1, SoundscapesService.master + (root.wheelDelta > 0 ? 0.05 : -0.05))));
            root.wheelDelta = 0;
        }
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        // ── The mix ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                id: leadDisc
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: width / 2
                color: root.playing ? root.toneColor(root.toneOf(root.ids[0] ?? "")) : Appearance.colors.colSurfaceContainerHighest
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                SoundIcon {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    visible: (root.lead?.icon ?? "") !== ""
                    source: root.lead?.icon ?? ""
                    color: root.playing ? root.onToneColor(root.toneOf(root.ids[0] ?? "")) : Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: (root.lead?.icon ?? "") === ""
                    text: "waves"
                    iconSize: 22
                    fill: 1
                    color: root.playing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({ "tnum": 1 })
                    color: Appearance.colors.colSubtext
                }
            }

            CornerButton {
                glyph: "shuffle"
                tip: Translation.tr("Surprise me with another mix")
                onClicked: SoundscapesService.surprise()
            }
            CornerButton {
                glyph: "open_in_new"
                tip: Translation.tr("Open Soundscapes")
                onClicked: GlobalStates.openSoundscapesApp("")
            }
        }

        // ── Play, volume ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            RippleButton {
                id: playButton
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: root.playing ? Appearance.rounding.full : Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: SoundscapesService.togglePlay()

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.playing ? "pause" : "play_arrow"
                        iconSize: 26
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                    }
                }
                StyledToolTip {
                    text: root.playing ? Translation.tr("Pause") : Translation.tr("Play")
                }
            }

            MaterialSymbol {
                text: SoundscapesService.master <= 0.001 ? "volume_off" : SoundscapesService.master < 0.5 ? "volume_down" : "volume_up"
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: SoundscapesService.master
                configuration: StyledSlider.Configuration.XS
                stopIndicatorValues: []
                tooltipContent: `${Math.round(value * 100)}%`
                onMoved: SoundscapesService.setMaster(value)
            }

            CornerButton {
                glyph: "stop"
                tip: Translation.tr("Stop and clear the mix")
                onClicked: SoundscapesService.stopAll()
            }
        }

        // ── Each sound ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.shownIds

                RowLayout {
                    id: soundRow
                    required property string modelData
                    readonly property var info: SoundscapesService.sound(soundRow.modelData)
                    readonly property int tone: root.toneOf(soundRow.modelData)

                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.toneColor(soundRow.tone)
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        onClicked: SoundscapesService.toggle(soundRow.modelData)

                        contentItem: Item {
                            SoundIcon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                source: soundRow.info?.icon ?? ""
                                color: root.onToneColor(soundRow.tone)
                            }
                        }
                        StyledToolTip {
                            text: Translation.tr("Turn %1 off").arg(soundRow.info?.name ?? soundRow.modelData)
                        }
                    }

                    StyledText {
                        Layout.preferredWidth: 92
                        text: soundRow.info?.name ?? soundRow.modelData
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: SoundscapesService.stateOf(soundRow.modelData).vol
                        configuration: StyledSlider.Configuration.XS
                        stopIndicatorValues: []
                        highlightColor: Appearance.colors.colSecondary
                        handleColor: Appearance.colors.colSecondary
                        tooltipContent: `${Math.round(value * 100)}%`
                        onMoved: SoundscapesService.setVolume(soundRow.modelData, value)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.ids.length > root.maxRows
                text: Translation.tr("+%1 more in the app").arg(root.ids.length - root.maxRows)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // ── Sleep timer ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "bedtime"
                iconSize: 18
                fill: SoundscapesService.timerRunning ? 1 : 0
                color: SoundscapesService.timerRunning ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            }

            Repeater {
                model: [15, 30, 60, 90]

                RippleButton {
                    id: chip
                    required property int modelData
                    readonly property bool selected: SoundscapesService.timerRunning
                        && Math.round(SoundscapesService.timerTotal / 60) === chip.modelData

                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: chip.selected ? Appearance.rounding.small : Appearance.rounding.full
                    colBackground: chip.selected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: chip.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
                    colRipple: chip.selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: SoundscapesService.setTimer(chip.selected ? 0 : chip.modelData)

                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            text: chip.modelData < 60 ? Translation.tr("%1 min").arg(chip.modelData)
                                : Translation.tr("%1 h").arg(chip.modelData / 60)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: chip.selected ? Font.DemiBold : Font.Normal
                            color: chip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                    }
                    StyledToolTip {
                        text: chip.selected ? Translation.tr("Cancel the sleep timer") : Translation.tr("Fade out and stop in %1 minutes").arg(chip.modelData)
                    }
                }
            }
        }
    }

    component CornerButton: RippleButton {
        id: cornerButton
        property string glyph
        property string tip

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: cornerButton.glyph
                iconSize: 18
                color: Appearance.colors.colOnSurface
            }
        }

        StyledToolTip {
            text: cornerButton.tip
        }
    }
}
