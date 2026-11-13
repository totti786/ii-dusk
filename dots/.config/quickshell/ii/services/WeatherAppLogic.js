// Formatting and chart-building helpers for the ii Weather app.
//
// Everything in the normalized data model is metric. These helpers are the
// only place that knows the user's display units, so a provider never sees an
// imperial value and a chart never has to guess.

const DEFAULT_UNITS = {
    temperature: "c",
    wind: "kmh",
    precip: "mm",
    pressure: "hpa",
    visibility: "km",
    distance: "km"
};

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const WEEKDAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function unitsFromJson(text) {
    let parsed = {};
    try { parsed = JSON.parse(text || "{}"); } catch (e) { parsed = {}; }
    return Object.assign({}, DEFAULT_UNITS, parsed || {});
}

function defaultUnitsJson() {
    return JSON.stringify(DEFAULT_UNITS);
}

function isList(value) {
    return value && value.length !== undefined;
}

function pad2(value) {
    return String(value).padStart(2, "0");
}

function round(value, decimals) {
    const factor = Math.pow(10, decimals || 0);
    return Math.round(Number(value) * factor) / factor;
}

function localDate(ms, offsetSeconds) {
    return new Date(Number(ms) + Number(offsetSeconds || 0) * 1000);
}

function temperatureValue(celsius, units) {
    if (celsius === null || celsius === undefined || !Number.isFinite(Number(celsius)))
        return null;
    return units.temperature === "f" ? Number(celsius) * 9 / 5 + 32 : Number(celsius);
}

function formatTemperature(celsius, units, includeUnit) {
    const value = temperatureValue(celsius, units);
    if (value === null)
        return "--";
    return `${Math.round(value)}°${includeUnit ? (units.temperature === "f" ? "F" : "C") : ""}`;
}

function formatTemperatureDecimal(celsius, units, decimals) {
    const value = temperatureValue(celsius, units);
    if (value === null)
        return "--";
    return `${round(value, decimals === undefined ? 1 : decimals)}°`;
}

function temperatureUnit(units) {
    return units.temperature === "f" ? "°F" : "°C";
}

function windValue(kmh, units) {
    if (kmh === null || kmh === undefined || !Number.isFinite(Number(kmh)))
        return null;
    const value = Number(kmh);
    if (units.wind === "mph") return value * 0.621371;
    if (units.wind === "ms") return value / 3.6;
    if (units.wind === "kn") return value * 0.539957;
    return value;
}

function windUnit(units) {
    if (units.wind === "mph") return "mph";
    if (units.wind === "ms") return "m/s";
    if (units.wind === "kn") return "kn";
    return "km/h";
}

function formatWind(kmh, units) {
    const value = windValue(kmh, units);
    if (value === null)
        return "--";
    const decimals = units.wind === "ms" ? 1 : 0;
    return `${round(value, decimals)} ${windUnit(units)}`;
}

function precipValue(mm, units) {
    if (mm === null || mm === undefined || !Number.isFinite(Number(mm)))
        return null;
    return units.precip === "in" ? Number(mm) / 25.4 : Number(mm);
}

function precipUnit(units) {
    return units.precip === "in" ? "in" : "mm";
}

function formatPrecip(mm, units) {
    const value = precipValue(mm, units);
    if (value === null)
        return "--";
    if (units.precip === "in")
        return `${round(value, 2)} in`;
    return `${round(value, value < 10 ? 1 : 0)} mm`;
}

function pressureValue(hpa, units) {
    if (hpa === null || hpa === undefined || !Number.isFinite(Number(hpa)))
        return null;
    if (units.pressure === "inhg") return Number(hpa) * 0.02953;
    if (units.pressure === "mmhg") return Number(hpa) * 0.750062;
    return Number(hpa);
}

function pressureUnit(units) {
    if (units.pressure === "inhg") return "inHg";
    if (units.pressure === "mmhg") return "mmHg";
    return "hPa";
}

