// Astronomy fallback for the ii Weather app.
//
// Weather providers disagree about which astronomy fields they publish: some
// send sunrise and sunset, some only moon phase, and a few send nothing at all.
// This module fills the gaps with local calculations (a compact port of the
// standard SunCalc formulas). Provider values always win when present.

const rad = Math.PI / 180;
const dayMs = 86400000;
const J1970 = 2440588;
const J2000 = 2451545;
const e = rad * 23.4397;

function toJulian(ms) {
    return ms / dayMs - 0.5 + J1970;
}

function fromJulian(j) {
    return (j + 0.5 - J1970) * dayMs;
}

function toDays(ms) {
    return toJulian(ms) - J2000;
}

function rightAscension(l, b) {
    return Math.atan2(Math.sin(l) * Math.cos(e) - Math.tan(b) * Math.sin(e), Math.cos(l));
}

function declination(l, b) {
    return Math.asin(Math.sin(b) * Math.cos(e) + Math.cos(b) * Math.sin(e) * Math.sin(l));
}

function azimuth(H, phi, dec) {
    return Math.atan2(Math.sin(H), Math.cos(H) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi));
}

function altitude(H, phi, dec) {
    return Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(H));
}

function siderealTime(d, lw) {
    return rad * (280.16 + 360.9856235 * d) - lw;
}

function solarMeanAnomaly(d) {
    return rad * (357.5291 + 0.98560028 * d);
}

function eclipticLongitude(M) {
    const C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M));
    const P = rad * 102.9372;
    return M + C + P + Math.PI;
}

function sunCoords(d) {
    const M = solarMeanAnomaly(d);
    const L = eclipticLongitude(M);
    return { dec: declination(L, 0), ra: rightAscension(L, 0) };
}

function moonCoords(d) {
    const L = rad * (218.316 + 13.176396 * d);
    const M = rad * (134.963 + 13.064993 * d);
    const F = rad * (93.272 + 13.229350 * d);
    const l = L + rad * 6.289 * Math.sin(M);
    const b = rad * 5.128 * Math.sin(F);
    const dt = 385001 - 20905 * Math.cos(M);
    return { ra: rightAscension(l, b), dec: declination(l, b), dist: dt };
}

function julianCycle(d, lw) {
    return Math.round(d - 0.0009 - lw / (2 * Math.PI));
}

function approxTransit(Ht, lw, n) {
    return 0.0009 + (Ht + lw) / (2 * Math.PI) + n;
}

function solarTransitJ(ds, M, L) {
    return J2000 + ds + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
}

function hourAngle(h, phi, d) {
    const cosH = (Math.sin(h) - Math.sin(phi) * Math.sin(d)) / (Math.cos(phi) * Math.cos(d));
    if (cosH > 1 || cosH < -1)
        return null;
    return Math.acos(cosH);
}

function getSetJ(h, lw, phi, dec, n, M, L) {
    const w = hourAngle(h, phi, dec);
    if (w === null)
        return null;
    const a = approxTransit(w, lw, n);
    return solarTransitJ(a, M, L);
}

function sunTimes(dateMs, latitude, longitude) {
    const lw = rad * -longitude;
    const phi = rad * latitude;
    const d = toDays(dateMs);
    const n = julianCycle(d, lw);
    const ds = approxTransit(0, lw, n);
    const M = solarMeanAnomaly(ds);
    const L = eclipticLongitude(M);
    const dec = declination(L, 0);
    const Jnoon = solarTransitJ(ds, M, L);
    const Jset = getSetJ(rad * -0.833, lw, phi, dec, n, M, L);
    const Jrise = Jset === null ? null : Jnoon - (Jset - Jnoon);
    return {
        sunrise: Jrise === null ? null : fromJulian(Jrise),
        sunset: Jset === null ? null : fromJulian(Jset),
        solarNoon: fromJulian(Jnoon)
    };
}

function sunPosition(dateMs, latitude, longitude) {
    const lw = rad * -longitude;
    const phi = rad * latitude;
    const d = toDays(dateMs);
    const c = sunCoords(d);
    const H = siderealTime(d, lw) - c.ra;
    return {
        altitude: altitude(H, phi, c.dec),
        azimuth: azimuth(H, phi, c.dec)
    };
}

function moonPosition(dateMs, latitude, longitude) {
    const lw = rad * -longitude;
    const phi = rad * latitude;
    const d = toDays(dateMs);
    const c = moonCoords(d);
    const H = siderealTime(d, lw) - c.ra;
    return {
        altitude: altitude(H, phi, c.dec),
        azimuth: azimuth(H, phi, c.dec),
        distance: c.dist
    };
}

