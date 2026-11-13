// Weather providers for the ii Weather app.
//
// Every provider is normalized into one shape so the UI never has to know which
// service answered: temperatures in °C, wind in km/h, precipitation in mm,
// pressure in hPa, visibility in km and timestamps in epoch milliseconds.
//
// Adding a provider means adding an entry to PROVIDERS, a buildRequest case,
// a parse case and (when it publishes alerts separately) an alertsRequest /
// parseAlerts case. Everything else in the app follows.

// ── Small helpers ───────────────────────────────────────────────────────────

function num(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : (fallback === undefined ? null : fallback);
}

function firstFinite(values, fallback) {
    for (let i = 0; i < values.length; i++) {
        const n = Number(values[i]);
        if (Number.isFinite(n))
            return n;
    }
    return fallback === undefined ? null : fallback;
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function fToC(value) {
    return value === null || value === undefined ? null : (Number(value) - 32) * 5 / 9;
}

function mphToKmh(value) {
    return value === null || value === undefined ? null : Number(value) * 1.609344;
}

function mpsToKmh(value) {
    return value === null || value === undefined ? null : Number(value) * 3.6;
}

function inchToMm(value) {
    return value === null || value === undefined ? null : Number(value) * 25.4;
}

function mileToKm(value) {
    return value === null || value === undefined ? null : Number(value) * 1.609344;
}

function feetToKm(value) {
    return value === null || value === undefined ? null : Number(value) * 0.0003048;
}

function secToMs(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n * 1000 : null;
}

function isoToMs(value) {
    if (!value)
        return null;
    const ms = Date.parse(value);
    return Number.isFinite(ms) ? ms : null;
}

// Open-Meteo returns "2026-10-26T08:15" in the location's local time, with the
// offset supplied separately. Date.parse would read that as the machine's own
// timezone, so anchor it to UTC and subtract the location offset.
function localIsoToMs(value, offsetSeconds) {
    if (!value)
        return null;
    let text = String(value);
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(text))
        text += ":00";
    text += "Z";
    const ms = Date.parse(text);
    return Number.isFinite(ms) ? ms - num(offsetSeconds, 0) * 1000 : null;
}

function localDayStartMs(ms, offsetSeconds) {
    const offset = num(offsetSeconds, 0) * 1000;
    return Math.floor((ms + offset) / 86400000) * 86400000 - offset;
}

function localDateKey(ms, offsetSeconds) {
    return new Date(ms + num(offsetSeconds, 0) * 1000).toISOString().slice(0, 10);
}

function dayKeyToMs(key, offsetSeconds) {
    return Date.parse(key + "T00:00:00Z") - num(offsetSeconds, 0) * 1000;
}

function offsetFromIso(value) {
    if (!value)
        return 0;
    const match = /([+-])(\d{2}):(\d{2})$/.exec(String(value));
    if (!match)
        return 0;
    const sign = match[1] === "-" ? -1 : 1;
    return sign * (Number(match[2]) * 3600 + Number(match[3]) * 60);
}

function offsetFromZoneName(timezone, fallback) {
    // QML's JS engine has no Intl, but a longitude estimate is enough for
    // deciding which local day an hourly point belongs to. Providers that know
    // their offset (all the JSON ones) pass it explicitly instead.
    if (Number.isFinite(fallback))
        return fallback;
    return 0;
}

function estimatedOffsetFromLongitude(longitude) {
    return Math.round(num(longitude, 0) / 15) * 3600;
}

function avg(values) {
    let sum = 0, count = 0;
    for (const v of values) {
        if (Number.isFinite(v)) {
            sum += v;
            count++;
        }
    }
    return count > 0 ? sum / count : null;
}

function maxOf(values) {
    let result = null;
    for (const v of values) {
        if (Number.isFinite(v))
            result = result === null ? v : Math.max(result, v);
    }
    return result;
}

function minOf(values) {
    let result = null;
    for (const v of values) {
        if (Number.isFinite(v))
            result = result === null ? v : Math.min(result, v);
    }
    return result;
}

function dewPointC(tempC, humidity) {
    const t = Number(tempC), rh = Number(humidity);
    if (!Number.isFinite(t) || !Number.isFinite(rh) || rh <= 0)
        return null;
    const a = 17.27, b = 237.7;
    const alpha = (a * t) / (b + t) + Math.log(clamp(rh, 1, 100) / 100);
    return (b * alpha) / (a - alpha);
}

// ── Weather codes ───────────────────────────────────────────────────────────
// The canonical code is a WMO 4677 code, the same vocabulary Open-Meteo uses.
// Everything else is translated on the way in.

function wmoToWwo(code) {
    const c = Number(code);
    if (c === 0 || c === 1) return 113;
    if (c === 2) return 116;
    if (c === 3) return 122;
    if (c === 45 || c === 48) return 248;
    if (c === 51 || c === 53 || c === 55) return 266;
    if (c === 56 || c === 57) return 284;
    if (c === 61 || c === 63 || c === 65) return 296;
    if (c === 66 || c === 67) return 311;
    if (c === 71 || c === 73 || c === 75 || c === 77) return 332;
    if (c === 80 || c === 81 || c === 82) return 353;
    if (c === 85 || c === 86) return 368;
    if (c === 95) return 386;
    if (c === 96 || c === 99) return 389;
    return 113;
}

function conditionText(code) {
    const c = Number(code);
    if (c === 0) return "Clear sky";
    if (c === 1) return "Mainly clear";
    if (c === 2) return "Partly cloudy";
    if (c === 3) return "Overcast";
    if (c === 45) return "Fog";
    if (c === 48) return "Depositing rime fog";
    if (c === 51) return "Light drizzle";
    if (c === 53) return "Moderate drizzle";
    if (c === 55) return "Dense drizzle";
    if (c === 56) return "Light freezing drizzle";
    if (c === 57) return "Dense freezing drizzle";
    if (c === 61) return "Slight rain";
    if (c === 63) return "Moderate rain";
    if (c === 65) return "Heavy rain";
    if (c === 66) return "Light freezing rain";
    if (c === 67) return "Heavy freezing rain";
    if (c === 71) return "Slight snow";
    if (c === 73) return "Moderate snow";
    if (c === 75) return "Heavy snow";
    if (c === 77) return "Snow grains";
    if (c === 80) return "Slight rain showers";
    if (c === 81) return "Moderate rain showers";
    if (c === 82) return "Violent rain showers";
    if (c === 85) return "Slight snow showers";
    if (c === 86) return "Heavy snow showers";
    if (c === 95) return "Thunderstorm";
    if (c === 96) return "Thunderstorm with slight hail";
    if (c === 99) return "Thunderstorm with heavy hail";
    return "Unknown conditions";
}

function wwoToWmo(code) {
    const c = Number(code);
    // Clear / cloud cover
    if (c === 113) return 0;
    if (c === 116) return 2;
    if (c === 119 || c === 122) return 3;
    // Fog and mist
    if (c === 143 || c === 248) return 45;
    if (c === 260) return 48;
    // Drizzle
    if (c === 263) return 51;
    if (c === 266) return 53;
    // Freezing drizzle / rain
    if (c === 185 || c === 281) return 56;
    if (c === 284) return 57;
    if (c === 182 || c === 311 || c === 317) return 66;
    if (c === 314 || c === 320) return 67;
    // Rain
    if (c === 176 || c === 293 || c === 296) return 61;
    if (c === 299 || c === 302) return 63;
    if (c === 305 || c === 308) return 65;
    // Showers
    if (c === 353) return 80;
    if (c === 356 || c === 359) return 82;
    // Snow
    if (c === 179 || c === 227 || c === 323 || c === 326) return 71;
    if (c === 329 || c === 332) return 73;
    if (c === 230 || c === 335 || c === 338) return 75;
    // Sleet / snow showers
    if (c === 317 || c === 320) return 66;
    if (c === 362) return 85;
    if (c === 365) return 86;
    if (c === 368) return 85;
    if (c === 371) return 86;
    // Ice pellets
    if (c === 350 || c === 374 || c === 377) return 77;
    // Thunder
    if (c === 200 || c === 386 || c === 389) return 95;
    if (c === 392 || c === 395) return 95;
    return 3;
}

function owmToWmo(id, icon) {
    const c = Number(id);
    if (c >= 200 && c < 300) return 95;
    if (c >= 300 && c < 400) return c === 300 || c === 301 ? 51 : (c === 302 ? 53 : 55);
    if (c >= 500 && c < 600) {
        if (c === 511) return 66;
        if (c >= 520) return c === 520 ? 80 : (c === 521 ? 81 : 82);
        if (c === 500) return 61;
        if (c === 501) return 63;
        return 65;
    }
    if (c >= 600 && c < 700) {
        if (c === 611 || c === 612 || c === 613) return 66;
        if (c === 615 || c === 616) return 67;
        if (c >= 620) return c === 620 ? 85 : 86;
        if (c === 600) return 71;
        if (c === 601) return 73;
        return 75;
    }
    if (c >= 700 && c < 800) return 45;
    if (c === 800) return 0;
    if (c === 801 || c === 802) return 2;
    if (c === 803 || c === 804) return 3;
    if (String(icon || "").endsWith("n"))
        return c === 800 ? 0 : 2;
    return 3;
}

function metSymbolToWmo(symbol) {
    const s = String(symbol || "").toLowerCase();
    if (s.indexOf("thunder") >= 0) return s.indexOf("hail") >= 0 ? 96 : 95;
    if (s.indexOf("heavyrain") >= 0) return 65;
    if (s.indexOf("rain") >= 0) return s.indexOf("light") >= 0 ? 61 : 63;
    if (s.indexOf("heavysleet") >= 0) return 67;
    if (s.indexOf("sleet") >= 0) return 66;
    if (s.indexOf("heavysnow") >= 0) return 75;
    if (s.indexOf("snow") >= 0) return s.indexOf("light") >= 0 ? 71 : 73;
    if (s.indexOf("fog") >= 0) return 45;
    if (s.indexOf("cloudy") >= 0) return s.indexOf("partly") >= 0 ? 2 : 3;
    if (s.indexOf("fair") >= 0) return 1;
    if (s.indexOf("clear") >= 0) return 0;
    return 3;
}