function formatPressure(hpa, units) {
    const value = pressureValue(hpa, units);
    if (value === null)
        return "--";
    return `${round(value, units.pressure === "hpa" ? 0 : 2)} ${pressureUnit(units)}`;
}

function visibilityValue(km, units) {
    if (km === null || km === undefined || !Number.isFinite(Number(km)))
        return null;
    return units.visibility === "mi" ? Number(km) * 0.621371 : Number(km);
}

function visibilityUnit(units) {
    return units.visibility === "mi" ? "mi" : "km";
}

function formatVisibility(km, units) {
    const value = visibilityValue(km, units);
    if (value === null)
        return "--";
    return `${round(value, value < 10 ? 1 : 0)} ${visibilityUnit(units)}`;
}

function formatDistance(km, units) {
    const value = units.distance === "mi" ? Number(km) * 0.621371 : Number(km);
    if (!Number.isFinite(value))
        return "--";
    return `${round(value, value < 10 ? 1 : 0)} ${units.distance === "mi" ? "mi" : "km"}`;
}

function formatPercent(value, decimals) {
    if (value === null || value === undefined || !Number.isFinite(Number(value)))
        return "--";
    return `${round(value, decimals === undefined ? 0 : decimals)}%`;
}

function formatNumber(value, decimals) {
    if (value === null || value === undefined || !Number.isFinite(Number(value)))
        return "--";
    return `${round(value, decimals === undefined ? 0 : decimals)}`;
}

function formatUv(value) {
    if (value === null || value === undefined || !Number.isFinite(Number(value)))
        return "--";
    return round(value, 1).toFixed(1);
}

function formatAqi(value) {
    if (value === null || value === undefined || !Number.isFinite(Number(value)))
        return "--";
    return String(Math.round(value));
}

function formatTime(ms, offsetSeconds, use24h) {
    if (!ms)
        return "--";
    const date = localDate(ms, offsetSeconds);
    let hour = date.getUTCHours();
    const minute = pad2(date.getUTCMinutes());
    if (use24h)
        return `${pad2(hour)}:${minute}`;
    const suffix = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour === 0) hour = 12;
    return `${hour}:${minute} ${suffix}`;
}

function formatHour(ms, offsetSeconds, use24h) {
    if (!ms)
        return "--";
    const date = localDate(ms, offsetSeconds);
    let hour = date.getUTCHours();
    if (use24h)
        return pad2(hour);
    const suffix = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour === 0) hour = 12;
    return `${hour} ${suffix}`;
}

function formatWeekday(ms, offsetSeconds, short) {
    if (!ms)
        return "--";
    const day = localDate(ms, offsetSeconds).getUTCDay();
    return short ? WEEKDAYS_SHORT[day] : WEEKDAYS[day];
}

function formatMonthDay(ms, offsetSeconds) {
    if (!ms)
        return "--";
    const date = localDate(ms, offsetSeconds);
    return `${MONTHS_SHORT[date.getUTCMonth()]} ${date.getUTCDate()}`;
}

function formatDate(ms, offsetSeconds) {
    return formatMonthDay(ms, offsetSeconds);
}

function formatDateTime(ms, offsetSeconds, use24h) {
    if (!ms)
        return "--";
    return `${formatMonthDay(ms, offsetSeconds)} · ${formatTime(ms, offsetSeconds, use24h)}`;
}

function dayLabel(ms, offsetSeconds, index) {
    if (index === 0)
        return "Today";
    if (index === 1)
        return "Tomorrow";
    return formatWeekday(ms, offsetSeconds, false);
}

function isSameLocalDay(a, b, offsetSeconds) {
    if (!a || !b)
        return false;
    const da = localDate(a, offsetSeconds);
    const db = localDate(b, offsetSeconds);
    return da.getUTCFullYear() === db.getUTCFullYear()
        && da.getUTCMonth() === db.getUTCMonth()
        && da.getUTCDate() === db.getUTCDate();
}

