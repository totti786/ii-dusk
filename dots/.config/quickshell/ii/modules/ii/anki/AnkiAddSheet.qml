pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/** Add a note to a deck, make a deck, or import an .apkg package. */
ClockSheet {
    id: root

    title: Translation.tr("Add to Anki")
    subtitle: Translation.tr("New note, new deck, or an .apkg package")

    property real deckId: AnkiService.currentDeckId
    property var noteType: null
    property string status: ""
    property bool statusIsError: false

    /// Decks as a flat list with their full names, nested ones included.
    readonly property var deckList: {
        const out = [];
        const walk = (node, path) => {
            for (const child of (node?.children ?? [])) {
                const full = path.length > 0 ? `${path}::${child.name}` : child.name;
                out.push({ "id": child.id, "name": full });
                walk(child, full);
            }
        };
        walk(AnkiService.decks, "");
        return out;
    }

    function say(message: string, isError: bool): void {
        root.status = message;
        root.statusIsError = isError;
    }

    function clearFields(): void {
        for (let i = 0; i < fieldRepeater.count; i++) {
            const item = fieldRepeater.itemAt(i);
            if (item)
                item.text = "";
        }
        const first = fieldRepeater.itemAt(0);
        if (first)
            Qt.callLater(first.focusInput);
    }

    function submit(): void {
        if (!root.noteType || root.deckId <= 0)
            return;
        const values = [];
        for (let i = 0; i < fieldRepeater.count; i++)
            values.push(fieldRepeater.itemAt(i)?.text ?? "");
        AnkiService.addNote(root.deckId, root.noteType.id, values, tagsField.text.trim(), (ok, message) => {
            if (ok) {
                root.say(Translation.tr("Added."), false);
                root.clearFields();
            } else {
                root.say(message.length > 0 ? message : Translation.tr("Could not add the note."), true);
            }
        });
    }

    Connections {
        target: AnkiService
        function onNoteTypesChanged(): void {
            if (!root.noteType && AnkiService.noteTypes.length > 0)
                root.noteType = AnkiService.noteTypes[0];
        }
    }

    Component.onCompleted: {
        AnkiService.loadNoteTypes();
        if (AnkiService.noteTypes.length > 0)
            root.noteType = AnkiService.noteTypes[0];
    }

    Process {
        id: picker
        command: ["python3", Directories.scriptPath + "/image_picker.py",
            "--title", Translation.tr("Import an Anki package"),
            "--folder", Directories.home,
            "--filters", JSON.stringify(["Anki packages (*.apkg)"])]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                let path = "";
                try {
                    path = String(JSON.parse(text));
                } catch (e) {
                    return;
                }
                root.say(Translation.tr("Importing…"), false);
                AnkiService.importPackage(FileUtils.trimFileProtocol(path), (ok, message) => {
                    root.say(ok ? Translation.tr("Imported: %1").arg(message) : (message || Translation.tr("Import failed.")), !ok);
                });
            }
        }
    }

    // ---- Note ----
    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Deck")
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        Repeater {
            model: root.deckList

            delegate: ClockChip {
                required property var modelData
                label: modelData.name
                selected: root.deckId === modelData.id
                onClicked: root.deckId = modelData.id
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Note type")
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        Repeater {
            model: AnkiService.noteTypes

            delegate: ClockChip {
                required property var modelData
                label: modelData.name
                selected: root.noteType !== null && root.noteType.id === modelData.id
                onClicked: root.noteType = modelData
            }
        }
    }

    Repeater {
        id: fieldRepeater
        model: root.noteType ? root.noteType.fields : []

        delegate: ClockFormField {
            required property var modelData
            required property int index
            symbol: index === 0 ? "edit_note" : "notes"
            caption: String(modelData)
            onAccepted: {
                const next = fieldRepeater.itemAt(index + 1);
                if (next)
                    next.focusInput();
                else
                    tagsField.focusInput();
            }
        }
    }

    ClockFormField {
        id: tagsField
        symbol: "sell"
        caption: Translation.tr("Tags (space separated)")
        onAccepted: root.submit()
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.status.length > 0
        text: root.status
        font.pixelSize: ClockStyle.textSmall
        color: root.statusIsError ? ClockStyle.colError : ClockStyle.colOnSurface
        wrapMode: Text.WordWrap
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: ClockStyle.colOutline
    }

    // ---- New deck ----
    ClockFormField {
        id: deckNameField
        symbol: "create_new_folder"
        caption: Translation.tr("New deck (Parent::Child nests it)")
        onAccepted: newDeck.clicked()
    }

    ClockButton {
        id: newDeck
        Layout.fillWidth: true
        label: Translation.tr("Create deck")
        symbol: "add"
        enabled: deckNameField.text.trim().length > 0
        onClicked: {
            AnkiService.createDeck(deckNameField.text.trim(), (ok, message, id) => {
                if (ok) {
                    root.deckId = id;
                    deckNameField.text = "";
                    root.say(Translation.tr("Deck created."), false);
                } else {
                    root.say(message || Translation.tr("Could not create the deck."), true);
                }
            });
        }
    }

    // ---- Import ----
    ClockButton {
        Layout.fillWidth: true
        label: Translation.tr("Import .apkg package…")
        symbol: "upload_file"
        variant: "text"
        enabled: !picker.running
        onClicked: picker.running = true
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Done")
            symbol: "check"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            label: Translation.tr("Add note")
            symbol: "note_add"
            enabled: root.noteType !== null && root.deckId > 0
            onClicked: root.submit()
        }
    ]
}