function iconToWmo(icon) {
    const s = String(icon || "").toLowerCase();
    if (s.indexOf("thunder") >= 0) return 95;
    if (s.indexOf("hail") >= 0) return 96;
    if (s.indexOf("sleet") >= 0) return 66;
    if (s.indexOf("snow") >= 0) return 71;
    if (s.indexOf("rain") >= 0 || s.indexOf("drizzle") >= 0 || s.indexOf("shower") >= 0) return 61;
    if (s.indexOf("fog") >= 0) return 45;
    if (s.indexOf("partly") >= 0) return 2;
    if (s.indexOf("cloud") >= 0 || s.indexOf("overcast") >= 0) return 3;
    if (s.indexOf("clear") >= 0 || s.indexOf("sun") >= 0) return 0;
    return 3;
}

function isNightIcon(icon) {
    return /night|n$/.test(String(icon || "").toLowerCase());
}

// AccuWeather reports values inside Metric/Imperial objects. Requests use
// metric=true, but the object shapes differ between endpoints, so read Metric
// first and convert a stray imperial value when necessary.
function accuValue(object, kind) {
    if (!object)
        return null;
    const metric = object.Metric && object.Metric.Value !== undefined ? num(object.Metric.Value) : null;
    let value = metric !== null ? metric : num(object.Value);
    if (value === null)
        return null;
    const unit = String(object.Unit || "").toLowerCase();
    if (kind === "temp" && (unit === "f" || unit === "fahrenheit"))
        value = fToC(value);
    else if (kind === "speed" && (unit === "mi/h" || unit === "mph"))
        value = value * 1.609344;
    else if (kind === "precip" && unit === "in")
        value = value * 25.4;
    else if (kind === "snow" && unit === "in")
        value = value * 2.54;
    else if (kind === "snow" && unit === "mm")
        value = value / 10;
    else if (kind === "pressure" && (unit === "inhg" || unit === "in"))
        value = value * 33.8639;
    else if (kind === "distance" && unit === "mi")
        value = value * 1.609344;
    return value;
}

function accuWeatherToWmo(icon, phrase) {
    const text = String(phrase || "").toLowerCase();
    if (text.length > 0) {
        if (text.indexOf("thunder") >= 0) return text.indexOf("hail") >= 0 ? 96 : 95;
        if (text.indexOf("freezing") >= 0 && (text.indexOf("rain") >= 0 || text.indexOf("drizzle") >= 0)) return 66;
        if (text.indexOf("sleet") >= 0 || text.indexOf("ice") >= 0) return 66;
        if (text.indexOf("snow") >= 0) return text.indexOf("light") >= 0 ? 71 : (text.indexOf("heavy") >= 0 ? 75 : 73);
        if (text.indexOf("rain") >= 0 || text.indexOf("shower") >= 0 || text.indexOf("drizzle") >= 0) return text.indexOf("heavy") >= 0 ? 65 : 61;
        if (text.indexOf("fog") >= 0) return 45;
        if (text.indexOf("partly") >= 0 || text.indexOf("intermittent") >= 0) return 2;
        if (text.indexOf("cloud") >= 0 || text.indexOf("overcast") >= 0) return 3;
        if (text.indexOf("clear") >= 0 || text.indexOf("sun") >= 0) return text.indexOf("mostly") >= 0 ? 1 : 0;
    }
    const code = Number(icon);
    if (code <= 2) return 0;
    if (code <= 5) return 2;
    if (code <= 8) return 3;
    if (code <= 10) return 45;
    if (code <= 14) return 61;
    if (code <= 17) return 95;
    if (code <= 29) return 71;
    if (code === 30 || code === 31 || code === 32) return 3;
    if (code <= 37) return 0;
    if (code <= 40) return 61;
    if (code <= 42) return 95;
    return 3;
}

function accuEpochMs(value) {
    const seconds = Number(value);
    return Number.isFinite(seconds) ? seconds * 1000 : null;
}


// ── Provider catalogue ─────────────────────────────────────────────────────

const PROVIDERS = [
    {
        id: "openMeteo",
        name: "Open-Meteo (best match)",
        shortName: "Open-Meteo",
        description: "Free global forecast using Open-Meteo's automatic best-match model. No account or key.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoEcmwf",
        name: "ECMWF IFS",
        shortName: "ECMWF IFS",
        description: "Global medium-range model from the European Centre for Medium-Range Weather Forecasts. Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "ecmwf_ifs025",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoIcon",
        name: "DWD ICON",
        shortName: "DWD ICON",
        description: "Global forecast from the German national weather service (DWD). Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "dwd_icon",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoGfs",
        name: "NOAA GFS",
        shortName: "NOAA GFS",
        description: "Global forecast from the US National Weather Service. Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "gfs_seamless",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoMeteoFrance",
        name: "Météo-France",
        shortName: "Météo-France",
        description: "Global blend from Météo-France. Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "meteofrance_seamless",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoJma",
        name: "JMA",
        shortName: "JMA",
        description: "Global forecast from the Japan Meteorological Agency. Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "jma_seamless",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoUkmo",
        name: "UK Met Office",
        shortName: "UK Met Office",
        description: "Global forecast from the UK Met Office. Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "ukmo_seamless",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "openMeteoGem",
        name: "Environment Canada",
        shortName: "Environment Canada",
        description: "Global forecast from Environment and Climate Change Canada. Delivered through Open-Meteo; no account or key required.",
        requiresKey: false,
        keyUrl: "https://open-meteo.com/",
        supportsModels: false,
        supportsAlerts: false,
        supportsMinutely: true,
        dailyDays: 16,
        region: "Worldwide",
        model: "gem_seamless",
        attribution: "Weather data by Open-Meteo.com · CC BY 4.0",
        url: "https://open-meteo.com/"
    },
    {
        id: "metNo",
        name: "MET Norway",
        shortName: "MET Norway",
        description: "The Norwegian Meteorological Institute's global forecast. No API key, but requests identify this app.",
        requiresKey: false,
        keyUrl: "https://developer.met.no/",
        supportsModels: false,
        supportsAlerts: true,
        supportsMinutely: false,
        dailyDays: 10,
        region: "Worldwide",
        attribution: "Data from MET Norway · NLOD / CC BY 4.0",
        url: "https://www.met.no/"
    },
    {
        id: "brightSky",
        name: "Bright Sky (DWD)",
        shortName: "Bright Sky",
        description: "Open German Weather Service data for Germany. No API key; observations and forecasts are station-based.",
        requiresKey: false,
        keyUrl: "https://brightsky.dev/",
        supportsModels: false,
        supportsAlerts: true,
        supportsMinutely: false,
        dailyDays: 8,
        region: "Germany",
        attribution: "Data by Bright Sky · Deutscher Wetterdienst (DWD)",
        url: "https://brightsky.dev/"
    }
];

const OPEN_METEO_MODELS = [
    { id: "best_match", name: "Best match", note: "Open-Meteo picks the best model for the location" },
    { id: "ecmwf_ifs025", name: "ECMWF IFS 0.25°", note: "European Centre for Medium-Range Weather Forecasts" },
    { id: "dwd_icon", name: "DWD ICON", note: "Deutscher Wetterdienst global model" },
    { id: "gfs_seamless", name: "NOAA GFS", note: "US Global Forecast System" },
    { id: "meteofrance_seamless", name: "Météo-France", note: "AROME / ARPEGE blend" },
    { id: "jma_seamless", name: "JMA", note: "Japan Meteorological Agency" },
    { id: "ukmo_seamless", name: "UK Met Office", note: "UKMO global model" },
    { id: "gem_seamless", name: "Environment Canada", note: "GEM global model" }
];

function providerById(id) {
    return PROVIDERS.find(provider => provider.id === String(id)) || PROVIDERS[0];
}

function modelById(id) {
    return OPEN_METEO_MODELS.find(model => model.id === String(id)) || OPEN_METEO_MODELS[0];
}

function catalog() {
    return PROVIDERS;
}

function models() {
    return OPEN_METEO_MODELS;
}

// ── Requests ────────────────────────────────────────────────────────────────

const USER_AGENT = "ii-weather/1.0 (Quickshell; github.com/end-4/dots-hyprland)";

function jsonHeaders(extra) {
    const headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT
    };
    if (extra) {
        for (const key in extra)
            headers[key] = extra[key];
    }
    return headers;
}

