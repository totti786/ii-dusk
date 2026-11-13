pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import QtPositioning

import qs.modules.common
import "WeatherAppProviders.js" as Providers
import "WeatherAppAstro.js" as Astro
import "WeatherAppLogic.js" as Logic

/**
 * State and fetching for the ii Weather app.
 *
 * This is deliberately separate from the bar's Weather singleton. The bar
 * service is tuned for a small popup and one source; this one normalizes six
 * providers, keeps its own location list and API keys, and is only woken when
 * the weather window is open.
 */
Singleton {
    id: root

    // ── Public state ────────────────────────────────────────────────────
    property bool active: false
    property bool ready: false
    property bool loading: false
    property bool airQualityLoading: false
    property bool searchingLocations: false
    property string error: ""
    property string errorKind: ""
    property string settingsError: ""
    property real lastFetchTime: 0
    property var data: ({})
    property var resolvedLocation: ({})
    property var locationResults: []
    property string searchError: ""

    // ── Settings file ───────────────────────────────────────────────────
    readonly property string settingsPath: `${Directories.state}/user/weather-app.json`
    property bool blockWrites: false

    property bool _pendingRefresh: false
    property bool _pendingForce: false
    property int _requestToken: 0
    property int _searchToken: 0
    property bool _settingsReady: false
    // AccuWeather needs a location key before it can answer; cache it per coordinates
    // for this app session so we do not spend a request on every refresh.
    property var _accuWeatherKeys: ({})

    readonly property var providerCatalog: Providers.catalog()
    readonly property var openMeteoModels: Providers.models()
    readonly property var currentProvider: Providers.providerById(root.settings.provider)
    readonly property var apiKeys: root.readApiKeys()
    readonly property string currentApiKey: root.apiKeys[root.currentProvider.id] || ""
    readonly property bool missingKey: root.currentProvider.requiresKey && root.currentApiKey.length === 0
    readonly property var units: Logic.unitsFromJson(root.settings.unitsJson)
    readonly property bool use24h: !/[aA]/.test(String(Config.options?.time?.format ?? "hh:mm"))
    readonly property var savedLocations: root.readLocations()
    readonly property int activeLocationIndex: {
        const count = root.savedLocations.length;
        if (count === 0) return 0;
        return Math.max(0, Math.min(count - 1, Number(root.settings.activeLocation)));
    }
    readonly property var activeLocation: root.savedLocations[root.activeLocationIndex] || null
    readonly property string providerLabel: root.currentProvider.name
    readonly property bool hasData: !!(root.data && root.data.hourly && root.data.hourly.length > 0)
    readonly property bool stale: root.lastFetchTime > 0 && Date.now() - root.lastFetchTime > Math.max(5, root.settings.refreshMinutes) * 60000
    readonly property var current: root.data?.current ?? ({})
    readonly property var hourly: root.data?.hourly ?? []
    readonly property var daily: root.data?.daily ?? []
    readonly property var airQuality: root.data?.airQuality ?? ({})

    // ── GPS ─────────────────────────────────────────────────────────────
    property bool gpsValid: false
    property real gpsLatitude: 0
    property real gpsLongitude: 0
    property real gpsUpdatedAt: 0
    property string gpsName: "Current location"
    property bool gpsServiceFailed: false

    signal dataRefreshed()

    // ── Settings helpers ────────────────────────────────────────────────
    function readApiKeys() {
        try {
            const parsed = JSON.parse(root.settings.apiKeysJson || "{}");
            return parsed && typeof parsed === "object" ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    function readLocations() {
        try {
            const parsed = JSON.parse(root.settings.locationsJson || "[]");
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }

    function writeLocations(locations) {
        root.settings.locationsJson = JSON.stringify(locations || []);
    }

    function estimateOffset(longitude, latitude) {
        return Math.round(Number(longitude || 0) / 15) * 3600;
    }

    function normalizeLocation(location) {
        if (!location)
            return null;
        const latitude = Number(location.latitude);
        const longitude = Number(location.longitude);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude))
            return null;
        return {
            id: String(location.id ?? `${latitude.toFixed(4)},${longitude.toFixed(4)}`),
            name: String(location.name || "Current location"),
            admin1: String(location.admin1 || ""),
            country: String(location.country || ""),
            latitude: latitude,
            longitude: longitude,
            timezone: String(location.timezone || ""),
            utcOffset: Number.isFinite(Number(location.utcOffset))
                ? Number(location.utcOffset)
                : root.estimateOffset(longitude, latitude)
        };
    }

    function isUsableLocation(location) {
        if (!location)
            return false;
        const lat = Number(location.latitude);
        const lon = Number(location.longitude);
        return Number.isFinite(lat) && Number.isFinite(lon)
            && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
            && !(Math.abs(lat) < 0.0001 && Math.abs(lon) < 0.0001);
    }

    function defaultCity() {
        if (!Config.ready)
            return "";
        const city = String(Config.options?.bar?.weather?.city ?? "").trim();
        return city === "City" ? "" : city;
    }

    function normalizeSettings() {
        const knownProviders = root.providerCatalog.map(provider => provider.id);
        if (!knownProviders.includes(root.settings.provider))
            root.settings.provider = "openMeteo";
        if (!root.settings.openMeteoModel || !root.openMeteoModels.some(model => model.id === root.settings.openMeteoModel))
            root.settings.openMeteoModel = "best_match";
        if (!root.settings.unitsJson) {
            root.settings.unitsJson = Logic.defaultUnitsJson();
        } else {
            const units = Logic.unitsFromJson(root.settings.unitsJson);
            root.settings.unitsJson = JSON.stringify(units);
        }
        if (!root.settings.apiKeysJson) {
            root.settings.apiKeysJson = "{}";
        } else {
            root.settings.apiKeysJson = JSON.stringify(root.readApiKeys());
        }
        const locations = root.readLocations();
        if (!Array.isArray(locations))
            root.settings.locationsJson = "[]";
        const count = root.readLocations().length;
        if (count === 0)
            root.settings.activeLocation = 0;
        else
            root.settings.activeLocation = Math.max(0, Math.min(count - 1, Number(root.settings.activeLocation)));
    }

    function saveNow() {
        if (root._settingsReady && !root.blockWrites)
            settingsFile.writeAdapter();
    }

    function setProvider(providerId) {
        if (root.settings.provider === providerId)
            return;
        const provider = Providers.providerById(providerId);
        root.settings.provider = provider.id;
        root.settings.lastProvider = provider.id;
        if (provider.id === "openMeteo")
            root.settings.openMeteoModel = "best_match";
        else if (provider.model)
            root.settings.openMeteoModel = provider.model;
        if (root.active)
            root.refresh(true);
    }

    function setOpenMeteoModel(modelId) {
        if (root.settings.openMeteoModel === modelId)
            return;
        root.settings.openMeteoModel = modelId;
        if (root.active && root.currentProvider.id === "openMeteo")
            root.refresh(true);
    }

    function setApiKey(providerId, key) {
        const keys = root.readApiKeys();
        keys[providerId] = String(key || "").trim();
        root.settings.apiKeysJson = JSON.stringify(keys);
        if (root.active && root.settings.provider === providerId)
            root.refresh(true);
    }

    function apiKeyFor(providerId) {
        return root.readApiKeys()[providerId] || "";
    }

    function setUnit(key, value) {
        const units = root.units;
        units[key] = value;
        root.settings.unitsJson = JSON.stringify(units);
    }

    function setRefreshMinutes(minutes) {
        root.settings.refreshMinutes = Math.max(5, Math.min(120, Number(minutes)));
    }

    function setIncludeAirQuality(value) {
        root.settings.includeAirQuality = !!value;
        if (value && root.hasData && root.active)
            root.fetchAirQuality(root.resolvedLocation, root._requestToken);
    }


    function setAccentMode(value) {
        root.settings.accentMode = value;
    }

    function setOverviewOrder(order) {
        root.settings.overviewOrderJson = JSON.stringify(Array.from(order ?? []));
    }

    function dismissError() {
        root.error = "";
        root.errorKind = "";
    }

    // ── Location management ─────────────────────────────────────────────
    function selectLocation(index) {
        if (index < 0 || index >= root.savedLocations.length)
            return;
        root.settings.activeLocation = index;
        root.settings.useGps = false;
        if (root.active)
            root.refresh(true);
    }

    function addLocation(location) {
        const normalized = root.normalizeLocation(location);
        if (!normalized)
            return -1;
        const locations = root.savedLocations.slice();
        let index = locations.findIndex(item =>
            Math.abs(Number(item.latitude) - normalized.latitude) < 0.01
            && Math.abs(Number(item.longitude) - normalized.longitude) < 0.01);
        if (index < 0) {
            locations.push(normalized);
            index = locations.length - 1;
        } else {
            locations[index] = Object.assign({}, locations[index], normalized);
        }
        root.writeLocations(locations);
        root.settings.activeLocation = index;
        root.settings.useGps = false;
        if (root.active)
            root.refresh(true);
        return index;
    }

    function removeLocation(index) {
        if (index < 0 || index >= root.savedLocations.length)
            return;
        const locations = root.savedLocations.slice();
        locations.splice(index, 1);
        root.writeLocations(locations);
        root.settings.activeLocation = Math.max(0, Math.min(index, locations.length - 1));
        if (root.active)
            root.refresh(true);
    }

    function clearLocationSearch() {
        root.locationResults = [];
        root.searchError = "";
        root.searchingLocations = false;
    }

    function searchLocations(query) {
        const text = String(query || "").trim();
        if (text.length < 2) {
            root.clearLocationSearch();
            return;
        }
        const token = ++root._searchToken;
        root.searchingLocations = true;
        root.searchError = "";
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(text)}&count=8&language=en&format=json`;
        root.httpGet(url, { "Accept": "application/json" }, response => {
            if (token !== root._searchToken)
                return;
            try {
                const json = JSON.parse(response);
                const results = Array.isArray(json.results) ? json.results : [];
                root.locationResults = results.map(result => root.normalizeLocation({
                    id: result.id,
                    name: result.name,
                    admin1: result.admin1 || result.admin2 || "",
                    country: result.country || "",
                    latitude: result.latitude,
                    longitude: result.longitude,
                    timezone: result.timezone || "",
                    utcOffset: root.estimateOffset(result.longitude, result.latitude)
                })).filter(result => result !== null);
                root.searchingLocations = false;
                if (root.locationResults.length === 0)
                    root.searchError = "No places match that search.";
            } catch (e) {
                root.searchingLocations = false;
                root.searchError = "The location search returned something unreadable.";
            }
        }, status => {
            if (token !== root._searchToken)
                return;
            root.searchingLocations = false;
            root.searchError = status === 0 ? "Couldn't reach the location service." : `Location search failed (HTTP ${status}).`;
        });
    }

    function reverseGeocode(latitude, longitude, callback) {
        const url = `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${latitude}&longitude=${longitude}&localityLanguage=en`;
        root.httpGet(url, { "Accept": "application/json" }, response => {
            let name = "";
            try {
                const json = JSON.parse(response);
                name = json.city || json.locality || json.principalSubdivision || json.countryName || "";
            } catch (e) {
                name = "";
            }
            callback(name || "Current location");
        }, () => callback("Current location"));
    }

    function useGps() {
        root.settings.useGps = true;
        root.gpsServiceFailed = false;
        root.error = "";
        root.errorKind = "";
        if (root.active) {
            gpsFallbackTimer.restart();
            root.refresh(true);
        }
    }

    function disableGps() {
        root.settings.useGps = false;
        root.gpsValid = false;
        gpsFallbackTimer.stop();
        if (root.active)
            root.refresh(true);
    }

    function refreshFromGps() {
        if (!root.gpsValid)
            return;
        root.refresh(true);
    }

    function handleGpsPosition(position) {
        if (!position.latitudeValid || !position.longitudeValid)
            return;
        const latitude = position.coordinate.latitude;
        const longitude = position.coordinate.longitude;
        const changed = !root.gpsValid
            || Math.abs(root.gpsLatitude - latitude) > 0.02
            || Math.abs(root.gpsLongitude - longitude) > 0.02;
        root.gpsLatitude = latitude;
        root.gpsLongitude = longitude;
        root.gpsValid = true;
        root.gpsUpdatedAt = Date.now();
        root.gpsServiceFailed = false;
        gpsFallbackTimer.stop();
        if (changed) {
            root.reverseGeocode(latitude, longitude, name => {
                root.gpsName = name;
                if (root.active)
                    root.refresh(true);
            });
        }
    }

    function handleGpsFailure() {
        if (!root.settings.useGps)
            return;
        root.gpsServiceFailed = true;
        root.settings.useGps = false;
        root.gpsValid = false;
        gpsFallbackTimer.stop();
        root.error = "Couldn't get a GPS fix. Showing your saved location instead.";
        root.errorKind = "location";
        if (root.active)
            root.refresh(true);
    }

    // ── Refresh / fetch ─────────────────────────────────────────────────
    function activate() {
        root.active = true;
    }

    function deactivate() {
        root.active = false;
        gpsFallbackTimer.stop();
    }

    function refresh(force) {
        if (!root.ready) {
            root._pendingRefresh = true;
            root._pendingForce = force === true;
            return;
        }
        if (root.loading)
            return;
        if (!force && root.lastFetchTime > 0 && Date.now() - root.lastFetchTime < 60000)
            return;

        const provider = root.currentProvider;
        if (provider.requiresKey && root.currentApiKey.length === 0) {
            root.loading = false;
            root.error = `${provider.name} needs an API key. Add one in Settings, or switch to a keyless source.`;
            root.errorKind = "key";
            return;
        }

        const token = ++root._requestToken;
        root.loading = true;
        root.error = "";
        root.errorKind = "";

        root.resolveLocation(location => {
            if (token !== root._requestToken)
                return;
            root.resolvedLocation = location;
            if (!root.providerSupportsLocation(provider, location)) {
                // A national source cannot answer for this place. Keep the app usable by
                // falling back to a worldwide source instead of leaving stale data on screen.
                if (provider.id !== "openMeteo") {
                    root.settings.provider = "openMeteo";
                    root.settings.lastProvider = "openMeteo";
                    root.loading = false;
                    root.refresh(true);
                } else {
                    root.fail(`${provider.name} does not cover ${location.name || "this place"}.`, "location");
                }
                return;
            }
            if (provider.id === "accuWeather") {
                root.fetchAccuWeather(provider, location, token);
                return;
            }
            const model = provider.model || root.settings.openMeteoModel;
            const request = Providers.buildRequest(provider.id, {
                location: location,
                apiKey: root.currentApiKey,
                model: model
            });
            if (!request) {
                root.fail(`${provider.name} is not configured.`, "provider");
                return;
            }
            root.httpGet(request.url, request.headers, response => {
                if (token !== root._requestToken)
                    return;
                let parsed;
                try {
                    const json = JSON.parse(response);
                    parsed = Providers.parse(provider.id, json, {
                        location: location,
                        apiKey: root.currentApiKey,
                        model: model
                    });
                } catch (e) {
                    root.fail(`Couldn't read the forecast from ${provider.name}: ${e.message || e}`, "provider");
                    return;
                }
                if (!parsed) {
                    root.fail(`${provider.name} returned no usable forecast.`, "provider");
                    return;
                }
                root.finish(parsed, token);
            }, (status, body) => {
                if (token !== root._requestToken)
                    return;
                root.handleHttpFailure(status, body, provider);
            });
        }, message => {
            if (token !== root._requestToken)
                return;
            root.fail(message, "location");
        });
    }

    function resolveLocation(callback, failure) {
        if (root.settings.useGps && root.gpsValid && Date.now() - root.gpsUpdatedAt < 10 * 60000) {
            callback(root.normalizeLocation({
                name: root.gpsName,
                country: root.activeLocation?.country || "",
                latitude: root.gpsLatitude,
                longitude: root.gpsLongitude,
                timezone: root.activeLocation?.timezone || "",
                utcOffset: root.activeLocation?.utcOffset
            }));
            return;
        }

        const saved = root.activeLocation;
        if (saved && root.isUsableLocation(saved)) {
            callback(root.normalizeLocation(saved));
            return;
        }

        if (saved && String(saved.name || "").length > 0) {
            root.geocodeFirst(saved.name, location => {
                const merged = Object.assign({}, saved, location);
                root.replaceActiveLocation(merged);
                callback(root.normalizeLocation(merged));
            }, failure);
            return;
        }

        const city = root.defaultCity();
        if (city.length > 0) {
            root.geocodeFirst(city, location => {
                const locations = root.savedLocations.slice();
                locations.push(location);
                root.writeLocations(locations);
                root.settings.activeLocation = locations.length - 1;
                callback(location);
            }, failure);
            return;
        }

        root.locateByIp(callback, failure);
    }


    // ── AccuWeather's two-step API ─────────────────────────────────────
    function fetchAccuWeather(provider, location, token) {
        const cacheKey = `${Number(location.latitude).toFixed(3)},${Number(location.longitude).toFixed(3)}`;
        const cached = root._accuWeatherKeys[cacheKey];
        if (cached) {
            root.fetchAccuWeatherForecast(provider, location, cached, token);
            return;
        }
        const request = Providers.accuWeatherLocationRequest(root.currentApiKey, location);
        root.httpGet(request.url, request.headers, response => {
            if (token !== root._requestToken)
                return;
            let json;
            try {
                json = JSON.parse(response);
            } catch (e) {
                root.fail(`Couldn't read the AccuWeather location for ${location.name || "this place"}: ${e.message || e}`, "provider");
                return;
            }
            const key = Providers.accuWeatherLocationKey(json);
            if (!key) {
                root.fail("AccuWeather could not find this place. Try another location or source.", "location");
                return;
            }
            root._accuWeatherKeys[cacheKey] = key;
            root.fetchAccuWeatherForecast(provider, location, key, token);
        }, (status, body) => {
            if (token !== root._requestToken)
                return;
            root.handleHttpFailure(status, body, provider);
        });
    }

    function fetchAccuWeatherForecast(provider, location, locationKey, token) {
        const requests = Providers.accuWeatherRequests(locationKey, root.currentApiKey);
        if (!requests || requests.length === 0) {
            root.fail(`${provider.name} is not configured.`, "provider");
            return;
        }
        const responses = {};
        let remaining = requests.length;
        let failed = false;

        const failOnce = (message, kind) => {
            if (failed)
                return;
            failed = true;
            root.fail(message, kind || "provider");
        };

        for (const request of requests) {
            root.httpGet(request.url, request.headers, response => {
                if (failed || token !== root._requestToken)
                    return;
                try {
                    responses[request.name] = JSON.parse(response);
                } catch (e) {
                    failOnce(`Couldn't read the ${request.name} forecast from ${provider.name}: ${e.message || e}`, "provider");
                    return;
                }
                remaining -= 1;
                if (remaining > 0)
                    return;

                let parsed;
                try {
                    parsed = Providers.parseAccuWeather(responses, {
                        location: Object.assign({}, location, { accuWeatherKey: locationKey })
                    });
                } catch (e) {
                    failOnce(`Couldn't read the forecast from ${provider.name}: ${e.message || e}`, "provider");
                    return;
                }
                if (!parsed) {
                    failOnce(`${provider.name} returned no usable forecast.`, "provider");
                    return;
                }
                root.resolvedLocation = Object.assign({}, root.resolvedLocation, {
                    accuWeatherKey: locationKey,
                    utcOffset: parsed.utcOffset
                });
                root.finish(parsed, token);
            }, (status, body) => {
                if (failed || token !== root._requestToken)
                    return;
                failed = true;
                root.handleHttpFailure(status, body, provider);
            });
        }
    }

    function providerSupportsLocation(provider, location) {
        if (provider.id === "brightSky") {
            const country = String(location.country || "").toLowerCase();
            return country.indexOf("germany") >= 0 || country === "de" || country === "deutschland";
        }
        return true;
    }

    function replaceActiveLocation(location) {
        const locations = root.savedLocations.slice();
        if (locations.length === 0)
            locations.push(location);
        else
            locations[root.activeLocationIndex] = Object.assign({}, locations[root.activeLocationIndex], location);
        root.writeLocations(locations);
    }

    function geocodeFirst(name, callback, failure) {
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=1&language=en&format=json`;
        root.httpGet(url, { "Accept": "application/json" }, response => {
            try {
                const json = JSON.parse(response);
                if (!json.results || json.results.length === 0) {
                    failure(`Couldn't find “${name}”. Choose a city in Settings.`);
                    return;
                }
                const result = json.results[0];
                callback(root.normalizeLocation({
                    id: result.id,
                    name: result.name,
                    admin1: result.admin1 || result.admin2 || "",
                    country: result.country || "",
                    latitude: result.latitude,
                    longitude: result.longitude,
                    timezone: result.timezone || "",
                    utcOffset: root.estimateOffset(result.longitude, result.latitude)
                }));
            } catch (e) {
                failure(`Couldn't read the location result for “${name}”.`);
            }
        }, status => {
            failure(status === 0 ? "Couldn't reach the location service." : `Location lookup failed (HTTP ${status}).`);
        });
    }

    function locateByIp(callback, failure) {
        root.httpGet("https://ipinfo.io/json", { "Accept": "application/json" }, response => {
            try {
                const json = JSON.parse(response);
                if (!json.loc) {
                    failure("Couldn't determine your location from the network. Choose a city in Settings.");
                    return;
                }
                const parts = String(json.loc).split(",");
                const location = root.normalizeLocation({
                    id: "ip",
                    name: json.city || json.region || "Current location",
                    admin1: json.region || "",
                    country: json.country || "",
                    latitude: Number(parts[0]),
                    longitude: Number(parts[1]),
                    timezone: json.timezone || "",
                    utcOffset: undefined
                });
                if (!location) {
                    failure("The network location service returned invalid coordinates.");
                    return;
                }
                const locations = root.savedLocations.slice();
                locations.push(location);
                root.writeLocations(locations);
                root.settings.activeLocation = locations.length - 1;
                callback(location);
            } catch (e) {
                failure("Couldn't read the network location service response.");
            }
        }, status => {
            root.httpGet("https://ipapi.co/json/", { "Accept": "application/json" }, fallback => {
                try {
                    const json = JSON.parse(fallback);
                    if (!Number.isFinite(Number(json.latitude)) || !Number.isFinite(Number(json.longitude))) {
                        failure("Couldn't determine your location from the network. Choose a city in Settings.");
                        return;
                    }
                    const location = root.normalizeLocation({
                        id: "ip",
                        name: json.city || json.region || "Current location",
                        admin1: json.region || "",
                        country: json.country_name || json.country || "",
                        latitude: Number(json.latitude),
                        longitude: Number(json.longitude),
                        timezone: json.timezone || "",
                        utcOffset: undefined
                    });
                    const locations = root.savedLocations.slice();
                    locations.push(location);
                    root.writeLocations(locations);
                    root.settings.activeLocation = locations.length - 1;
                    callback(location);
                } catch (e) {
                    failure("Couldn't determine your location from the network. Choose a city in Settings.");
                }
            }, () => {
                failure(status === 0 ? "Couldn't determine your location from the network. Choose a city in Settings." : `Network location failed (HTTP ${status}).`);
            });
        });
    }

    function finish(parsed, token) {
        let enriched;
        try {
            enriched = Astro.enrich(parsed);
        } catch (e) {
            root.fail(`The forecast was fetched but its astronomy could not be calculated: ${e.message || e}`, "provider");
            return;
        }
        root.data = enriched;
        root.loading = false;
        root.error = "";
        root.errorKind = "";
        root.lastFetchTime = Date.now();
        root.dataRefreshed();
        if (root.settings.includeAirQuality)
            root.fetchAirQuality(root.resolvedLocation, token);
    }

    function fail(message, kind) {
        root.loading = false;
        root.error = message;
        root.errorKind = kind || "provider";
    }

    function handleHttpFailure(status, body, provider) {
        let message = `Couldn't refresh from ${provider.name}`;
        let kind = "network";
        if (status === 401 || status === 403) {
            kind = "key";
            if (provider.id === "openWeatherMap")
                message = "OpenWeatherMap rejected this API key. One Call 3.0 must be enabled for the key.";
            else if (provider.id === "weatherApi")
                message = "WeatherAPI.com rejected this API key. Check the key and that the free plan is active.";
            else if (provider.id === "pirateWeather")
                message = "Pirate Weather rejected this API key.";
            else if (provider.id === "accuWeather")
                message = "AccuWeather rejected this API key. Check it at developer.accuweather.com and the trial's daily call limit.";
            else if (provider.id === "metNo")
                message = "MET Norway rejected the request. Its API requires an identifying User-Agent.";
            else
                message = `${provider.name} rejected the API key.`;
        } else if (status === 429) {
            message = `${provider.name} is rate-limiting this app. Try again in a little while.`;
        } else if (status === 404 && provider.id === "brightSky") {
            kind = "location";
            message = "Bright Sky only covers Germany, and has no data for this location.";
        } else if (status === 0) {
            message = `Couldn't reach ${provider.name}. Check the network connection.`;
        } else {
            message += ` (HTTP ${status}).`;
        }
        root.fail(message, kind);
    }

    function fetchAirQuality(location, token) {
        if (!location || !Number.isFinite(Number(location.latitude)))
            return;
        root.airQualityLoading = true;
        const request = Providers.airQualityRequest(location);
        root.httpGet(request.url, request.headers, response => {
            if (token !== root._requestToken)
                return;
            try {
                const json = JSON.parse(response);
                root.data = Providers.mergeAirQuality(root.data, json);
            } catch (e) {
                // Air quality is a supplement. A parse failure must not hide the weather.
            }
            root.airQualityLoading = false;
        }, () => {
            if (token === root._requestToken)
                root.airQualityLoading = false;
        });
    }





    function httpGet(url, headers, success, failure) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 22000;
        const allHeaders = Object.assign({
            "User-Agent": "ii-weather/1.0 (Quickshell; github.com/end-4/dots-hyprland)",
            "Accept": "application/json, text/plain, */*"
        }, headers || {});
        for (const key in allHeaders)
            xhr.setRequestHeader(key, allHeaders[key]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status >= 200 && xhr.status < 300)
                success(xhr.responseText);
            else
                failure(xhr.status, xhr.responseText);
        };
        xhr.ontimeout = function() { failure(0, "timeout"); };
        xhr.onerror = function() { failure(0, "network"); };
        xhr.send();
    }

    // ── Active-window lifecycle ─────────────────────────────────────────
    onActiveChanged: {
        if (root.active) {
            if (!root.ready) {
                root._pendingRefresh = true;
                root._pendingForce = false;
            } else if (!root.hasData || root.stale) {
                root.refresh(false);
            }
            if (root.settings.useGps)
                gpsFallbackTimer.restart();
        } else {
            gpsFallbackTimer.stop();
        }
    }

    onReadyChanged: {
        if (root.ready && root._pendingRefresh && root.active) {
            root._pendingRefresh = false;
            root.refresh(root._pendingForce);
        }
    }

    // ── Timers ──────────────────────────────────────────────────────────
    Timer {
        interval: Math.max(5, root.settings.refreshMinutes) * 60000
        running: root.active && root.ready && !root.loading
        repeat: true
        onTriggered: root.refresh(true)
    }

    Timer {
        id: gpsFallbackTimer
        interval: 15000
        repeat: false
        onTriggered: {
            if (!root.settings.useGps || !root.active)
                return;
            if (!root.gpsValid) {
                root.gpsServiceFailed = true;
                root.settings.useGps = false;
                root.error = "GPS is taking too long. Showing your saved location instead.";
                root.errorKind = "location";
                root.refresh(true);
            }
        }
    }

    Timer {
        id: writeTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root._settingsReady && !root.blockWrites)
                settingsFile.writeAdapter();
        }
    }

    // Created only when GPS is on: building a PositionSource makes a blocking
    // D-Bus call to geoclue when that service is not answering.
    Loader {
        id: positionLoader
        active: root.settings.useGps && root.active
        onLoaded: if (root.settings.useGps && root.active) item.start()
        sourceComponent: PositionSource {
            id: positionSource
            updateInterval: 60000
            onPositionChanged: root.handleGpsPosition(position)
            onValidityChanged: {
                if (!positionSource.valid && root.settings.useGps)
                    root.handleGpsFailure();
            }
        }
    }

    FileView {
        id: settingsFile
        path: root.settingsPath
        atomicWrites: true
        blockWrites: root.blockWrites
        onAdapterUpdated: {
            if (root._settingsReady && !root.blockWrites)
                writeTimer.restart();
        }
        onLoaded: {
            root._settingsReady = true;
            root.ready = true;
            root.normalizeSettings();
            if (root.active && (!root.hasData || root.stale))
                root.refresh(false);
        }
        onLoadFailed: error => {
            root._settingsReady = true;
            root.ready = true;
            if (error === FileViewError.FileNotFound) {
                root.normalizeSettings();
                writeTimer.restart();
            } else {
                root.settingsError = `Couldn't read the weather settings file (${error}). Changes will be written to ${root.settingsPath}.`;
                root.normalizeSettings();
                writeTimer.restart();
            }
        }
        adapter: JsonAdapter {
            id: settingsAdapter
            property string provider: "openMeteo"
            property string openMeteoModel: "best_match"
            property string apiKeysJson: "{}"
            property string locationsJson: "[]"
            property int activeLocation: 0
            property bool useGps: false
            property string unitsJson: "{\"temperature\":\"c\",\"wind\":\"kmh\",\"precip\":\"mm\",\"pressure\":\"hpa\",\"visibility\":\"km\",\"distance\":\"km\"}"
            property int refreshMinutes: 10
            property bool includeAirQuality: true
            property string accentMode: "theme"
            property string overviewOrderJson: "[]"
            property string lastProvider: "openMeteo"
        }
    }

    property alias settings: settingsAdapter

    Component.onDestruction: {
        root.blockWrites = true;
        gpsFallbackTimer.stop();
    }
}