function moonIllumination(dateMs) {
    const d = toDays(dateMs);
    const s = sunCoords(d);
    const m = moonCoords(d);
    const sdist = 149598000;
    const phi = Math.acos(Math.sin(s.dec) * Math.sin(m.dec) + Math.cos(s.dec) * Math.cos(m.dec) * Math.cos(s.ra - m.ra));
    const inc = Math.atan2(sdist * Math.sin(phi), m.dist - sdist * Math.cos(phi));
    const angle = Math.atan2(
        Math.cos(s.dec) * Math.sin(s.ra - m.ra),
        Math.sin(s.dec) * Math.cos(m.dec) - Math.cos(s.dec) * Math.sin(m.dec) * Math.cos(s.ra - m.ra)
    );
    return {
        fraction: (1 + Math.cos(inc)) / 2,
        phase: 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / Math.PI,
        angle: angle
    };
}

// Search the local day for the two altitude crossings. startMs is local
// midnight at the location, not this machine's midnight.
function moonTimes(startMs, latitude, longitude) {
    const hc = 0.133 * rad;
    const step = 2 * 3600000;
    let h0 = moonPosition(startMs, latitude, longitude).altitude - hc;
    let rise = null;
    let set = null;
    for (let i = 1; i <= 24; i += 2) {
        const h1 = moonPosition(startMs + i * step, latitude, longitude).altitude - hc;
        const h2 = moonPosition(startMs + (i + 1) * step, latitude, longitude).altitude - hc;
        const a = (h0 + h2) / 2 - h1;
        const b = (h2 - h0) / 2;
        const xe = -b / (2 * a);
        const ye = (a * xe + b) * xe + h1;
        const d = b * b - 4 * a * h1;
        let roots = 0;
        let x1 = 0;
        let x2 = 0;
        if (d >= 0) {
            const dx = Math.sqrt(d) / (Math.abs(a) * 2);
            x1 = xe - dx;
            x2 = xe + dx;
            if (Math.abs(x1) <= 1) roots++;
            if (Math.abs(x2) <= 1) roots++;
            if (x1 < -1)
                x1 = x2;
        }
        if (roots === 1) {
            if (h0 < 0)
                rise = i + x1;
            else
                set = i + x1;
        } else if (roots === 2) {
            rise = i + (ye < 0 ? x2 : x1);
            set = i + (ye < 0 ? x1 : x2);
        }
        if (rise !== null && set !== null)
            break;
        h0 = h2;
    }
    const dayEnd = startMs + 86400000;
    let moonrise = rise === null ? null : startMs + rise * step;
    let moonset = set === null ? null : startMs + set * step;
    if (moonrise !== null && (moonrise < startMs || moonrise >= dayEnd)) moonrise = null;
    if (moonset !== null && (moonset < startMs || moonset >= dayEnd)) moonset = null;
    return { moonrise: moonrise, moonset: moonset };
}

function localDayStart(ms, offsetSeconds) {
    const offset = offsetSeconds * 1000;
    return Math.floor((ms + offset) / dayMs) * dayMs - offset;
}

function localDateKey(ms, offsetSeconds) {
    return new Date(ms + offsetSeconds * 1000).toISOString().slice(0, 10);
}

function phaseName(phase) {
    const p = ((Number(phase) % 1) + 1) % 1;
    if (p < 0.03 || p >= 0.97) return "New moon";
    if (p < 0.22) return "Waxing crescent";
    if (p < 0.28) return "First quarter";
    if (p < 0.47) return "Waxing gibbous";
    if (p < 0.53) return "Full moon";
    if (p < 0.72) return "Waning gibbous";
    if (p < 0.78) return "Last quarter";
    return "Waning crescent";
}

function fillDailyAstro(day, latitude, longitude, offsetSeconds) {
    const result = Object.assign({}, day);
    const noon = (result.time ?? localDayStart(Date.now(), offsetSeconds)) + 12 * 3600000;
    if (result.sunrise === null || result.sunrise === undefined || result.sunset === null || result.sunset === undefined) {
        const times = sunTimes(noon, latitude, longitude);
        if (result.sunrise === null || result.sunrise === undefined)
            result.sunrise = times.sunrise;
        if (result.sunset === null || result.sunset === undefined)
            result.sunset = times.sunset;
    }
    if (result.moonrise === null || result.moonrise === undefined || result.moonset === null || result.moonset === undefined) {
        const start = localDayStart(noon, offsetSeconds);
        const times = moonTimes(start, latitude, longitude);
        if (result.moonrise === null || result.moonrise === undefined)
            result.moonrise = times.moonrise;
        if (result.moonset === null || result.moonset === undefined)
            result.moonset = times.moonset;
    }
    if (result.moonPhase === null || result.moonPhase === undefined || result.moonIllum === null || result.moonIllum === undefined) {
        const illum = moonIllumination(noon);
        if (result.moonPhase === null || result.moonPhase === undefined)
            result.moonPhase = illum.phase;
        if (result.moonIllum === null || result.moonIllum === undefined)
            result.moonIllum = illum.fraction * 100;
    }
    if ((result.daylight === null || result.daylight === undefined) && result.sunrise && result.sunset)
        result.daylight = (result.sunset - result.sunrise) / 1000;
    return result;
}

