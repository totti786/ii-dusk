import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** Create or edit a focus tag: what it is called, what it looks like, how it runs. */
ClockSheet {
    id: root

    property string tagId: ""
    property ClockSidePanel panels: null
    property string editorTab: "look"

    readonly property var existing: GritService.tagById(root.tagId)
    readonly property bool editing: root.existing !== null
    readonly property var previewTag: ({
        accent: root.accent,
        color: root.customColor,
        shape: root.shape,
        icon: root.icon
    })
    readonly property color colPreview: GritStyle.tagColor(root.previewTag)
    readonly property color colPreviewContainer: GritStyle.tagContainer(root.previewTag)
    readonly property color colPreviewOn: GritStyle.tagOn(root.previewTag)

    property string name: ""
    property string icon: "local_fire_department"
    property string shape: "Cookie7Sided"
    property string accent: "primary"
    property string customColor: ""
    property int focusMinutes: 25
    property int breakMinutes: 5
    property int longBreakMinutes: 15
    property int cycles: 4
    property int dailyGoalMinutes: 0
    property bool autoStartBreak: true
    property bool autoStartFocus: false
    property string errorText: ""

    title: root.editing ? Translation.tr("Edit tag") : Translation.tr("New tag")
    subtitle: Translation.tr("A label, a length and a colour for the work")
    scrollable: true

    function load(): void {
        const tag = root.existing;
        if (!tag)
            return;
        root.name = String(tag.name ?? "");
        root.icon = String(tag.icon ?? "local_fire_department");
        root.shape = String(tag.shape ?? "Cookie7Sided");
        root.accent = String(tag.accent ?? "primary");
        root.customColor = String(tag.color ?? "");
        root.focusMinutes = Math.max(1, Number(tag.focusMinutes ?? 25));
        root.breakMinutes = Math.max(1, Number(tag.breakMinutes ?? 5));
        root.longBreakMinutes = Math.max(1, Number(tag.longBreakMinutes ?? 15));
        root.cycles = Math.max(1, Number(tag.cycles ?? 4));
        root.dailyGoalMinutes = Math.max(0, Number(tag.dailyGoalMinutes ?? 0));
        root.autoStartBreak = tag.autoStartBreak !== false;
        root.autoStartFocus = tag.autoStartFocus === true;
    }

    function save(): void {
        if (root.customColor.length > 0 && !GritStyle.isHex(root.customColor)) {
            root.errorText = Translation.tr("The colour should look like #7C4DFF");
            root.editorTab = "look";
            return;
        }
        const draft = {
            name: root.name.trim().length > 0 ? root.name.trim() : Translation.tr("New tag"),
            icon: root.icon,
            shape: root.shape,
            accent: root.accent,
            color: root.customColor.trim(),
            focusMinutes: Math.max(1, root.focusMinutes),
            breakMinutes: Math.max(1, root.breakMinutes),
            longBreakMinutes: Math.max(1, root.longBreakMinutes),
            cycles: Math.max(1, root.cycles),
            dailyGoalMinutes: Math.max(0, root.dailyGoalMinutes),
            autoStartBreak: root.autoStartBreak,
            autoStartFocus: root.autoStartFocus
        };
        if (root.editing)
            GritService.updateTag(root.tagId, draft);
        else
            GritService.createTag(draft);
        root.close();
    }

    Component.onCompleted: root.load()

    // ── Sections ────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockFormChip {
            label: Translation.tr("Look & name")
            symbol: "palette"
            selected: root.editorTab === "look"
            onTriggered: root.editorTab = "look"
        }

        ClockFormChip {
            label: Translation.tr("Timing & goal")
            symbol: "timer"
            selected: root.editorTab === "timing"
            onTriggered: root.editorTab = "timing"
        }
    }

    // ── Look tab ────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.editorTab === "look"
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 86
            radius: GritStyle.radiusLarge
            color: root.colPreviewContainer

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: GritStyle.gapLarge
                    rightMargin: GritStyle.gapLarge
                }
                spacing: GritStyle.gap

                MaterialShapeWrappedMaterialSymbol {
                    text: root.icon
                    iconSize: 26
                    padding: 12
                    shape: root.shape
                    color: root.colPreview
                    colSymbol: GritStyle.tagOnSolid({ color: String(root.colPreview), accent: root.accent })
                    rotation: 12
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.name.length > 0 ? root.name : Translation.tr("New tag")
                        elide: Text.ElideRight
                        font.family: GritStyle.fontTitle
                        font.variableAxes: GritStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: root.colPreviewOn
                    }

                    StyledText {
                        text: Translation.tr("%1 focus · %2 break · %3 cycles · %4 goal")
                            .arg(GritStyle.durationShort(root.focusMinutes))
                            .arg(GritStyle.durationShort(root.breakMinutes))
                            .arg(String(root.cycles))
                            .arg(root.dailyGoalMinutes > 0
                                ? GritStyle.durationShort(root.dailyGoalMinutes) : Translation.tr("Off"))
                        font.pixelSize: GritStyle.textSmall
                        color: root.colPreviewOn
                        opacity: 0.8
                    }
                }
            }
        }

        ClockFormField {
            symbol: "label"
            shapeKind: MaterialShape.Shape.Cookie7Sided
            caption: Translation.tr("Name")
            placeholder: Translation.tr("Deep work")
            text: root.name
            onTextChanged: root.name = text
            onAccepted: root.save()
        }

        StyledText {
            Layout.leftMargin: 4
            Layout.topMargin: 4
            text: Translation.tr("Icon")
            font.pixelSize: GritStyle.textSmall
            font.weight: Font.DemiBold
            color: GritStyle.colOnSurfaceVariant
        }

        GritIconPicker {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            selected: root.icon
            colAccent: root.colPreview
            onPicked: icon => root.icon = icon
        }

        StyledText {
            Layout.leftMargin: 4
            Layout.topMargin: 4
            text: Translation.tr("Shape")
            font.pixelSize: GritStyle.textSmall
            font.weight: Font.DemiBold
            color: GritStyle.colOnSurfaceVariant
        }

        GritShapePicker {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            selected: root.shape
            colAccent: root.colPreview
            onPicked: shape => root.shape = shape
        }

        StyledText {
            Layout.leftMargin: 4
            Layout.topMargin: 4
            text: Translation.tr("Accent")
            font.pixelSize: GritStyle.textSmall
            font.weight: Font.DemiBold
            color: GritStyle.colOnSurfaceVariant
        }

        Flow {
            Layout.fillWidth: true
            spacing: GritStyle.gapSmall

            Repeater {
                model: GritStyle.accentNames

                ClockFormChip {
                    required property var modelData
                    label: String(modelData.label ?? "")
                    selected: root.customColor.length === 0 && root.accent === String(modelData.id ?? "")
                    onTriggered: {
                        root.accent = String(modelData.id ?? "primary");
                        root.customColor = "";
                    }
                }
            }
        }

        ClockFormField {
            symbol: "palette"
            shapeKind: MaterialShape.Shape.Flower
            caption: Translation.tr("Custom colour")
            placeholder: "#7C4DFF (leave empty to use the accent)"
            text: root.customColor
            onTextChanged: {
                root.customColor = text;
                root.errorText = "";
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            visible: root.errorText.length > 0
            text: root.errorText
            wrapMode: Text.WordWrap
            font.pixelSize: GritStyle.textSmall
            color: GritStyle.colError
        }
    }

    // ── Timing & goal tab ───────────────────────────────────────────────
    component DurationRow: Rectangle {
        id: durationRow
        property string symbol: ""
        property string label: ""
        property string description: ""
        property alias value: stepper.value
        property alias from: stepper.from
        property alias to: stepper.to
        property alias stepSize: stepper.stepSize
        property var format: value => GritStyle.durationShort(value)
        signal moved(int value)

        Layout.fillWidth: true
        implicitHeight: 62
        radius: GritStyle.radiusSmall
        color: GritStyle.colField

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 8
            }
            spacing: GritStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: durationRow.symbol
                iconSize: 18
                padding: 8
                shape: "Cookie7Sided"
                color: root.colPreviewContainer
                colSymbol: root.colPreviewOn
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: durationRow.label
                    elide: Text.ElideRight
                    font.pixelSize: GritStyle.textNormal
                    font.weight: Font.DemiBold
                    color: GritStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: durationRow.description.length > 0
                    text: durationRow.description
                    elide: Text.ElideRight
                    font.pixelSize: GritStyle.textSmall
                    color: GritStyle.colSubtext
                }
            }

            ClockStepper {
                id: stepper
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: GritStyle.gapSmall
                format: durationRow.format
                onMoved: value => durationRow.moved(value)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.editorTab === "timing"
        spacing: 8

        DurationRow {
            symbol: "psychiatry"
            label: Translation.tr("Focus")
            description: Translation.tr("Length of one session")
            value: root.focusMinutes
            from: 1
            to: 180
            onMoved: value => root.focusMinutes = value
        }

        DurationRow {
            symbol: "coffee"
            label: Translation.tr("Short break")
            description: Translation.tr("Between focus sessions")
            value: root.breakMinutes
            from: 1
            to: 60
            onMoved: value => root.breakMinutes = value
        }

        DurationRow {
            symbol: "self_improvement"
            label: Translation.tr("Long break")
            description: Translation.tr("After the last cycle")
            value: root.longBreakMinutes
            from: 1
            to: 90
            onMoved: value => root.longBreakMinutes = value
        }

        DurationRow {
            symbol: "repeat"
            label: Translation.tr("Cycles")
            description: Translation.tr("Sessions per long break")
            value: root.cycles
            from: 1
            to: 12
            format: value => String(value) + "×"
            onMoved: value => root.cycles = value
        }

        DurationRow {
            symbol: "flag"
            label: Translation.tr("Daily goal")
            description: Translation.tr("Target focus time each day")
            value: root.dailyGoalMinutes
            from: 0
            to: 480
            stepSize: 15
            format: value => value <= 0 ? Translation.tr("Off") : GritStyle.durationShort(value)
            onMoved: value => root.dailyGoalMinutes = value
        }

        ClockFormToggle {
            symbol: "coffee"
            label: Translation.tr("Start breaks automatically")
            description: Translation.tr("The break begins when focus ends")
            checked: root.autoStartBreak
            onToggled: checked => root.autoStartBreak = checked
        }

        ClockFormToggle {
            symbol: "psychiatry"
            label: Translation.tr("Start focus automatically")
            description: Translation.tr("Roll from a break straight into the next session")
            checked: root.autoStartFocus
            onToggled: checked => root.autoStartFocus = checked
        }
    }

    actions: ColumnLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "check"
            label: root.editing ? Translation.tr("Save tag") : Translation.tr("Create tag")
            onClicked: root.save()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: GritStyle.gapSmall

            ClockButton {
                Layout.fillWidth: true
                symbol: "close"
                label: Translation.tr("Cancel")
                onClicked: root.close()
            }

            ClockButton {
                visible: root.editing
                Layout.fillWidth: true
                danger: true
                symbol: "delete"
                label: Translation.tr("Delete")
                onClicked: {
                    GritService.deleteTag(root.tagId);
                    root.close();
                }
            }
        }
    }
}