function localDayKey(ms, offsetSeconds) {
    return localDate(ms, offsetSeconds).toISOString().slice(0, 10);
}

function timeAgo(ms) {
    if (!ms)
        return "";
    const seconds = Math.max(0, Math.round((Date.now() - Number(ms)) / 1000));
    if (seconds < 45)
        return "just now";
    if (seconds < 3600)
        return `${Math.round(seconds / 60)} min ago`;
    if (seconds < 86400)
        return `${Math.round(seconds / 3600)} h ago`;
    return `${Math.round(seconds / 86400)} d ago`;
}

function formatDaylight(seconds) {
    if (seconds === null || seconds === undefined || !Number.isFinite(Number(seconds)))
        return "--";
    const total = Math.max(0, Math.round(Number(seconds) / 60));
    const hours = Math.floor(total / 60);
    const minutes = total % 60;
    return `${hours}h ${minutes}m`;
}

function windDirection(degrees) {
    if (degrees === null || degrees === undefined || !Number.isFinite(Number(degrees)))
        return "--";
    const directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
    return directions[Math.round((((Number(degrees) % 360) + 360) % 360) / 22.5) % 16];
}

function aqiCategory(aqi) {
    if (aqi === null || aqi === undefined || !Number.isFinite(Number(aqi)))
        return { label: "No data", short: "--", tone: "neutral" };
    const value = Number(aqi);
    if (value <= 50) return { label: "Good", short: "Good", tone: "success" };
    if (value <= 100) return { label: "Moderate", short: "Moderate", tone: "primary" };
    if (value <= 150) return { label: "Unhealthy for sensitive groups", short: "Sensitive", tone: "tertiary" };
    if (value <= 200) return { label: "Unhealthy", short: "Unhealthy", tone: "error" };
    if (value <= 300) return { label: "Very unhealthy", short: "Very unhealthy", tone: "error" };
    return { label: "Hazardous", short: "Hazardous", tone: "error" };
}

function uvCategory(uv) {
    if (uv === null || uv === undefined || !Number.isFinite(Number(uv)))
        return { label: "No data", tone: "neutral" };
    const value = Number(uv);
    if (value < 3) return { label: "Low", tone: "success" };
    if (value < 6) return { label: "Moderate", tone: "primary" };
    if (value < 8) return { label: "High", tone: "tertiary" };
    if (value < 11) return { label: "Very high", tone: "error" };
    return { label: "Extreme", tone: "error" };
}

function pollenCategory(total) {
    if (total === null || total === undefined || !Number.isFinite(Number(total)))
        return { label: "No data", tone: "neutral" };
    const value = Number(total);
    if (value < 2.5) return { label: "Low", tone: "success" };
    if (value < 10) return { label: "Moderate", tone: "primary" };
    if (value < 50) return { label: "High", tone: "tertiary" };
    if (value < 100) return { label: "Very high", tone: "error" };
    return { label: "Extreme", tone: "error" };
}

function humidityComfort(value) {
    if (value === null || value === undefined || !Number.isFinite(Number(value)))
        return "";
    const humidity = Number(value);
    if (humidity < 30) return "Dry air";
    if (humidity > 70) return "Humid";
    return "Comfortable";
}

function pressureTrend(current, previous) {
    if (current === null || previous === null || !Number.isFinite(Number(current)) || !Number.isFinite(Number(previous)))
        return { label: "Steady", icon: "trending_flat" };
    const delta = Number(current) - Number(previous);
    if (delta > 0.8) return { label: "Rising", icon: "trending_up" };
    if (delta < -0.8) return { label: "Falling", icon: "trending_down" };
    return { label: "Steady", icon: "trending_flat" };
}

function conditionHeadline(code, isDay) {
    const text = conditionText(code);
    return text;
}

