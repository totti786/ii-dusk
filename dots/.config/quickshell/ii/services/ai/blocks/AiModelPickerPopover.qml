pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** One picker for the three signed-in engines; no parallel provider catalogs. */
Item {
    id: root
    signal picked(modelId: string)
    property string query: ""
    property var expandedProviders: []
    function toggleProvider(id) {
        expandedProviders = expandedProviders.includes(id) ? expandedProviders.filter(value => value !== id) : expandedProviders.concat([id]);
    }
    property bool hostOwnsCatalogueHeader: false
    property bool fillOpenRouterAvailableHeight: false
    readonly property bool modelCatalogueOpen: false
    readonly property bool modelCatalogueCanRefresh: false
    readonly property string modelCatalogueTitle: ""
    function closeModelCatalogue() {}
    function refreshModelCatalogue() { Ai.refreshOpencodeModels(); }
    onVisibleChanged: { if (visible) Ai.refreshOpencodeModels(); }
    Component.onCompleted: Ai.refreshOpencodeModels()
    readonly property real gap: Appearance.rounding.small
    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 3)
    implicitHeight: searchBox.implicitHeight + root.gap + Math.max(root.rowHeight, modelList.contentHeight)
    readonly property var rows: {
        const result = [], needle = root.query.trim().toLowerCase();
        for (const providerId of Ai.providerIds) {
            const provider = Ai.providers[providerId];
            const matching = provider.models.filter(model => !needle || (provider.name + " " + model.title + " " + model.value).toLowerCase().includes(needle));
            // Expand an engine or search to see its available models.
            const models = needle || root.expandedProviders.includes(providerId) ? matching : [matching.find(model => model.id === Ai.currentModelId) ?? matching[0]].filter(Boolean);
            if (!models.length) continue;
            result.push({header: true, providerId: providerId, title: provider.name, description: provider.description});
            for (const model of models) result.push({header: false, model: model});
        }
        return result;
    }
    Rectangle {
        id: searchBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: 44
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        TextInput {
            anchors.fill: parent
            anchors.margins: 12
            verticalAlignment: TextInput.AlignVCenter
            text: root.query
            onTextEdited: root.query = text
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.normal
            selectByMouse: true
            StyledText {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: parent.text.length === 0
                text: Translation.tr("Find an agent or connected model")
                color: Appearance.colors.colSubtext
            }
        }
    }
    ListView {
        id: modelList
        anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: parent.bottom; topMargin: root.gap }
        clip: true
        spacing: 4
        model: root.rows
        ScrollBar.vertical: ScrollBar {}
        delegate: Item {
            required property var modelData
            width: modelList.width
            height: modelData.header ? 42 : root.rowHeight
            RippleButton {
                id: providerButton
                anchors.fill: parent
                visible: parent.modelData.header
                readonly property string providerId: parent.modelData.providerId ?? ""
                buttonRadius: Appearance.rounding.small
                onClicked: root.toggleProvider(providerId)
                contentItem: RowLayout {
                    StyledText { Layout.fillWidth: true; text: providerButton.parent.modelData.title ?? ""; font.weight: Font.DemiBold; color: Appearance.colors.colSubtext }
                    MaterialSymbol { text: root.expandedProviders.includes(providerButton.providerId) ? "expand_less" : "expand_more"; iconSize: 20; color: Appearance.colors.colSubtext }
                }
                StyledToolTip { text: Translation.tr("Show or hide model choices") }
            }
            RippleButton {
                id: modelButton
                anchors.fill: parent
                visible: !parent.modelData.header
                readonly property var entry: parent.modelData.model
                toggled: entry?.id === Ai.currentModelId
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer1
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                onClicked: root.picked(entry.id)
                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol { text: modelButton.toggled ? "check_circle" : "smart_toy"; iconSize: 23; color: Appearance.colors.colPrimary }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledText { Layout.fillWidth: true; text: modelButton.entry?.title ?? ""; elide: Text.ElideRight; color: Appearance.colors.colOnLayer1 }
                        StyledText { Layout.fillWidth: true; text: modelButton.entry?.description ?? ""; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                    }
                }
            }
        }
        StyledText {
            anchors.centerIn: parent
            visible: modelList.count === 0
            text: Translation.tr("No matching agents")
            color: Appearance.colors.colSubtext
        }
    }
}
