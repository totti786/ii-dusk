import QtQuick
import qs.services
import qs.modules.common

/** Signed-in agent catalog. The CLIs own auth, the shell owns the conversation.
 * Model objects are reused across refreshes instead of accumulating QML objects.
 * A local CLI transport can call cloud models, so these are remote for privacy policy.
 */
QtObject {
    id: catalog
    property Component modelComponent: AiModel {}
    property Component providerComponent: AiProvider {}
    property var opencodeModelNames: []
    property var agentModelNames: ({})
    property var providerCache: ({})
    property var modelCache: ({})
    readonly property var providerDefs: [
        {
            id: "codex", name: "Codex", icon: "openai-symbolic",
            description: Translation.tr("Uses your Codex ChatGPT sign-in. No API key."),
            homepage: "https://chatgpt.com", endpoint: "agent://codex", api_format: "opencode", requires_key: false,
            capabilities: {tools: true, attachments: true, vision: true, samplingParams: false},
            quirks: {agentEngine: "codex"},
            models: catalog.agentModelNames.codex?.length ? catalog.agentModelNames.codex : [{value: "default", title: Translation.tr("Codex default") }]
        },
        {
            id: "claude", name: "Claude Code", materialIcon: "neurology",
            description: Translation.tr("Uses your Claude Code subscription sign-in. No API key."),
            homepage: "https://claude.ai", endpoint: "agent://claude", api_format: "opencode", requires_key: false,
            capabilities: {tools: true, attachments: true, vision: true, samplingParams: false},
            quirks: {agentEngine: "claude"},
            models: catalog.agentModelNames.claude?.length ? catalog.agentModelNames.claude : [{value: "default", title: Translation.tr("Claude Code default") }]
        },
        {
            id: "opencode-server", name: "OpenCode", icon: "opencode-logo-light.svg",
            description: Translation.tr("Uses the providers already connected in OpenCode. No keys stored in QuickShell."),
            homepage: "https://opencode.ai", endpoint: "agent://opencode", api_format: "opencode", requires_key: false,
            capabilities: {tools: true, attachments: true, samplingParams: false},
            quirks: {agentEngine: "opencode"}, models: []
        }
    ]
    readonly property var opencodeEntries: {
        const entries = Array.from(catalog.opencodeModelNames ?? []).filter(m => m?.providerID && m?.modelID).map(m => ({
            value: `${m.providerID}/${m.modelID}`, title: String(m.name || m.modelID),
            tools: m.tools === true, vision: m.vision === true,
            contextWindow: Number(m.contextWindow ?? 0), maxOutput: Number(m.maxOutput ?? 0),
            capabilitySource: "detected"
        }));
        return entries.length > 0 ? entries : [{value: "auto/default", title: Translation.tr("OpenCode configured model")}];
    }
    readonly property var providers: {
        const result = {};
        // No cloud request is silently permitted by a loopback transport.
        if (Number(Config.options?.policies?.ai ?? 1) !== 1) return result;
        for (const def of catalog.providerDefs)
            result[def.id] = catalog.buildProvider(def, def.id === "opencode-server" ? catalog.opencodeEntries : def.models);
        return result;
    }
    readonly property var providerIds: Object.keys(catalog.providers)
    readonly property var models: {
        const result = {};
        for (const id of catalog.providerIds)
            for (const model of catalog.providers[id].models) result[model.id] = model;
        return result;
    }
    readonly property var modelIds: Object.keys(catalog.models)
    function isModelLocal(model): bool { return false; }
    function buildProvider(def: var, entries: var): var {
        const providerProperties = {
            id: def.id,
            name: def.name,
            icon: def.icon ?? "",
            materialIcon: def.materialIcon ?? "",
            description: def.description ?? "",
            homepage: def.homepage ?? "",
            endpoint: def.endpoint ?? "",
            api_format: def.api_format ?? "openai",
            requires_key: def.requires_key ?? true,
            key_id: def.key_id ?? def.id,
            key_get_link: def.key_get_link ?? "",
            key_get_description: def.key_get_description ?? "",
            local: false
        };
        const provider = catalog.providerCache[def.id] ?? catalog.providerComponent.createObject(catalog, providerProperties);
        catalog.providerCache[def.id] = provider;
        for (const key in providerProperties) provider[key] = providerProperties[key];
        const models = [];
        for (let i = 0; i < entries.length; i++) {
            const model = catalog.buildModel(def, provider, entries[i]);
            if (model)
                models.push(model);
        }
        provider.models = models;
        return provider;
    }

    function buildModel(def: var, provider: var, entry: var): var {
        const value = entry.value ?? entry.model ?? "";
        if (value.length === 0)
            return null;
        const caps = def.capabilities ?? {};
        const pick = (key, fallback) => entry[key] ?? caps[key] ?? fallback;
        const title = entry.title ?? value;
        const endpoint = (entry.endpoint ?? provider.endpoint ?? "").replace("{model}", entry.model ?? value);
        const modelProvider = entry.modelProvider ?? "";
        const properties = {
            id: `${provider.id}:${value}`,
            providerId: provider.id,
            value: value,
            title: title,
            modelProvider: modelProvider,
            name: provider.id === "others" ? title : `${provider.name} - ${title}`,
            icon: entry.icon ?? provider.icon,
            materialIcon: (entry.icon ?? provider.icon).length > 0 ? "" : (provider.materialIcon.length > 0 ? provider.materialIcon : "wand_stars"),
            description: entry.description ?? provider.description,
            homepage: entry.homepage ?? provider.homepage,
            endpoint: endpoint,
            model: modelProvider.length > 0 ? `${modelProvider}/${value}` : (entry.model ?? value),
            requires_key: entry.requires_key ?? provider.requires_key,
            key_id: entry.key_id ?? provider.key_id,
            key_get_link: entry.key_get_link ?? provider.key_get_link,
            key_get_description: entry.key_get_description ?? provider.key_get_description,
            api_format: entry.api_format ?? provider.api_format,
            extraParams: entry.extraParams ?? ({}),
            thinking: pick("thinking", false),
            thinkingKind: pick("thinkingKind", ""),
            thinkingAlwaysOn: pick("thinkingAlwaysOn", false),
            attachments: pick("attachments", false),
            vision: pick("vision", false),
            embeddings: pick("embeddings", false),
            capabilitySource: pick("capabilitySource", "knownCatalog"),
            tools: pick("tools", true),
            builtinSearch: pick("builtinSearch", false),
            samplingParams: pick("samplingParams", true),
            maxTemperature: pick("maxTemperature", 2.0),
            contextWindow: pick("contextWindow", 0),
            maxOutput: pick("maxOutput", 0),
            promptPrice: pick("promptPrice", ""),
            completionPrice: pick("completionPrice", ""),
            promptPriceIsFree: pick("promptPriceIsFree", false),
            completionPriceIsFree: pick("completionPriceIsFree", false),
            // Merged, not picked: a model overrides single quirks without
            // having to restate the ones its provider already declared.
            quirks: Object.assign({}, def.quirks ?? ({}), entry.quirks ?? ({}))
        };
        const model = catalog.modelCache[properties.id] ?? catalog.modelComponent.createObject(catalog, properties);
        catalog.modelCache[properties.id] = model;
        for (const key in properties) model[key] = properties[key];
        return model;
    }

    function resolve(providerId, value) { return catalog.models[`${providerId}:${value}`] ?? null; }
    function selectionEntries(providerId: string): var {
        return (catalog.providers[providerId]?.models ?? []).map(model => ({title: model.title, value: model.value, modelProvider: model.modelProvider}));
    }
}
