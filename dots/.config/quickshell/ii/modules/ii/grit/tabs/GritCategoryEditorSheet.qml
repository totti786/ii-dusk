import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/** A category groups habits and tasks under one colour. */
ClockSheet {
    id: root

    property string categoryId: ""
    property ClockSidePanel panels: null

    readonly property var existing: GritService.activeCategories.find(item => String(item.id) === String(root.categoryId)) ?? null
    readonly property bool editing: root.existing !== null
    readonly property color colAccent: GritStyle.accent(root.accent)

    property string name: ""
    property string icon: "label"
    property string accent: "primary"

    title: root.editing ? Translation.tr("Edit category") : Translation.tr("New category")
    subtitle: Translation.tr("A colour for habits and tasks that belong together")
    scrollable: true

    function load(): void {
        const category = root.existing;
        if (!category)
            return;
        root.name = String(category.name ?? "");
        root.icon = String(category.icon ?? "label");
        root.accent = String(category.accent ?? "primary");
    }

    function save(): void {
        const draft = {
            name: root.name.trim().length > 0 ? root.name.trim() : Translation.tr("New category"),
            icon: root.icon,
            accent: root.accent
        };
        if (root.editing)
            GritService.updateCategory(root.categoryId, draft);
        else
            GritService.createCategory(draft);
        root.close();
    }

    Component.onCompleted: root.load()

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 76
        radius: GritStyle.radiusLarge
        color: GritStyle.accentContainer(root.accent)

        RowLayout {
            anchors {
                fill: parent
                leftMargin: GritStyle.gapLarge
                rightMargin: GritStyle.gapLarge
            }
            spacing: GritStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: root.icon
                iconSize: 24
                padding: 11
                shape: "Cookie9Sided"
                color: root.colAccent
                colSymbol: ColorUtils.mostReadable(root.colAccent,
                    [GritStyle.colOnPrimary, GritStyle.colBackground])
            }

            StyledText {
                Layout.fillWidth: true
                text: root.name.length > 0 ? root.name : Translation.tr("New category")
                elide: Text.ElideRight
                font.family: GritStyle.fontTitle
                font.variableAxes: GritStyle.axesTitle
                font.pixelSize: Appearance.font.pixelSize.large
                color: GritStyle.accentOn(root.accent)
            }
        }
    }

    ClockFormField {
        symbol: "label"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Name")
        placeholder: Translation.tr("Health")
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
        colAccent: root.colAccent
        onPicked: icon => root.icon = icon
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
                selected: root.accent === String(modelData.id ?? "")
                onTriggered: root.accent = String(modelData.id ?? "primary")
            }
        }
    }

    actions: ColumnLayout {
        Layout.fillWidth: true
        spacing: GritStyle.gapSmall

        ClockButton {
            Layout.fillWidth: true
            variant: "filled"
            symbol: "check"
            label: root.editing ? Translation.tr("Save category") : Translation.tr("Create category")
            onClicked: root.save()
        }

        ClockButton {
            Layout.fillWidth: true
            symbol: "close"
            label: Translation.tr("Cancel")
            onClicked: root.close()
        }

        ClockButton {
            Layout.fillWidth: true
            visible: root.editing
            danger: true
            symbol: "delete"
            label: Translation.tr("Delete category")
            onClicked: {
                GritService.deleteCategory(root.categoryId);
                root.close();
            }
        }
    }
}