function conditionText(code) {
    const c = Number(code);
    if (c === 0) return "Clear sky";
    if (c === 1) return "Mainly clear";
    if (c === 2) return "Partly cloudy";
    if (c === 3) return "Overcast";
    if (c === 45) return "Fog";
    if (c === 48) return "Rime fog";
    if (c >= 51 && c <= 55) return "Drizzle";
    if (c >= 56 && c <= 57) return "Freezing drizzle";
    if (c === 61) return "Light rain";
    if (c === 63) return "Moderate rain";
    if (c === 65) return "Heavy rain";
    if (c === 66 || c === 67) return "Freezing rain";
    if (c === 71) return "Light snow";
    if (c === 73) return "Moderate snow";
    if (c === 75) return "Heavy snow";
    if (c === 77) return "Snow grains";
    if (c === 80) return "Light showers";
    if (c === 81) return "Moderate showers";
    if (c === 82) return "Violent showers";
    if (c === 85 || c === 86) return "Snow showers";
    if (c === 95) return "Thunderstorm";
    if (c === 96 || c === 99) return "Thunderstorm with hail";
    return "Unknown conditions";
}

// ── Chart builders ──────────────────────────────────────────────────────────

function hourlyWindow(hourly, range) {
    if (!isList(hourly))
        return [];
    const count = range === "48h" ? 48 : (range === "72h" ? 72 : 24);
    const now = Date.now();
    let start = hourly.findIndex(hour => Number(hour.time) >= now - 3600000);
    if (start < 0)
        start = 0;
    return hourly.slice(start, start + count);
}

function dailyWindow(daily, range) {
    if (!isList(daily))
        return [];
    const count = range === "14d" ? 14 : (range === "7d" ? 7 : 7);
    return daily.slice(0, count);
}

function hourlyLabels(hours, offset, use24h) {
    const labels = [];
    const pointLabels = [];
    const step = hours.length <= 24 ? 3 : 6;
    for (let i = 0; i < hours.length; i++) {
        const date = localDate(hours[i].time, offset);
        const hour = date.getUTCHours();
        let label = "";
        if (i % step === 0)
            label = hour === 0 ? formatWeekday(hours[i].time, offset, true) : formatHour(hours[i].time, offset, use24h);
        labels.push(label);
        pointLabels.push(`${formatWeekday(hours[i].time, offset, true)} ${formatMonthDay(hours[i].time, offset)} · ${formatTime(hours[i].time, offset, use24h)}`);
    }
    return { labels, pointLabels };
}

function dailyLabels(days, offset) {
    const labels = [];
    const pointLabels = [];
    const every = days.length > 10 ? 2 : 1;
    for (let i = 0; i < days.length; i++) {
        labels.push(i % every === 0 ? `${formatWeekday(days[i].time, offset, true)} ${localDate(days[i].time, offset).getUTCDate()}` : "");
        pointLabels.push(`${formatWeekday(days[i].time, offset, false)} ${formatMonthDay(days[i].time, offset)}`);
    }
    return { labels, pointLabels };
}

function mapped(series, mapper) {
    return (series || []).map(item => {
        if (item === null || item === undefined)
            return null;
        const value = mapper(item);
        return value === null || value === undefined || !Number.isFinite(Number(value)) ? null : Number(value);
    });
}

function seriesFrom(data, key) {
    return (data || []).map(item => {
        const value = item ? item[key] : null;
        return value === null || value === undefined || !Number.isFinite(Number(value)) ? null : Number(value);
    });
}

function chart(id, group, title, icon, subtitle, values, labels, options) {
    return Object.assign({
        id,
        group,
        kind: "line",
        title,
        icon,
        subtitle: subtitle || "",
        values: values || [],
        secondary: [],
        bars: [],
        labels: labels || [],
        pointLabels: [],
        unit: "",
        secondaryUnit: "",
        barUnit: "",
        primaryLabel: "",
        secondaryLabel: "",
        barLabel: "",
        tone: "primary",
        secondaryTone: "tertiary",
        barTone: "secondary",
        yMin: null,
        yMax: null,
        secondaryMin: null,
        secondaryMax: null,
        decimals: 0,
        secondaryDecimals: 0
    }, options || {});
}