function enrich(data) {
    if (!data || !data.current)
        return data;
    const latitude = Number(data.location?.latitude ?? 0);
    const longitude = Number(data.location?.longitude ?? 0);
    const offset = Number(data.utcOffset ?? data.location?.utcOffset ?? 0);
    const daily = (data.daily || []).map(day => fillDailyAstro(day, latitude, longitude, offset));
    const byDate = {};
    for (const day of daily)
        byDate[localDateKey(day.time, offset)] = day;

    const hourly = (data.hourly || []).map(hour => {
        if (hour.isDay !== null && hour.isDay !== undefined)
            return hour;
        const day = byDate[localDateKey(hour.time, offset)];
        if (day && day.sunrise && day.sunset)
            return Object.assign({}, hour, { isDay: hour.time >= day.sunrise && hour.time < day.sunset });
        const position = sunPosition(hour.time, latitude, longitude);
        return Object.assign({}, hour, { isDay: position.altitude > -0.833 * rad });
    });

    const current = Object.assign({}, data.current);
    const today = daily[0];
    if (today) {
        if (current.highC === null || current.highC === undefined) current.highC = today.maxC;
        if (current.lowC === null || current.lowC === undefined) current.lowC = today.minC;
        if (current.sunrise === null || current.sunrise === undefined) current.sunrise = today.sunrise;
        if (current.sunset === null || current.sunset === undefined) current.sunset = today.sunset;
        if (current.moonrise === null || current.moonrise === undefined) current.moonrise = today.moonrise;
        if (current.moonset === null || current.moonset === undefined) current.moonset = today.moonset;
        if (current.moonPhase === null || current.moonPhase === undefined) current.moonPhase = today.moonPhase;
        if (current.moonIllum === null || current.moonIllum === undefined) current.moonIllum = today.moonIllum;
    }
    if (current.isDay === null || current.isDay === undefined) {
        if (current.sunrise && current.sunset)
            current.isDay = current.time >= current.sunrise && current.time < current.sunset;
        else
            current.isDay = sunPosition(current.time || Date.now(), latitude, longitude).altitude > -0.833 * rad;
    }
    if (!current.summary)
        current.summary = conditionText(current.condition);
    if (current.moonPhase !== null && current.moonPhase !== undefined)
        current.moonPhaseName = phaseName(current.moonPhase);

    const astronomy = {
        sunrise: current.sunrise,
        sunset: current.sunset,
        moonrise: current.moonrise,
        moonset: current.moonset,
        moonPhase: current.moonPhase,
        moonPhaseName: current.moonPhaseName || phaseName(current.moonPhase ?? 0),
        moonIllum: current.moonIllum,
        daylight: current.sunrise && current.sunset ? (current.sunset - current.sunrise) / 1000 : null
    };

    return Object.assign({}, data, { current, hourly, daily, astronomy });
}

function conditionText(code) {
    const c = Number(code);
    if (c === 0) return "Clear sky";
    if (c === 1) return "Mainly clear";
    if (c === 2) return "Partly cloudy";
    if (c === 3) return "Overcast";
    if (c === 45 || c === 48) return "Fog";
    if (c >= 51 && c <= 57) return "Drizzle";
    if (c === 61) return "Slight rain";
    if (c === 63) return "Moderate rain";
    if (c === 65) return "Heavy rain";
    if (c === 66 || c === 67) return "Freezing rain";
    if (c === 71) return "Slight snow";
    if (c === 73) return "Moderate snow";
    if (c === 75 || c === 77) return "Snow";
    if (c === 80) return "Slight showers";
    if (c === 81) return "Moderate showers";
    if (c === 82) return "Violent showers";
    if (c === 85 || c === 86) return "Snow showers";
    if (c >= 95) return "Thunderstorm";
    return "Unknown conditions";
}