function buildRequest(providerId, ctx) {
    const provider = providerById(providerId);
    const lat = Number(ctx.location.latitude);
    const lon = Number(ctx.location.longitude);
    const key = String(ctx.apiKey || "");

    if (provider.id.startsWith("openMeteo")) {
        const model = ctx.model && ctx.model !== "best_match" ? "&models=" + encodeURIComponent(ctx.model) : "";
        const url = "https://api.open-meteo.com/v1/forecast"
            + `?latitude=${lat}&longitude=${lon}`
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,rain,snowfall,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,visibility,dew_point_2m"
            + "&hourly=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation_probability,precipitation,rain,snowfall,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,visibility,dew_point_2m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,daylight_duration,uv_index_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant"
            + "&minutely_15=precipitation,precipitation_probability"
            + "&timezone=auto&forecast_days=16&forecast_hours=72&forecast_minutely_15=48"
            + model;
        return { url: url, headers: jsonHeaders() };
    }

    if (provider.id === "metNo") {
        return {
            url: `https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=${lat.toFixed(4)}&lon=${lon.toFixed(4)}`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "openWeatherMap") {
        return {
            url: `https://api.openweathermap.org/data/3.0/onecall?lat=${lat}&lon=${lon}&units=metric&appid=${encodeURIComponent(key)}`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "weatherApi") {
        return {
            url: `https://api.weatherapi.com/v1/forecast.json?key=${encodeURIComponent(key)}&q=${lat},${lon}&days=14&aqi=no&alerts=yes`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "pirateWeather") {
        return {
            url: `https://api.pirateweather.net/forecast/${encodeURIComponent(key)}/${lat},${lon}?units=si&extend=hourly`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "infoplaza") {
        return {
            url: `https://api.infoplaza.com/weather/v1/forecast?latitude=${lat}&longitude=${lon}&token=${encodeURIComponent(key)}`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "brightSky") {
        const today = new Date();
        const start = today.toISOString().slice(0, 10);
        const end = new Date(today.getTime() + 7 * 86400000).toISOString().slice(0, 10);
        return {
            url: `https://api.brightsky.dev/weather?lat=${lat}&lon=${lon}&date=${start}&last_date=${end}`,
            headers: jsonHeaders()
        };
    }

    return null;
}


function accuWeatherLocationRequest(apiKey, location) {
    const key = encodeURIComponent(String(apiKey || ""));
    const query = encodeURIComponent(`${Number(location.latitude)},${Number(location.longitude)}`);
    return {
        url: `https://dataservice.accuweather.com/locations/v1/cities/geoposition/search?apikey=${key}&q=${query}&language=en-us&details=true`,
        headers: jsonHeaders()
    };
}

function accuWeatherLocationKey(json) {
    const item = Array.isArray(json) ? json[0] : json;
    return item && item.Key !== undefined ? String(item.Key) : "";
}

function accuWeatherRequests(locationKey, apiKey) {
    const key = encodeURIComponent(String(apiKey || ""));
    const place = encodeURIComponent(String(locationKey || ""));
    return [
        {
            name: "hourly",
            url: `https://dataservice.accuweather.com/forecasts/v1/hourly/12hour/${place}?apikey=${key}&details=true&metric=true&language=en-us`,
            headers: jsonHeaders()
        },
        {
            name: "daily",
            url: `https://dataservice.accuweather.com/forecasts/v1/daily/5day/${place}?apikey=${key}&details=true&metric=true&language=en-us`,
            headers: jsonHeaders()
        }
    ];
}




function stripAlertEmoji(value) {
    return String(value || "")
        .replace(/🔹|▪️|▪|▫/g, "\n• ")
        .replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, "")
        .replace(/[\u2600-\u27BF\uFE0F\u200D]/g, "")
        .replace(/\r\n/g, "\n")
        .replace(/[ \t]+\n/g, "\n")
        .replace(/\n{3,}/g, "\n\n")
        .replace(/[ \t]{2,}/g, " ")
        .trim();
}

function capText(value) {
    let text = String(value || "")
        .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
        .replace(/<br\s*\/?>/gi, "\n")
        .replace(/<\/p>/gi, "\n")
        .replace(/<[^>]+>/g, "")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"")
        .replace(/&#39;/g, "'")
        .replace(/&nbsp;/g, " ");
    return stripAlertEmoji(text);
}

function capTag(block, tag) {
    const match = new RegExp(`<(?:[\\w-]+:)?${tag}[^>]*>([\\s\\S]*?)<\\/(?:[\\w-]+:)?${tag}>`, "i").exec(block);
    return match ? capText(match[1]) : "";
}

function parseCapAlert(xml) {
    const text = String(xml || "");
    const infoMatches = text.match(/<(?:[\w-]+:)?info[^>]*>[\s\S]*?<\/(?:[\w-]+:)?info>/gi) || [];
    let info = infoMatches[0] || text;
    for (const block of infoMatches) {
        if (/<(?:[\w-]+:)?language[^>]*>\s*en/i.test(block)) {
            info = block;
            break;
        }
    }
    return {
        identifier: capTag(text, "identifier"),
        event: capTag(info, "event"),
        headline: capTag(info, "headline"),
        description: capTag(info, "description"),
        instruction: capTag(info, "instruction"),
        severity: capTag(info, "severity"),
        urgency: capTag(info, "urgency"),
        certainty: capTag(info, "certainty"),
        sender: capTag(info, "senderName") || capTag(text, "sender"),
        area: capTag(info, "areaDesc"),
        onset: isoToMs(capTag(info, "onset")),
        effective: isoToMs(capTag(info, "effective")),
        expires: isoToMs(capTag(info, "expires"))
    };
}

function wmoAlertsRequest(location) {
    const lat = Number(location.latitude);
    const lon = Number(location.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon))
        return null;
    // WMO SWIC takes POINT (lat lon), unlike the usual GeoJSON order. It returns
    // duplicate features for the same CAP file, which parseWmoAlerts deduplicates.
    const cql = `INTERSECTS(wkb_geometry, POINT (${lat} ${lon})) AND row_type NEQ 'BOUNDARY'`;
    return {
        url: "https://severeweather.wmo.int/f/wfs?request=GetFeature&version=1.1.0&outputFormat=json"
            + "&typeName=" + encodeURIComponent("local_postgis:postgis_geojsons")
            + "&cql_filter=" + encodeURIComponent(cql),
        headers: jsonHeaders()
    };
}

function parseWmoAlerts(json) {
    const severityName = value => ({4: "Extreme", 3: "Severe", 2: "Moderate", 1: "Minor"})[Number(value)] || "Unknown";
    const features = Array.isArray(json?.features) ? json.features : [];
    const alerts = [];
    const seen = {};
    for (const feature of features) {
        const props = feature?.properties;
        if (!props)
            continue;
        const start = isoToMs(props.onset || props.effective || props.sent);
        const end = isoToMs(props.expires);
        if (end !== null && end < Date.now())
            continue;
        const title = props.event || props.headline || "Weather alert";
        const key = String(props.identifier || props.capurl || feature.id || (title + "|" + start)).toLowerCase();
        if (seen[key])
            continue;
        seen[key] = true;
        alerts.push({
            id: key,
            title: stripAlertEmoji(title),
            description: stripAlertEmoji(props.description || props.areadesc || ""),
            severity: severityName(props.s),
            urgency: "Unknown",
            certainty: "Unknown",
            start: start,
            end: end,
            sender: "WMO SWIC",
            instruction: "",
            link: props.capurl ? "https://severeweather.wmo.int/v2/cap-alerts/" + props.capurl : ""
        });
    }
    return alerts;
}

function alertsRequest(providerId, ctx) {
    const provider = providerById(providerId);
    const lat = Number(ctx.location.latitude);
    const lon = Number(ctx.location.longitude);
    if (provider.id === "metNo") {
        return {
            url: `https://api.met.no/weatherapi/metalerts/2.0/current?lat=${lat.toFixed(4)}&lon=${lon.toFixed(4)}&lang=en`,
            headers: jsonHeaders()
        };
    }
    if (provider.id === "infoplaza") {
        return {
            url: `https://api.infoplaza.com/weather/v1/forecast?latitude=${lat}&longitude=${lon}&token=${encodeURIComponent(key)}`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "brightSky") {
        return {
            url: `https://api.brightsky.dev/alerts?lat=${lat}&lon=${lon}`,
            headers: jsonHeaders()
        };
    }
    return null;
}

// ── Air quality (supplement) ────────────────────────────────────────────────
// Open-Meteo's CAMS air quality endpoint is free and provider-independent, so
// every source gets the same pollutants and pollen charts.

function airQualityRequest(location) {
    const lat = Number(location.latitude);
    const lon = Number(location.longitude);
    const fields = "european_aqi,us_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen";
    return {
        url: `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${lon}&current=${fields}&hourly=${fields}&timezone=auto&forecast_days=5`,
        headers: jsonHeaders()
    };
}

const POLLEN_KEYS = ["alder", "birch", "grass", "mugwort", "olive", "ragweed"];

function pollenFromOpenMeteo(hourly, index) {
    const pollen = {};
    let total = 0;
    let any = false;
    for (const key of POLLEN_KEYS) {
        const value = num(hourly[key + "_pollen"]?.[index]);
        pollen[key] = value;
        if (value !== null) {
            any = true;
            total += value;
        }
    }
    pollen.total = any ? total : null;
    return pollen;
}

function mergeAirQuality(data, json) {
    if (!data || !json || !json.current)
        return data;
    const off = num(json.utc_offset_seconds, data.utcOffset || 0);
    const currentAq = json.current;
    const hourlyAq = json.hourly || {};
    const aqTimes = hourlyAq.time || [];
    const aqByHour = {};
    for (let i = 0; i < aqTimes.length; i++) {
        const ms = localIsoToMs(aqTimes[i], off);
        if (ms !== null)
            aqByHour[Math.floor((ms + off * 1000) / 3600000)] = i;
    }

    function aqIndexFor(ms) {
        return aqByHour[Math.floor((ms + off * 1000) / 3600000)];
    }

    function aqFields(index) {
        if (index === undefined)
            return {};
        return {
            aqi: num(hourlyAq.us_aqi?.[index]),
            europeanAqi: num(hourlyAq.european_aqi?.[index]),
            pm25: num(hourlyAq.pm2_5?.[index]),
            pm10: num(hourlyAq.pm10?.[index]),
            ozone: num(hourlyAq.ozone?.[index]),
            no2: num(hourlyAq.nitrogen_dioxide?.[index]),
            so2: num(hourlyAq.sulphur_dioxide?.[index]),
            co: num(hourlyAq.carbon_monoxide?.[index]),
            pollen: pollenFromOpenMeteo(hourlyAq, index)
        };
    }

    const hourly = (data.hourly || []).map(hour => {
        const fields = aqFields(aqIndexFor(hour.time));
        return Object.assign({}, hour, fields);
    });

    const currentFields = {
        aqi: num(currentAq.us_aqi),
        europeanAqi: num(currentAq.european_aqi),
        pm25: num(currentAq.pm2_5),
        pm10: num(currentAq.pm10),
        ozone: num(currentAq.ozone),
        no2: num(currentAq.nitrogen_dioxide),
        so2: num(currentAq.sulphur_dioxide),
        co: num(currentAq.carbon_monoxide),
        pollen: pollenFromOpenMeteo(currentAq, 0)
    };
    // The current object from Open-Meteo AQ does not use the hourly array's
    // shape, so read the pollen fields directly.
    const pollenCurrent = {};
    let pollenTotal = 0, pollenAny = false;
    for (const key of POLLEN_KEYS) {
        const value = num(currentAq[key + "_pollen"]);
        pollenCurrent[key] = value;
        if (value !== null) {
            pollenAny = true;
            pollenTotal += value;
        }
    }
    pollenCurrent.total = pollenAny ? pollenTotal : null;
    currentFields.pollen = pollenCurrent;

    const current = Object.assign({}, data.current, currentFields);

    const dailyMap = {};
    for (const hour of hourly) {
        const key = localDateKey(hour.time, off);
        if (!dailyMap[key])
            dailyMap[key] = { aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null };
        const day = dailyMap[key];
        for (const field of ["aqi", "pm25", "pm10", "ozone", "no2", "so2", "co"]) {
            if (hour[field] !== null && hour[field] !== undefined)
                day[field] = day[field] === null ? hour[field] : Math.max(day[field], hour[field]);
        }
        if (hour.pollen && hour.pollen.total !== null && hour.pollen.total !== undefined)
            day.pollenTotal = day.pollenTotal === null ? hour.pollen.total : Math.max(day.pollenTotal, hour.pollen.total);
    }

    const daily = (data.daily || []).map(day => {
        const key = localDateKey(day.time, off);
        const aq = dailyMap[key];
        if (!aq)
            return day;
        return Object.assign({}, day, {
            aqi: aq.aqi,
            pm25: aq.pm25,
            pm10: aq.pm10,
            ozone: aq.ozone,
            no2: aq.no2,
            so2: aq.so2,
            co: aq.co,
            pollenTotal: aq.pollenTotal
        });
    });

    const airQuality = {
        time: localIsoToMs(currentAq.time, off),
        aqi: currentFields.aqi,
        europeanAqi: currentFields.europeanAqi,
        pm25: currentFields.pm25,
        pm10: currentFields.pm10,
        ozone: currentFields.ozone,
        no2: currentFields.no2,
        so2: currentFields.so2,
        co: currentFields.co,
        pollen: currentFields.pollen,
        source: "Open-Meteo / CAMS"
    };

    return Object.assign({}, data, { current, hourly, daily, airQuality, utcOffset: data.utcOffset || off });
}

// ── Parsers ─────────────────────────────────────────────────────────────────

function parse(providerId, json, ctx) {
    const provider = providerById(providerId);
    if (provider.id.startsWith("openMeteo")) return parseOpenMeteo(json, ctx);
    if (provider.id === "metNo") return parseMetNo(json, ctx);
    if (provider.id === "openWeatherMap") return parseOpenWeatherMap(json, ctx);
    if (provider.id === "weatherApi") return parseWeatherApi(json, ctx);
    if (provider.id === "pirateWeather") return parsePirateWeather(json, ctx);
    if (provider.id === "infoplaza") return parseInfoplaza(json, ctx);
    if (provider.id === "brightSky") return parseBrightSky(json, ctx);
    return null;
}

function baseData(provider, ctx, extra) {
    const location = ctx.location || {};
    return Object.assign({
        providerId: provider.id,
        providerName: provider.name,
        model: provider.id === "openMeteo" ? (ctx.model || "best_match") : "",
        fetchedAt: Date.now(),
        timezone: location.timezone || "",
        utcOffset: num(location.utcOffset, 0),
        location: {
            name: location.name || "Current location",
            admin1: location.admin1 || "",
            country: location.country || "",
            latitude: num(location.latitude, 0),
            longitude: num(location.longitude, 0),
            timezone: location.timezone || "",
            utcOffset: num(location.utcOffset, 0)
        },
        current: {},
        hourly: [],
        daily: [],
        minutely: [],
        alerts: [],
        airQuality: { source: "Open-Meteo / CAMS" },
        source: {
            name: provider.name,
            attribution: provider.attribution,
            url: provider.url
        }
    }, extra || {});
}

function parseOpenMeteo(json, ctx) {
    if (!json || !json.current || !json.hourly || !json.daily)
        throw new Error("Open-Meteo returned no forecast");
    const provider = providerById("openMeteo");
    const off = num(json.utc_offset_seconds, 0);
    const hourlyJson = json.hourly;
    const dailyJson = json.daily;
    const currentJson = json.current;

    const hourly = [];
    for (let i = 0; i < (hourlyJson.time || []).length; i++) {
        hourly.push({
            time: localIsoToMs(hourlyJson.time[i], off),
            tempC: num(hourlyJson.temperature_2m?.[i]),
            feelsC: num(hourlyJson.apparent_temperature?.[i]),
            condition: num(hourlyJson.weather_code?.[i], 3),
            isDay: null,
            humidity: num(hourlyJson.relative_humidity_2m?.[i]),
            dewC: num(hourlyJson.dew_point_2m?.[i]),
            pressureHpa: num(hourlyJson.pressure_msl?.[i]),
            windKmh: num(hourlyJson.wind_speed_10m?.[i]),
            gustKmh: num(hourlyJson.wind_gusts_10m?.[i]),
            windDirDeg: num(hourlyJson.wind_direction_10m?.[i]),
            cloud: num(hourlyJson.cloud_cover?.[i]),
            visibilityKm: num(hourlyJson.visibility?.[i]) === null ? null : num(hourlyJson.visibility[i]) / 1000,
            uv: num(hourlyJson.uv_index?.[i]),
            precipMm: num(hourlyJson.precipitation?.[i], 0),
            precipProb: num(hourlyJson.precipitation_probability?.[i]),
            rainMm: num(hourlyJson.rain?.[i]),
            snowCm: num(hourlyJson.snowfall?.[i]),
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
        });
    }

    const daily = [];
    for (let i = 0; i < (dailyJson.time || []).length; i++) {
        daily.push({
            time: localIsoToMs(dailyJson.time[i] + "T00:00", off),
            maxC: num(dailyJson.temperature_2m_max?.[i]),
            minC: num(dailyJson.temperature_2m_min?.[i]),
            condition: num(dailyJson.weather_code?.[i], 3),
            summary: conditionText(num(dailyJson.weather_code?.[i], 3)),
            isDay: true,
            precipMm: num(dailyJson.precipitation_sum?.[i], 0),
            precipProb: num(dailyJson.precipitation_probability_max?.[i]),
            rainMm: num(dailyJson.rain_sum?.[i]),
            snowCm: num(dailyJson.snowfall_sum?.[i]),
            windKmh: num(dailyJson.wind_speed_10m_max?.[i]),
            gustKmh: num(dailyJson.wind_gusts_10m_max?.[i]),
            windDirDeg: num(dailyJson.wind_direction_10m_dominant?.[i]),
            humidity: null,
            pressureHpa: null,
            uv: num(dailyJson.uv_index_max?.[i]),
            cloud: null,
            visibilityKm: null,
            sunrise: localIsoToMs(dailyJson.sunrise?.[i], off),
            sunset: localIsoToMs(dailyJson.sunset?.[i], off),
            daylight: num(dailyJson.daylight_duration?.[i]),
            moonrise: null,
            moonset: null,
            moonPhase: null,
            moonIllum: null,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
        });
    }

    const currentTime = localIsoToMs(currentJson.time, off);
    let nearestIndex = 0;
    let nearestDistance = Infinity;
    for (let i = 0; i < hourly.length; i++) {
        const distance = Math.abs(hourly[i].time - currentTime);
        if (distance < nearestDistance) {
            nearestDistance = distance;
            nearestIndex = i;
        }
    }
    const nearestHour = hourly[nearestIndex] || {};
    const today = daily[0] || {};
    const current = {
        time: currentTime,
        tempC: num(currentJson.temperature_2m),
        feelsC: num(currentJson.apparent_temperature),
        condition: num(currentJson.weather_code, 3),
        summary: conditionText(num(currentJson.weather_code, 3)),
        isDay: currentJson.is_day === 1,
        humidity: num(currentJson.relative_humidity_2m),
        dewC: num(currentJson.dew_point_2m),
        pressureHpa: num(currentJson.pressure_msl),
        windKmh: num(currentJson.wind_speed_10m),
        gustKmh: num(currentJson.wind_gusts_10m),
        windDirDeg: num(currentJson.wind_direction_10m),
        cloud: num(currentJson.cloud_cover),
        visibilityKm: num(currentJson.visibility) === null ? null : num(currentJson.visibility) / 1000,
        uv: num(currentJson.uv_index),
        precipMm: num(currentJson.precipitation, 0),
        precipProb: nearestHour.precipProb,
        rainMm: num(currentJson.rain),
        snowCm: num(currentJson.snowfall),
        highC: today.maxC,
        lowC: today.minC,
        sunrise: today.sunrise,
        sunset: today.sunset,
        moonrise: null,
        moonset: null,
        moonPhase: null,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    };

    const minutely = [];
    const minutelyJson = json.minutely_15 || {};
    for (let i = 0; i < (minutelyJson.time || []).length; i++) {
        minutely.push({
            time: localIsoToMs(minutelyJson.time[i], off),
            precipMm: num(minutelyJson.precipitation?.[i], 0),
            precipProb: num(minutelyJson.precipitation_probability?.[i])
        });
    }

    return baseData(provider, Object.assign({}, ctx, { location: Object.assign({}, ctx.location, { utcOffset: off }) }), {
        timezone: json.timezone || ctx.location.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily,
        minutely: minutely
    });
}

function metSymbolIsDay(symbol) {
    const s = String(symbol || "");
    if (s.endsWith("_day")) return true;
    if (s.endsWith("_night")) return false;
    return null;
}

function parseMetNo(json, ctx) {
    const properties = json?.properties;
    const series = properties?.timeseries;
    if (!series || series.length === 0)
        throw new Error("MET Norway returned no forecast");
    const provider = providerById("metNo");
    const offset = num(ctx.location.utcOffset, estimatedOffsetFromLongitude(ctx.location.longitude));
    const hourly = [];

    for (let i = 0; i < series.length; i++) {
        const entry = series[i];
        const start = isoToMs(entry.time);
        if (start === null)
            continue;
        const nextStart = i + 1 < series.length ? isoToMs(series[i + 1].time) : start + 3600000;
        const hours = Math.max(1, Math.round((nextStart - start) / 3600000));
        const instant = entry.data?.instant?.details || {};
        const next1 = entry.data?.next_1_hours || {};
        const next6 = entry.data?.next_6_hours || {};
        const next12 = entry.data?.next_12_hours || {};
        const symbol = next1.summary?.symbol_code || next6.summary?.symbol_code || next12.summary?.symbol_code || "";
        const condition = metSymbolToWmo(symbol);
        const isDay = metSymbolIsDay(symbol);
        const intervalHours = Math.min(hours, 6);
        const totalPrecip = num(next6.details?.precipitation_amount, num(next1.details?.precipitation_amount, 0));
        const perHourPrecip = totalPrecip === null ? null : totalPrecip / intervalHours;
        for (let h = 0; h < intervalHours; h++) {
            hourly.push({
                time: start + h * 3600000,
                tempC: num(instant.air_temperature),
                feelsC: num(instant.apparent_air_temperature),
                condition: condition,
                isDay: h === 0 ? isDay : null,
                humidity: num(instant.relative_humidity),
                dewC: num(instant.dew_point_temperature),
                pressureHpa: num(instant.air_pressure_at_sea_level),
                windKmh: mpsToKmh(num(instant.wind_speed)),
                gustKmh: null,
                windDirDeg: num(instant.wind_from_direction),
                cloud: num(instant.cloud_area_fraction),
                visibilityKm: null,
                uv: num(instant.ultraviolet_index_clear_sky),
                precipMm: h === 0 ? num(next1.details?.precipitation_amount, perHourPrecip ?? 0) : (perHourPrecip ?? 0),
                precipProb: null,
                rainMm: null,
                snowCm: null,
                aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
            });
        }
    }

    hourly.sort((a, b) => a.time - b.time);
    const now = Date.now();
    const currentIndex = Math.max(0, hourly.findIndex(hour => hour.time >= now - 3600000));
    const currentHour = hourly[currentIndex] || hourly[0] || {};
    const daily = groupDaily(hourly, offset);
    const today = daily[0] || {};

    const current = Object.assign({}, currentHour, {
        time: currentHour.time || now,
        summary: conditionText(currentHour.condition),
        highC: today.maxC,
        lowC: today.minC,
        sunrise: today.sunrise,
        sunset: today.sunset,
        moonrise: null,
        moonset: null,
        moonPhase: null,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    });

    return baseData(provider, Object.assign({}, ctx, { location: Object.assign({}, ctx.location, { utcOffset: offset }) }), {
        timezone: ctx.location.timezone || "",
        utcOffset: offset,
        current: current,
        hourly: hourly,
        daily: daily
    });
}

function groupDaily(hourly, offset) {
    const map = {};
    for (const hour of hourly) {
        const key = localDateKey(hour.time, offset);
        if (!map[key]) {
            map[key] = {
                time: dayKeyToMs(key, offset),
                maxC: null,
                minC: null,
                condition: null,
                conditionHour: -1,
                summary: "",
                isDay: true,
                precipMm: 0,
                precipProb: null,
                rainMm: 0,
                snowCm: 0,
                windKmh: null,
                gustKmh: null,
                windDirDeg: null,
                humidity: [],
                pressureHpa: [],
                uv: null,
                cloud: [],
                visibilityKm: [],
                sunrise: null,
                sunset: null,
                daylight: null,
                moonrise: null,
                moonset: null,
                moonPhase: null,
                moonIllum: null,
                aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
            };
        }
        const day = map[key];
        day.maxC = day.maxC === null ? hour.tempC : Math.max(day.maxC, hour.tempC);
        day.minC = day.minC === null ? hour.tempC : Math.min(day.minC, hour.tempC);
        if (hour.precipMm !== null && hour.precipMm !== undefined)
            day.precipMm += hour.precipMm;
        if (hour.rainMm !== null && hour.rainMm !== undefined)
            day.rainMm += hour.rainMm;
        if (hour.snowCm !== null && hour.snowCm !== undefined)
            day.snowCm += hour.snowCm;
        if (hour.precipProb !== null && hour.precipProb !== undefined)
            day.precipProb = day.precipProb === null ? hour.precipProb : Math.max(day.precipProb, hour.precipProb);
        if (hour.windKmh !== null && hour.windKmh !== undefined)
            day.windKmh = day.windKmh === null ? hour.windKmh : Math.max(day.windKmh, hour.windKmh);
        if (hour.gustKmh !== null && hour.gustKmh !== undefined)
            day.gustKmh = day.gustKmh === null ? hour.gustKmh : Math.max(day.gustKmh, hour.gustKmh);
        if (hour.uv !== null && hour.uv !== undefined)
            day.uv = day.uv === null ? hour.uv : Math.max(day.uv, hour.uv);
        if (hour.windDirDeg !== null && hour.windDirDeg !== undefined && day.windDirDeg === null)
            day.windDirDeg = hour.windDirDeg;
        if (hour.humidity !== null && hour.humidity !== undefined)
            day.humidity.push(hour.humidity);
        if (hour.pressureHpa !== null && hour.pressureHpa !== undefined)
            day.pressureHpa.push(hour.pressureHpa);
        if (hour.cloud !== null && hour.cloud !== undefined)
            day.cloud.push(hour.cloud);
        if (hour.visibilityKm !== null && hour.visibilityKm !== undefined)
            day.visibilityKm.push(hour.visibilityKm);
        const localHour = new Date(hour.time + offset * 1000).getUTCHours();
        const score = Math.abs(localHour - 13);
        if (day.conditionHour < 0 || score < day.conditionHour) {
            day.conditionHour = score;
            day.condition = hour.condition;
        }
        if (hour.isDay === true && day.conditionHour > 0 && Math.abs(localHour - 13) <= 1)
            day.condition = hour.condition;
    }
    return Object.keys(map).sort().map(key => {
        const day = map[key];
        day.humidity = avg(day.humidity);
        day.pressureHpa = avg(day.pressureHpa);
        day.cloud = avg(day.cloud);
        day.visibilityKm = avg(day.visibilityKm);
        day.condition = day.condition === null ? 3 : day.condition;
        day.summary = conditionText(day.condition);
        delete day.conditionHour;
        return day;
    });
}

function parseOpenWeatherMap(json, ctx) {
    if (!json || !json.current || !json.hourly || !json.daily)
        throw new Error("OpenWeatherMap returned no forecast");
    const provider = providerById("openWeatherMap");
    const off = num(json.timezone_offset, 0);
    const currentJson = json.current;
    const hourly = [];
    for (const hour of json.hourly || []) {
        hourly.push({
            time: secToMs(hour.dt),
            tempC: num(hour.temp),
            feelsC: num(hour.feels_like),
            condition: owmToWmo(hour.weather?.[0]?.id, hour.weather?.[0]?.icon),
            isDay: String(hour.weather?.[0]?.icon || "").endsWith("d"),
            humidity: num(hour.humidity),
            dewC: num(hour.dew_point),
            pressureHpa: num(hour.pressure),
            windKmh: mpsToKmh(num(hour.wind_speed)),
            gustKmh: mpsToKmh(num(hour.wind_gust)),
            windDirDeg: num(hour.wind_deg),
            cloud: num(hour.clouds),
            visibilityKm: num(hour.visibility) === null ? null : num(hour.visibility) / 1000,
            uv: num(hour.uvi),
            precipMm: num(hour.rain?.["1h"], 0),
            precipProb: num(hour.pop) === null ? null : num(hour.pop) * 100,
            rainMm: num(hour.rain?.["1h"], 0),
            snowCm: num(hour.snow?.["1h"], 0) / 10,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
        });
    }

    const daily = [];
    for (const day of json.daily || []) {
        daily.push({
            time: secToMs(day.dt),
            maxC: num(day.temp?.max),
            minC: num(day.temp?.min),
            condition: owmToWmo(day.weather?.[0]?.id, day.weather?.[0]?.icon),
            summary: day.summary || day.weather?.[0]?.description || conditionText(owmToWmo(day.weather?.[0]?.id)),
            isDay: true,
            precipMm: num(day.rain, 0) + num(day.snow, 0),
            precipProb: num(day.pop) === null ? null : num(day.pop) * 100,
            rainMm: num(day.rain),
            snowCm: num(day.snow) === null ? null : num(day.snow) / 10,
            windKmh: mpsToKmh(num(day.wind_speed)),
            gustKmh: mpsToKmh(num(day.wind_gust)),
            windDirDeg: num(day.wind_deg),
            humidity: num(day.humidity),
            pressureHpa: num(day.pressure),
            uv: num(day.uvi),
            cloud: num(day.clouds),
            visibilityKm: null,
            sunrise: secToMs(day.sunrise),
            sunset: secToMs(day.sunset),
            daylight: null,
            moonrise: secToMs(day.moonrise),
            moonset: secToMs(day.moonset),
            moonPhase: num(day.moon_phase),
            moonIllum: null,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
        });
    }

    const today = daily[0] || {};
    const currentHour = hourly[0] || {};
    const current = {
        time: secToMs(currentJson.dt),
        tempC: num(currentJson.temp),
        feelsC: num(currentJson.feels_like),
        condition: owmToWmo(currentJson.weather?.[0]?.id, currentJson.weather?.[0]?.icon),
        summary: currentJson.weather?.[0]?.description || conditionText(owmToWmo(currentJson.weather?.[0]?.id)),
        isDay: String(currentJson.weather?.[0]?.icon || "").endsWith("d"),
        humidity: num(currentJson.humidity),
        dewC: num(currentJson.dew_point),
        pressureHpa: num(currentJson.pressure),
        windKmh: mpsToKmh(num(currentJson.wind_speed)),
        gustKmh: mpsToKmh(num(currentJson.wind_gust)),
        windDirDeg: num(currentJson.wind_deg),
        cloud: num(currentJson.clouds),
        visibilityKm: num(currentJson.visibility) === null ? null : num(currentJson.visibility) / 1000,
        uv: num(currentJson.uvi),
        precipMm: num(currentJson.rain?.["1h"], 0),
        precipProb: currentHour.precipProb,
        rainMm: num(currentJson.rain?.["1h"]),
        snowCm: num(currentJson.snow?.["1h"]) === null ? null : num(currentJson.snow?.["1h"]) / 10,
        highC: today.maxC,
        lowC: today.minC,
        sunrise: secToMs(currentJson.sunrise) ?? today.sunrise,
        sunset: secToMs(currentJson.sunset) ?? today.sunset,
        moonrise: today.moonrise,
        moonset: today.moonset,
        moonPhase: today.moonPhase,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    };

    const minutely = (json.minutely || []).map(minute => ({
        time: secToMs(minute.dt),
        precipMm: num(minute.precipitation, 0),
        precipProb: null
    }));

    const alerts = (json.alerts || []).map((alert, index) => ({
        id: String(alert.event || index),
        title: alert.event || "Weather alert",
        description: alert.description || "",
        severity: alert.tags?.includes("Extreme") ? "Extreme" : (alert.tags?.includes("Severe") ? "Severe" : "Moderate"),
        urgency: "Unknown",
        certainty: "Unknown",
        start: secToMs(alert.start),
        end: secToMs(alert.end),
        sender: alert.sender_name || "",
        instruction: ""
    }));

    return baseData(provider, Object.assign({}, ctx, { location: Object.assign({}, ctx.location, { utcOffset: off }) }), {
        timezone: json.timezone || ctx.location.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily,
        minutely: minutely,
        alerts: alerts
    });
}

function weatherApiOffset(json) {
    const location = json?.location || {};
    const local = String(location.localtime || "");
    const epoch = num(location.localtime_epoch);
    if (!local || epoch === null)
        return estimatedOffsetFromLongitude(location.lon);
    const asUtc = Date.parse(local.replace(" ", "T") + "Z");
    if (!Number.isFinite(asUtc))
        return estimatedOffsetFromLongitude(location.lon);
    const offset = Math.round((epoch * 1000 - asUtc) / 60000) * 60;
    if (Math.abs(offset) > 18 * 3600)
        return estimatedOffsetFromLongitude(location.lon);
    return offset;
}

function parseWeatherApi(json, ctx) {
    if (!json || !json.current || !json.forecast)
        throw new Error("WeatherAPI returned no forecast");
    const provider = providerById("weatherApi");
    const off = weatherApiOffset(json);
    const currentJson = json.current;
    const days = json.forecast.forecastday || [];
    const hourly = [];
    const daily = [];

    for (const day of days) {
        const dayDate = day.date || "";
        const sunrise = localDateTimeToMs(dayDate, day.astro?.sunrise, off);
        const sunset = localDateTimeToMs(dayDate, day.astro?.sunset, off);
        const moonrise = localDateTimeToMs(dayDate, day.astro?.moonrise, off);
        const moonset = localDateTimeToMs(dayDate, day.astro?.moonset, off);
        const dayHours = day.hour || [];
        const pressures = [];
        const clouds = [];
        const visibilities = [];
        for (const hour of dayHours) {
            const time = secToMs(hour.time_epoch);
            const pressure = num(hour.pressure_mb);
            if (pressure !== null) pressures.push(pressure);
            if (hour.cloud !== undefined) clouds.push(num(hour.cloud));
            if (hour.vis_km !== undefined) visibilities.push(num(hour.vis_km));
            hourly.push({
                time: time,
                tempC: num(hour.temp_c),
                feelsC: num(hour.feelslike_c),
                condition: wwoToWmo(hour.condition?.code),
                isDay: hour.is_day === 1,
                humidity: num(hour.humidity),
                dewC: dewPointC(hour.temp_c, hour.humidity),
                pressureHpa: pressure,
                windKmh: num(hour.wind_kph),
                gustKmh: num(hour.gust_kph),
                windDirDeg: num(hour.wind_degree),
                cloud: num(hour.cloud),
                visibilityKm: num(hour.vis_km),
                uv: num(hour.uv),
                precipMm: num(hour.precip_mm, 0),
                precipProb: num(hour.chance_of_rain),
                rainMm: num(hour.precip_mm),
                snowCm: num(hour.snow_cm),
                aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
            });
        }
        daily.push({
            time: day.date_epoch ? secToMs(day.date_epoch) : dayKeyToMs(dayDate, off),
            maxC: num(day.day?.maxtemp_c),
            minC: num(day.day?.mintemp_c),
            condition: wwoToWmo(day.day?.condition?.code),
            summary: day.day?.condition?.text || conditionText(wwoToWmo(day.day?.condition?.code)),
            isDay: true,
            precipMm: num(day.day?.totalprecip_mm, 0),
            precipProb: num(day.day?.daily_chance_of_rain),
            rainMm: num(day.day?.totalprecip_mm),
            snowCm: num(day.day?.totalsnow_cm),
            windKmh: num(day.day?.maxwind_kph),
            gustKmh: maxOf(dayHours.map(hour => num(hour.gust_kph))),
            windDirDeg: null,
            humidity: num(day.day?.avghumidity),
            pressureHpa: avg(pressures),
            uv: num(day.day?.uv),
            cloud: avg(clouds),
            visibilityKm: avg(visibilities),
            sunrise: sunrise,
            sunset: sunset,
            daylight: sunrise !== null && sunset !== null ? (sunset - sunrise) / 1000 : null,
            moonrise: moonrise,
            moonset: moonset,
            moonPhase: null,
            moonIllum: num(day.astro?.moon_illumination),
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
        });
    }

    hourly.sort((a, b) => a.time - b.time);
    const today = daily[0] || {};
    const currentHour = hourly[0] || {};
    const current = {
        time: secToMs(currentJson.last_updated_epoch),
        tempC: num(currentJson.temp_c),
        feelsC: num(currentJson.feelslike_c),
        condition: wwoToWmo(currentJson.condition?.code),
        summary: currentJson.condition?.text || conditionText(wwoToWmo(currentJson.condition?.code)),
        isDay: currentJson.is_day === 1,
        humidity: num(currentJson.humidity),
        dewC: dewPointC(currentJson.temp_c, currentJson.humidity),
        pressureHpa: num(currentJson.pressure_mb),
        windKmh: num(currentJson.wind_kph),
        gustKmh: num(currentJson.gust_kph),
        windDirDeg: num(currentJson.wind_degree),
        cloud: num(currentJson.cloud),
        visibilityKm: num(currentJson.vis_km),
        uv: num(currentJson.uv),
        precipMm: num(currentJson.precip_mm, 0),
        precipProb: currentHour.precipProb,
        rainMm: num(currentJson.precip_mm),
        snowCm: null,
        highC: today.maxC,
        lowC: today.minC,
        sunrise: today.sunrise,
        sunset: today.sunset,
        moonrise: today.moonrise,
        moonset: today.moonset,
        moonPhase: today.moonPhase,
        moonIllum: today.moonIllum,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    };

    const alerts = [];
    for (const alert of json.alerts?.alert || []) {
        alerts.push({
            id: String(alert.id || alert.headline || alerts.length),
            title: alert.headline || alert.event || "Weather alert",
            description: alert.desc || alert.msg || "",
            severity: alert.severity || "Moderate",
            urgency: alert.urgency || "Unknown",
            certainty: alert.certainty || "Unknown",
            start: isoToMs(alert.effective),
            end: isoToMs(alert.expires),
            sender: "WeatherAPI.com",
            instruction: alert.instruction || ""
        });
    }

    return baseData(provider, Object.assign({}, ctx, { location: Object.assign({}, ctx.location, { utcOffset: off }) }), {
        timezone: json.location?.tz_id || ctx.location.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily,
        alerts: alerts
    });
}

function localDateTimeToMs(date, time, offsetSeconds) {
    if (!date || !time || time === "No moonrise" || time === "No moonset" || time === "No sunrise" || time === "No sunset")
        return null;
    const match = /^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i.exec(String(time).trim());
    if (!match)
        return null;
    let hour = Number(match[1]);
    const minute = Number(match[2]);
    const suffix = String(match[3] || "").toUpperCase();
    if (suffix === "PM" && hour < 12) hour += 12;
    if (suffix === "AM" && hour === 12) hour = 0;
    return Date.parse(`${date}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00Z`) - offsetSeconds * 1000;
}

function parsePirateWeather(json, ctx) {
    if (!json || !json.currently)
        throw new Error("Pirate Weather returned no forecast");
    const provider = providerById("pirateWeather");
    const off = num(json.offset, 0) * 3600;
    const currentJson = json.currently;
    const hourly = [];
    for (const hour of json.hourly?.data || []) {
        hourly.push({
            time: secToMs(hour.time),
            tempC: num(hour.temperature),
            feelsC: num(hour.apparentTemperature),
            condition: iconToWmo(hour.icon),
            isDay: hour.icon ? !isNightIcon(hour.icon) : null,
            humidity: num(hour.humidity) === null ? null : num(hour.humidity) * 100,
            dewC: num(hour.dewPoint),
            pressureHpa: num(hour.pressure),
            windKmh: mpsToKmh(num(hour.windSpeed)),
            gustKmh: mpsToKmh(num(hour.windGust)),
            windDirDeg: num(hour.windBearing),
            cloud: num(hour.cloudCover) === null ? null : num(hour.cloudCover) * 100,
            visibilityKm: num(hour.visibility),
            uv: num(hour.uvIndex),
            precipMm: num(hour.precipIntensity, 0),
            precipProb: num(hour.precipProbability) === null ? null : num(hour.precipProbability) * 100,
            rainMm: hour.precipType === "rain" ? num(hour.precipIntensity, 0) : 0,
            snowCm: hour.precipType === "snow" ? num(hour.precipIntensity, 0) : 0,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
        });
    }

    const daily = [];
    for (const day of json.daily?.data || []) {
        daily.push({
            time: secToMs(day.time),
            maxC: num(day.temperatureHigh),
            minC: num(day.temperatureLow),
            condition: iconToWmo(day.icon),
            summary: day.summary || conditionText(iconToWmo(day.icon)),
            isDay: true,
            precipMm: num(day.precipIntensity, 0) * 24,
            precipProb: num(day.precipProbability) === null ? null : num(day.precipProbability) * 100,
            rainMm: day.precipType === "rain" ? num(day.precipIntensity, 0) * 24 : 0,
            snowCm: day.precipType === "snow" ? num(day.precipIntensity, 0) * 24 : 0,
            windKmh: mpsToKmh(num(day.windSpeed)),
            gustKmh: mpsToKmh(num(day.windGust)),
            windDirDeg: num(day.windBearing),
            humidity: num(day.humidity) === null ? null : num(day.humidity) * 100,
            pressureHpa: num(day.pressure),
            uv: num(day.uvIndex),
            cloud: num(day.cloudCover) === null ? null : num(day.cloudCover) * 100,
            visibilityKm: num(day.visibility),
            sunrise: secToMs(day.sunriseTime),
            sunset: secToMs(day.sunsetTime),
            daylight: day.sunriseTime && day.sunsetTime ? (day.sunsetTime - day.sunriseTime) : null,
            moonrise: null,
            moonset: null,
            moonPhase: num(day.moonPhase),
            moonIllum: null,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
        });
    }

    const today = daily[0] || {};
    const currentHour = hourly[0] || {};
    const current = {
        time: secToMs(currentJson.time),
        tempC: num(currentJson.temperature),
        feelsC: num(currentJson.apparentTemperature),
        condition: iconToWmo(currentJson.icon),
        summary: currentJson.summary || conditionText(iconToWmo(currentJson.icon)),
        isDay: currentJson.icon ? !isNightIcon(currentJson.icon) : null,
        humidity: num(currentJson.humidity) === null ? null : num(currentJson.humidity) * 100,
        dewC: num(currentJson.dewPoint),
        pressureHpa: num(currentJson.pressure),
        windKmh: mpsToKmh(num(currentJson.windSpeed)),
        gustKmh: mpsToKmh(num(currentJson.windGust)),
        windDirDeg: num(currentJson.windBearing),
        cloud: num(currentJson.cloudCover) === null ? null : num(currentJson.cloudCover) * 100,
        visibilityKm: num(currentJson.visibility),
        uv: num(currentJson.uvIndex),
        precipMm: num(currentJson.precipIntensity, 0),
        precipProb: num(currentJson.precipProbability) === null ? null : num(currentJson.precipProbability) * 100,
        rainMm: currentJson.precipType === "rain" ? num(currentJson.precipIntensity, 0) : 0,
        snowCm: currentJson.precipType === "snow" ? num(currentJson.precipIntensity, 0) : 0,
        highC: today.maxC,
        lowC: today.minC,
        sunrise: today.sunrise,
        sunset: today.sunset,
        moonrise: null,
        moonset: null,
        moonPhase: today.moonPhase,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    };

    const minutely = (json.minutely?.data || []).map(minute => ({
        time: secToMs(minute.time),
        precipMm: num(minute.precipIntensity, 0),
        precipProb: num(minute.precipProbability) === null ? null : num(minute.precipProbability) * 100
    }));

    const alerts = (json.alerts || []).map((alert, index) => ({
        id: String(alert.uri || alert.title || index),
        title: alert.title || "Weather alert",
        description: alert.description || "",
        severity: alert.severity || "Moderate",
        urgency: "Unknown",
        certainty: "Unknown",
        start: secToMs(alert.time),
        end: secToMs(alert.expires),
        sender: (alert.regions || []).join(", "),
        instruction: ""
    }));

    return baseData(provider, Object.assign({}, ctx, { location: Object.assign({}, ctx.location, { utcOffset: off }) }), {
        timezone: json.timezone || ctx.location.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily,
        minutely: minutely,
        alerts: alerts
    });
}


function parseInfoplaza(json, ctx) {
    if (!json || (!json.currently && !json.hourly && !json.daily))
        throw new Error("Infoplaza returned no forecast");
    const provider = providerById("infoplaza");
    const off = num(ctx.location.utcOffset, estimatedOffsetFromLongitude(ctx.location.longitude));
    const seconds = value => num(value) === null ? null : num(value) * 1000;
    const percent = value => num(value) === null ? null : clamp(num(value) * 100, 0, 100);

    const hourly = (json.hourly || []).map(item => {
        const condition = iconToWmo(item.icon);
        return {
            time: seconds(item.time),
            tempC: num(item.temperature),
            feelsC: num(item.apparentTemperature),
            condition: condition,
            isDay: item.icon ? !isNightIcon(item.icon) : null,
            humidity: percent(item.humidity),
            dewC: num(item.dewPoint),
            pressureHpa: num(item.pressure),
            windKmh: num(item.windSpeed) === null ? null : num(item.windSpeed) * 3.6,
            gustKmh: num(item.windGust) === null ? null : num(item.windGust) * 3.6,
            windDirDeg: num(item.windBearing),
            cloud: percent(item.cloudCover),
            visibilityKm: num(item.visibility) === null ? null : num(item.visibility) / 1000,
            uv: num(item.uvIndex),
            precipMm: num(item.precipIntensity, 0),
            precipProb: percent(item.precipProbability),
            rainMm: item.precipType === "rain" ? num(item.precipIntensity, 0) : 0,
            snowCm: item.precipType === "snow" ? num(item.precipIntensity, 0) / 10 : 0,
            summary: conditionText(condition),
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
        };
    });

    const daily = (json.daily || []).map(item => {
        const condition = iconToWmo(item.icon);
        const time = seconds(item.time);
        return {
            time: time,
            maxC: num(item.temperatureHigh),
            minC: num(item.temperatureLow),
            condition: condition,
            summary: conditionText(condition),
            isDay: true,
            precipMm: num(item.precipSum, 0),
            precipProb: percent(item.precipProbability),
            rainMm: item.precipType === "rain" ? num(item.precipSum, 0) : 0,
            snowCm: item.precipType === "snow" ? num(item.precipSum, 0) / 10 : 0,
            windKmh: num(item.windSpeed) === null ? null : num(item.windSpeed) * 3.6,
            gustKmh: null,
            windDirDeg: num(item.windBearing),
            humidity: percent(item.humidity),
            pressureHpa: num(item.pressure),
            uv: num(item.uvIndex),
            cloud: percent(item.cloudCover),
            visibilityKm: null,
            sunrise: null,
            sunset: null,
            daylight: null,
            moonrise: null,
            moonset: null,
            moonPhase: null,
            moonIllum: null,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
        };
    });

    const c = json.currently || {};
    const current = {
        time: hourly[0]?.time ?? Date.now(),
        tempC: num(c.temperature),
        feelsC: num(c.apparentTemperature),
        condition: iconToWmo(c.icon),
        summary: conditionText(iconToWmo(c.icon)),
        isDay: c.icon ? !isNightIcon(c.icon) : (hourly[0]?.isDay ?? null),
        humidity: percent(c.humidity),
        dewC: num(c.dewPoint),
        pressureHpa: num(c.pressure),
        windKmh: num(c.windSpeed) === null ? null : num(c.windSpeed) * 3.6,
        gustKmh: num(c.windGust) === null ? null : num(c.windGust) * 3.6,
        windDirDeg: num(c.windBearing),
        cloud: percent(c.cloudCover),
        visibilityKm: num(c.visibility) === null ? null : num(c.visibility) / 1000,
        uv: hourly[0]?.uv ?? null,
        precipMm: num(c.precipIntensity, 0),
        precipProb: percent(c.precipProbability),
        rainMm: 0,
        snowCm: 0,
        highC: daily[0]?.maxC ?? null,
        lowC: daily[0]?.minC ?? null,
        sunrise: null,
        sunset: null,
        moonrise: null,
        moonset: null,
        moonPhase: null,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    };

    const minutely = (json.minutely || []).map(item => ({
        time: seconds(item.time),
        precipMm: num(item.precipIntensity, 0) / 60,
        precipProb: percent(item.precipProbability)
    }));

    const location = Object.assign({}, ctx.location, { utcOffset: off });
    return baseData(provider, Object.assign({}, ctx, { location: location }), {
        timezone: ctx.location?.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily,
        minutely: minutely,
        alerts: []
    });
}

function parseBrightSky(json, ctx) {
    if (!json || !json.weather || json.weather.length === 0)
        throw new Error("Bright Sky returned no forecast (it only covers Germany)");
    const provider = providerById("brightSky");
    const weather = json.weather;
    const first = weather[0]?.timestamp || "";
    const off = offsetFromIso(first) || estimatedOffsetFromLongitude(ctx.location.longitude);
    const now = Date.now();
    const hourly = [];
    for (const entry of weather) {
        const time = isoToMs(entry.timestamp);
        if (time === null || time < now - 2 * 3600000)
            continue;
        const icon = String(entry.icon || "");
        hourly.push({
            time: time,
            tempC: num(entry.temperature),
            feelsC: null,
            condition: iconToWmo(icon),
            isDay: icon.endsWith("-day") ? true : (icon.endsWith("-night") ? false : null),
            humidity: num(entry.relative_humidity),
            dewC: num(entry.dew_point),
            pressureHpa: num(entry.pressure_msl),
            windKmh: num(entry.wind_speed),
            gustKmh: num(entry.wind_gust_speed),
            windDirDeg: num(entry.wind_direction),
            cloud: num(entry.cloud_cover),
            visibilityKm: num(entry.visibility) === null ? null : num(entry.visibility) / 1000,
            uv: null,
            precipMm: num(entry.precipitation, 0),
            precipProb: num(entry.precipitation_probability),
            rainMm: num(entry.precipitation, 0),
            snowCm: null,
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
        });
    }
    if (hourly.length === 0)
        throw new Error("Bright Sky returned no future hours");
    const daily = groupDaily(hourly, off);
    const today = daily[0] || {};
    const currentHour = hourly[0] || {};
    const current = Object.assign({}, currentHour, {
        summary: conditionText(currentHour.condition),
        highC: today.maxC,
        lowC: today.minC,
        sunrise: today.sunrise,
        sunset: today.sunset,
        moonrise: null,
        moonset: null,
        moonPhase: null,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    });
    return baseData(provider, Object.assign({}, ctx, { location: Object.assign({}, ctx.location, { utcOffset: off }) }), {
        timezone: ctx.location.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily
    });
}

// ── Alert parsers ───────────────────────────────────────────────────────────

function xmlText(value) {
    return String(value || "")
        .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
        .replace(/<[^>]+>/g, " ")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, "\"")
        .replace(/&#39;/g, "'")
        .replace(/\s+/g, " ")
        .trim();
}

function xmlTag(block, tag) {
    const match = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i").exec(block);
    return match ? match[1] : "";
}


function parseAccuWeather(responses, ctx) {
    const provider = providerById("accuWeather");
    const hourlyJson = Array.isArray(responses.hourly) ? responses.hourly : [];
    const dailyJson = Array.isArray(responses.daily?.DailyForecasts) ? responses.daily.DailyForecasts : [];
    if (hourlyJson.length === 0)
        throw new Error("AccuWeather returned no hourly forecast");
    if (dailyJson.length === 0)
        throw new Error("AccuWeather returned no daily forecast");

    const off = offsetFromIso(hourlyJson[0]?.DateTime)
        || num(ctx.location.utcOffset, estimatedOffsetFromLongitude(ctx.location.longitude));

    const hourly = hourlyJson.slice(0, 12).map(item => {
        const condition = accuWeatherToWmo(item.WeatherIcon, item.IconPhrase);
        const rainMm = accuValue(item.Rain, "precip");
        const snowCm = accuValue(item.Snow, "snow");
        const totalMm = accuValue(item.TotalLiquid, "precip");
        return {
            time: accuEpochMs(item.EpochDateTime) ?? isoToMs(item.DateTime),
            tempC: accuValue(item.Temperature, "temp"),
            feelsC: accuValue(item.RealFeelTemperature, "temp"),
            condition: condition,
            isDay: item.IsDaylight === undefined ? null : !!item.IsDaylight,
            humidity: num(item.RelativeHumidity),
            dewC: accuValue(item.DewPoint, "temp"),
            pressureHpa: accuValue(item.Pressure, "pressure"),
            windKmh: accuValue(item.Wind?.Speed, "speed"),
            gustKmh: accuValue(item.WindGust?.Speed, "speed"),
            windDirDeg: num(item.Wind?.Direction?.Degrees),
            cloud: num(item.CloudCover),
            visibilityKm: accuValue(item.Visibility, "distance"),
            uv: num(item.UVIndex),
            precipMm: totalMm !== null ? totalMm : (rainMm !== null ? rainMm : 0),
            precipProb: num(item.PrecipitationProbability),
            rainMm: rainMm,
            snowCm: snowCm,
            summary: item.IconPhrase || conditionText(condition),
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
        };
    });

    // UV is only published hourly; use the day's peak for the daily chart.
    const dailyUv = {};
    for (const hour of hourly) {
        if (hour.uv === null || hour.uv === undefined || !Number.isFinite(Number(hour.uv)))
            continue;
        const key = localDateKey(hour.time, off);
        dailyUv[key] = dailyUv[key] === undefined ? hour.uv : Math.max(dailyUv[key], hour.uv);
    }

    const daily = dailyJson.slice(0, 5).map(item => {
        const dayPart = item.Day || {};
        const nightPart = item.Night || {};
        const condition = accuWeatherToWmo(dayPart.Icon ?? nightPart.Icon, dayPart.IconPhrase || nightPart.IconPhrase);
        const time = accuEpochMs(item.EpochDate)
            ?? (item.Date ? dayKeyToMs(String(item.Date).slice(0, 10), off) : null);
        const maxC = accuValue(item.Temperature?.Maximum, "temp");
        const minC = accuValue(item.Temperature?.Minimum, "temp");
        const rainMm = accuValue(dayPart.Rain, "precip");
        const snowCm = accuValue(dayPart.Snow, "snow");
        const totalMm = accuValue(dayPart.TotalLiquid, "precip");
        return {
            time: time,
            maxC: maxC,
            minC: minC,
            condition: condition,
            summary: dayPart.IconPhrase || nightPart.IconPhrase || conditionText(condition),
            isDay: true,
            precipMm: totalMm !== null ? totalMm : (rainMm !== null ? rainMm : 0),
            precipProb: num(dayPart.PrecipitationProbability),
            rainMm: rainMm,
            snowCm: snowCm,
            windKmh: accuValue(dayPart.Wind?.Speed, "speed"),
            gustKmh: accuValue(dayPart.WindGust?.Speed, "speed"),
            windDirDeg: num(dayPart.Wind?.Direction?.Degrees),
            humidity: num(dayPart.RelativeHumidity),
            pressureHpa: null,
            uv: dailyUv[localDateKey(time, off)] ?? null,
            cloud: num(dayPart.CloudCover),
            visibilityKm: accuValue(dayPart.Visibility, "distance"),
            sunrise: accuEpochMs(item.Sun?.EpochRise),
            sunset: accuEpochMs(item.Sun?.EpochSet),
            daylight: item.Sun?.EpochRise && item.Sun?.EpochSet ? Number(item.Sun.EpochSet) - Number(item.Sun.EpochRise) : null,
            moonrise: accuEpochMs(item.Moon?.EpochRise),
            moonset: accuEpochMs(item.Moon?.EpochSet),
            moonPhase: null,
            moonIllum: num(item.Moon?.Illumination),
            aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollenTotal: null
        };
    });

    const first = hourly[0];
    const today = daily[0] || {};
    const current = {
        time: first.time || Date.now(),
        tempC: first.tempC,
        feelsC: first.feelsC,
        condition: first.condition,
        summary: first.summary,
        isDay: first.isDay,
        humidity: first.humidity,
        dewC: first.dewC,
        pressureHpa: first.pressureHpa,
        windKmh: first.windKmh,
        gustKmh: first.gustKmh,
        windDirDeg: first.windDirDeg,
        cloud: first.cloud,
        visibilityKm: first.visibilityKm,
        uv: first.uv,
        precipMm: first.precipMm,
        precipProb: first.precipProb,
        rainMm: first.rainMm,
        snowCm: first.snowCm,
        highC: today.maxC,
        lowC: today.minC,
        sunrise: null,
        sunset: null,
        moonrise: null,
        moonset: null,
        moonPhase: null,
        moonIllum: null,
        aqi: null, pm25: null, pm10: null, ozone: null, no2: null, so2: null, co: null, pollen: null
    };

    const location = Object.assign({}, ctx.location, { utcOffset: off });
    return baseData(provider, Object.assign({}, ctx, { location: location }), {
        timezone: ctx.location?.timezone || "",
        utcOffset: off,
        current: current,
        hourly: hourly,
        daily: daily,
        minutely: [],
        alerts: []
    });
}

function parseAlerts(providerId, text, ctx) {
    const provider = providerById(providerId);
    if (provider.id === "metNo") {
        const alerts = [];
        const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
        let match;
        while ((match = itemRegex.exec(text)) !== null) {
            const block = match[1];
            const title = xmlText(xmlTag(block, "title"));
            const description = xmlText(xmlTag(block, "description"));
            if (!title)
                continue;
            const severityMatch = /severity:\s*([A-Za-z]+)/i.exec(description);
            const urgencyMatch = /urgency:\s*([A-Za-z]+)/i.exec(description);
            alerts.push({
                id: xmlText(xmlTag(block, "guid")) || title,
                title: title,
                description: description,
                severity: severityMatch ? severityMatch[1] : "Moderate",
                urgency: urgencyMatch ? urgencyMatch[1] : "Unknown",
                certainty: "Unknown",
                start: isoToMs(xmlText(xmlTag(block, "pubDate"))),
                end: null,
                sender: "MET Norway",
                instruction: "",
                link: xmlText(xmlTag(block, "link"))
            });
        }
        return alerts;
    }

    if (provider.id === "infoplaza") {
        return {
            url: `https://api.infoplaza.com/weather/v1/forecast?latitude=${lat}&longitude=${lon}&token=${encodeURIComponent(key)}`,
            headers: jsonHeaders()
        };
    }

    if (provider.id === "brightSky") {
        let json;
        try { json = JSON.parse(text); } catch (e) { return []; }
        return (json.alerts || []).map((alert, index) => ({
            id: String(alert.id || index),
            title: alert.headline || alert.event || "Weather alert",
            description: alert.description || "",
            severity: alert.severity || "Moderate",
            urgency: alert.urgency || "Unknown",
            certainty: alert.certainty || "Unknown",
            start: isoToMs(alert.onset || alert.effective),
            end: isoToMs(alert.expires),
            sender: alert.sender_name || "DWD",
            instruction: alert.instruction || ""
        }));
    }

    return [];
}

// ── Public helpers for the UI ───────────────────────────────────────────────

function providerSupports(providerId, feature) {
    const provider = providerById(providerId);
    if (feature === "alerts") return provider.supportsAlerts;
    if (feature === "minutely") return provider.supportsMinutely;
    if (feature === "models") return provider.supportsModels;
    return false;
}

function descriptionFor(providerId) {
    return providerById(providerId).description;
}
