pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** One picker for every model: signed-in agents and API providers, grouped by provider. */
Item {
    id: root
    signal picked(modelId: string)
    property string query: ""
    property var expandedProviders: []
    function toggleProvider(id) {
        expandedProviders = expandedProviders.includes(id) ? expandedProviders.filter(value => value !== id) : expandedProviders.concat([id]);
    }
    /** Only the sidebar's model chip shows this: the voice orb's desktop tasks follow this model, or are pinned. */
    property bool showVoiceFooter: false
    /** Offers "Auto" first: typed messages routed by what they need, instead of one chosen model. */
    property bool showAutoRow: false
    property bool autoActive: false
    signal autoPicked()
    readonly property bool voiceFollows: String(Config.options.ai.voice.escalationModel ?? "").trim().length === 0
    readonly property string voicePinnedName: {
        const raw = String(Config.options.ai.voice.escalationModel ?? "").trim();
        const id = raw.length > 0 && raw.indexOf(":") < 0 ? "claude:" + raw : raw;
        return Ai.catalog.models[id]?.title ?? raw;
    }
    readonly property real footerHeight: root.showVoiceFooter ? 52 : 0
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
        + (root.showVoiceFooter ? root.footerHeight + root.gap : 0)
    readonly property var rows: {
        const result = [], needle = root.query.trim().toLowerCase();
        if (root.showAutoRow && !needle) result.push({auto: true, header: false});
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
            horizontalAlignment: LayoutMirroring.enabled ? TextInput.AlignLeft : undefined
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
                text: Translation.tr("Find a model")
                color: Appearance.colors.colSubtext
            }
        }
    }
    ListView {
        id: modelList
        anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: footer.visible ? footer.top : parent.bottom; topMargin: root.gap; bottomMargin: footer.visible ? root.gap : 0 }
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
                visible: parent.modelData.header === true
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
                id: autoButton
                anchors.fill: parent
                visible: parent.modelData.auto === true
                toggled: root.autoActive
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer1
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                onClicked: root.autoPicked()
                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol { text: autoButton.toggled ? "check_circle" : "alt_route"; iconSize: 23; color: Appearance.colors.colPrimary }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Auto"); elide: Text.ElideRight; color: Appearance.colors.colOnLayer1 }
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Instant commands, then a quick model, then the desktop-tasks model"); elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                    }
                }
            }
            RippleButton {
                id: modelButton
                anchors.fill: parent
                visible: !parent.modelData.header && !parent.modelData.auto
                readonly property var entry: parent.modelData.model
                /** A model whose key is missing stays listed, greyed with the reason, rather than hidden. */
                readonly property bool needsKey: (entry?.requires_key ?? false) && !Ai.hasApiKey(entry?.key_id ?? "")
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
                        StyledText { Layout.fillWidth: true; text: modelButton.needsKey ? Translation.tr("Needs an API key. Add one in Settings, Models & Keys.") : (modelButton.entry?.description ?? ""); elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                    }
                }
            }
        }
        StyledText {
            anchors.centerIn: parent
            visible: modelList.count === 0
            text: Translation.tr("No matching models")
            color: Appearance.colors.colSubtext
        }
    }
    // The voice orb's desktop tasks: follow this chat model, or stay pinned to another one.
    RippleButton {
        id: footer
        visible: root.showVoiceFooter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.footerHeight
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer1
        onClicked: Config.options.ai.voice.escalationModel = root.voiceFollows ? Ai.currentModelId : ""
        contentItem: RowLayout {
            spacing: 10
            MaterialSymbol { text: "graphic_eq"; iconSize: 22; color: Appearance.colors.colPrimary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                    text: root.voiceFollows ? Translation.tr("Voice orb tasks use this model") : Translation.tr("Voice orb tasks: %1").arg(root.voicePinnedName)
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: root.voiceFollows ? Translation.tr("Click to keep them on this one") : Translation.tr("Click to follow the chat model")
                }
            }
        }
        StyledToolTip { text: Translation.tr("Only spoken requests that need tools, the browser or settings. Fine-tune in Settings > AI Assistant > Voice orb models.") }
    }
}