function buildCharts(data, units, range, use24h) {
    if (!data || !isList(data.hourly) || data.hourly.length === 0)
        return [];
    const offset = Number(data.utcOffset || 0);
    const hours = hourlyWindow(data.hourly, range);
    const days = dailyWindow(data.daily, range);
    const hourLabels = hourlyLabels(hours, offset, use24h);
    const dayLabels = dailyLabels(days, offset);
    const charts = [];

    charts.push(chart("temperature", "hourly", "Temperature", "thermostat", "Air temperature and what it feels like", mapped(hours, h => temperatureValue(h.tempC, units)), hourLabels.labels, {
        secondary: mapped(hours, h => temperatureValue(h.feelsC, units)),
        pointLabels: hourLabels.pointLabels,
        unit: temperatureUnit(units),
        primaryLabel: "Temperature",
        secondaryLabel: "Feels like",
        tone: "primary",
        secondaryTone: "tertiary",
        decimals: 0,
        secondaryDecimals: 0
    }));

    charts.push(chart("precipitation", "hourly", "Precipitation", "rainy", "Amount and chance of precipitation", [], hourLabels.labels, {
        kind: "bars",
        bars: mapped(hours, h => precipValue(h.precipMm, units)),
        secondary: mapped(hours, h => h.precipProb),
        pointLabels: hourLabels.pointLabels,
        unit: precipUnit(units),
        secondaryUnit: "%",
        barLabel: "Amount",
        secondaryLabel: "Chance",
        tone: "secondary",
        secondaryTone: "primary",
        barTone: "secondary",
        secondaryMin: 0,
        secondaryMax: 100,
        decimals: units.precip === "in" ? 2 : 1,
        secondaryDecimals: 0
    }));

    charts.push(chart("wind", "hourly", "Wind", "air", "Sustained wind and gusts", mapped(hours, h => windValue(h.windKmh, units)), hourLabels.labels, {
        secondary: mapped(hours, h => windValue(h.gustKmh, units)),
        pointLabels: hourLabels.pointLabels,
        unit: windUnit(units),
        primaryLabel: "Wind",
        secondaryLabel: "Gusts",
        tone: "primary",
        secondaryTone: "tertiary",
        decimals: units.wind === "ms" ? 1 : 0
    }));

    charts.push(chart("humidity", "hourly", "Humidity", "humidity_percentage", "Relative humidity", seriesFrom(hours, "humidity"), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        unit: "%",
        primaryLabel: "Humidity",
        tone: "primary",
        yMin: 0,
        yMax: 100
    }));

    charts.push(chart("dew", "hourly", "Dew point", "water_drop", "The temperature at which air becomes saturated", mapped(hours, h => temperatureValue(h.dewC, units)), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        unit: temperatureUnit(units),
        primaryLabel: "Dew point",
        tone: "tertiary"
    }));

    charts.push(chart("pressure", "hourly", "Pressure", "speed", "Mean sea-level pressure", mapped(hours, h => pressureValue(h.pressureHpa, units)), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        unit: pressureUnit(units),
        primaryLabel: "Pressure",
        tone: "primary",
        decimals: units.pressure === "hpa" ? 0 : 2
    }));

    charts.push(chart("uv", "hourly", "UV index", "wb_sunny", "Ultraviolet radiation", seriesFrom(hours, "uv"), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        primaryLabel: "UV index",
        tone: "tertiary",
        yMin: 0,
        decimals: 1
    }));

    charts.push(chart("visibility", "hourly", "Visibility", "visibility", "How far you can see", mapped(hours, h => visibilityValue(h.visibilityKm, units)), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        unit: visibilityUnit(units),
        primaryLabel: "Visibility",
        tone: "primary",
        decimals: 1
    }));

    charts.push(chart("cloud", "hourly", "Cloud cover", "cloud", "Total cloud fraction", seriesFrom(hours, "cloud"), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        unit: "%",
        primaryLabel: "Cloud cover",
        tone: "tertiary",
        yMin: 0,
        yMax: 100
    }));

    charts.push(chart("aqi", "hourly", "Air quality", "masks", "US Air Quality Index (Open-Meteo / CAMS)", seriesFrom(hours, "aqi"), hourLabels.labels, {
        pointLabels: hourLabels.pointLabels,
        unit: "US AQI",
        primaryLabel: "US AQI",
        tone: "primary",
        yMin: 0
    }));

    charts.push(chart("particulates", "hourly", "Particulate matter", "grain", "PM2.5 and PM10", seriesFrom(hours, "pm25"), hourLabels.labels, {
        secondary: seriesFrom(hours, "pm10"),
        pointLabels: hourLabels.pointLabels,
        unit: "µg/m³",
        primaryLabel: "PM2.5",
        secondaryLabel: "PM10",
        tone: "primary",
        secondaryTone: "tertiary",
        decimals: 1
    }));

    charts.push(chart("gases", "hourly", "Ozone & nitrogen dioxide", "science", "Trace gases", seriesFrom(hours, "ozone"), hourLabels.labels, {
        secondary: seriesFrom(hours, "no2"),
        pointLabels: hourLabels.pointLabels,
        unit: "µg/m³",
        primaryLabel: "Ozone",
        secondaryLabel: "NO₂",
        tone: "primary",
        secondaryTone: "tertiary",
        decimals: 1
    }));

    charts.push(chart("sulfur", "hourly", "Sulfur dioxide & carbon monoxide", "air", "Combustion-related pollutants", seriesFrom(hours, "so2"), hourLabels.labels, {
        secondary: seriesFrom(hours, "co"),
        pointLabels: hourLabels.pointLabels,
        unit: "µg/m³",
        primaryLabel: "SO₂",
        secondaryLabel: "CO",
        tone: "tertiary",
        secondaryTone: "primary",
        decimals: 1
    }));

    charts.push(chart("pollen", "hourly", "Pollen", "local_florist", "Total pollen and grass pollen", mapped(hours, h => h.pollen ? h.pollen.total : null), hourLabels.labels, {
        secondary: mapped(hours, h => h.pollen ? h.pollen.grass : null),
        pointLabels: hourLabels.pointLabels,
        unit: "grains/m³",
        primaryLabel: "Total",
        secondaryLabel: "Grass",
        tone: "primary",
        secondaryTone: "tertiary",
        decimals: 1
    }));

    const rangeDays = days.map((day, index) => ({
        time: day.time,
        label: dayLabel(day.time, offset, index),
        date: formatMonthDay(day.time, offset),
        min: temperatureValue(day.minC, units),
        max: temperatureValue(day.maxC, units),
        minLabel: formatTemperature(day.minC, units),
        maxLabel: formatTemperature(day.maxC, units),
        condition: day.condition,
        isDay: true
    }));

    charts.push(chart("dailyRange", "daily", "Daily temperature range", "device_thermostat", "Every day's low and high", [], dayLabels.labels, {
        kind: "range",
        days: rangeDays,
        pointLabels: dayLabels.pointLabels,
        unit: temperatureUnit(units),
        primaryLabel: "Low",
        secondaryLabel: "High",
        tone: "primary"
    }));

    charts.push(chart("dailyPrecipitation", "daily", "Daily precipitation", "rainy", "Accumulation and chance", [], dayLabels.labels, {
        kind: "bars",
        bars: mapped(days, day => precipValue(day.precipMm, units)),
        secondary: mapped(days, day => day.precipProb),
        pointLabels: dayLabels.pointLabels,
        unit: precipUnit(units),
        secondaryUnit: "%",
        barLabel: "Total",
        secondaryLabel: "Chance",
        tone: "secondary",
        secondaryTone: "primary",
        barTone: "secondary",
        secondaryMin: 0,
        secondaryMax: 100,
        decimals: units.precip === "in" ? 2 : 1
    }));

    charts.push(chart("dailyWind", "daily", "Daily wind", "air", "Maximum wind and gusts", mapped(days, day => windValue(day.windKmh, units)), dayLabels.labels, {
        secondary: mapped(days, day => windValue(day.gustKmh, units)),
        pointLabels: dayLabels.pointLabels,
        unit: windUnit(units),
        primaryLabel: "Wind",
        secondaryLabel: "Gusts",
        tone: "primary",
        secondaryTone: "tertiary",
        decimals: units.wind === "ms" ? 1 : 0
    }));

    charts.push(chart("dailyUv", "daily", "Daily UV", "wb_sunny", "Maximum UV index", seriesFrom(days, "uv"), dayLabels.labels, {
        pointLabels: dayLabels.pointLabels,
        primaryLabel: "UV",
        tone: "tertiary",
        decimals: 1,
        yMin: 0
    }));

    charts.push(chart("dailyAqi", "daily", "Daily air quality", "masks", "Peak US AQI", seriesFrom(days, "aqi"), dayLabels.labels, {
        pointLabels: dayLabels.pointLabels,
        primaryLabel: "US AQI",
        tone: "primary",
        yMin: 0
    }));

    return charts;
}

