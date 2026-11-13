pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The profiles of each sound card (analog stereo, HDMI, headset...), which PipeWire
 * exposes only through the Pulse layer, so they are read and set with pactl.
 */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: root.width
    /// Re-read the cards while the window is on show
    property bool active: true

    property var cards: []
    property bool failed: false


    function refresh(): void {
        if (!listCards.running)
            listCards.running = true;
    }

    function setProfile(card, profile): void {
        setProc.command = ["pactl", "set-card-profile", card.name, profile.name];
        setProc.running = true;
    }

    function parse(text): void {
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            root.failed = true;
            return;
        }
        root.failed = false;
        root.cards = data.map(card => ({
            name: card.name,
            title: card.properties["device.description"] ?? card.properties["alsa.card_name"] ?? card.name,
            active: card.active_profile,
            profiles: Object.keys(card.profiles)
                .map(key => ({
                    name: key,
                    description: card.profiles[key].description,
                    available: card.profiles[key].available !== false,
                    priority: card.profiles[key].priority ?? 0
                }))
                .filter(profile => profile.available && profile.name !== "pro-audio" || profile.name === card.active_profile)
                .sort((a, b) => b.priority - a.priority)
        })).filter(card => card.profiles.length > 0);
    }

    onActiveChanged: if (root.active) root.refresh()
    Component.onCompleted: root.refresh()

    Process {
        id: listCards
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
        onExited: code => {
            if (code !== 0)
                root.failed = true;
        }
    }

    Process {
        id: setProc
        onExited: root.refresh()
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

            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "tune"
                shape: MaterialShape.Shape.SoftBurst
                title: Translation.tr("What each sound card does")
                text: Translation.tr("A profile decides which jacks and outputs a card offers, like stereo, HDMI or a headset with a microphone.")
            }

            Repeater {
                model: root.cards
                delegate: ClockPane {
                    id: cardItem
                    required property var modelData
                    Layout.fillWidth: true
                    title: modelData.title
                    symbol: "developer_board"
                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        Repeater {
                            model: cardItem.modelData.profiles
                            delegate: ClockChip {
                                required property var modelData
                                label: modelData.description
                                selected: modelData.name === cardItem.modelData.active
                                onClicked: root.setProfile(cardItem.modelData, modelData)
                            }
                        }
                    }
                }
            }

            ClockEmptyState {
                Layout.fillWidth: true
                visible: root.cards.length === 0
                symbol: root.failed ? "error" : "tune"
                title: root.failed ? Translation.tr("Could not read the sound cards") : Translation.tr("No sound cards")
                subtitle: root.failed ? Translation.tr("This page needs pactl and a running PipeWire") : ""
            }
        }
    }
}