function chartsForGroup(charts, group) {
    return (charts || []).filter(item => item.group === group);
}

function hasData(values) {
    return (values || []).some(value => value !== null && value !== undefined && Number.isFinite(Number(value)));
}

function valueAt(values, index) {
    if (!values || index < 0 || index >= values.length)
        return null;
    const value = values[index];
    return value === null || value === undefined || !Number.isFinite(Number(value)) ? null : Number(value);
}

function formatChartValue(value, decimals) {
    if (value === null || value === undefined || !Number.isFinite(Number(value)))
        return "--";
    return String(round(value, decimals === undefined ? 0 : decimals));
}

function chartAxisLabel(value) {
    if (!Number.isFinite(Number(value)))
        return "";
    const n = Number(value);
    if (Math.abs(n) >= 1000) return `${Math.round(n)}`;
    if (Math.abs(n) >= 100) return `${Math.round(n)}`;
    if (Math.abs(n) >= 10) return `${Math.round(n)}`;
    if (Math.abs(n) >= 1) return `${round(n, 1)}`;
    return `${round(n, 2)}`;
}

function currentSummary(data) {
    if (!data || !data.current)
        return "";
    return `${formatTemperature(data.current.tempC, DEFAULT_UNITS)} · ${data.current.summary || conditionText(data.current.condition)}`;
}

function providerModelLabel(data) {
    if (!data)
        return "";
    if (data.providerId === "openMeteo" && data.model && data.model !== "best_match") {
        const names = {
            ecmwf_ifs025: "ECMWF IFS 0.25°",
            dwd_icon: "DWD ICON",
            gfs_seamless: "NOAA GFS",
            meteofrance_seamless: "Météo-France",
            jma_seamless: "JMA",
            ukmo_seamless: "UK Met Office",
            gem_seamless: "Environment Canada"
        };
        return names[data.model] || data.model;
    }
    return data.providerName || "";
}

function alertTone(severity) {
    const s = String(severity || "").toLowerCase();
    if (s.indexOf("extreme") >= 0 || s.indexOf("severe") >= 0) return "error";
    if (s.indexOf("moderate") >= 0) return "tertiary";
    return "primary";
}

function alertIcon(severity) {
    const s = String(severity || "").toLowerCase();
    if (s.indexOf("extreme") >= 0) return "warning";
    if (s.indexOf("severe") >= 0) return "report";
    if (s.indexOf("moderate") >= 0) return "info";
    return "notifications";
}
