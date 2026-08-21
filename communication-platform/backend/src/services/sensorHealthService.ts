import { Pool } from "pg";
import { FastifyBaseLogger } from "fastify";
import { createId } from "../lib/id.js";
import { sendSensorHealthAlert } from "./mailService.js";

/**
 * Watches shipped nodes for readings that look like a hardware fault rather than real microclimate,
 * and alarms the Persephone's Basket team.
 *
 * Design intent: a field sensor is SUPPOSED to differ from the regional weather API — that is the
 * product. So the thresholds here are deliberately generous; they fire only on divergence too large
 * to be microclimate, plus unambiguous faults (impossible values, stuck readings, going silent).
 * This keeps the ops inbox quiet enough that an alert actually means something.
 */

// A reading physically outside these bounds is a sensor fault, not weather.
const RANGE = {
  temperature: { min: -40, max: 60, unit: "C" },
  humidity: { min: 0, max: 100, unit: "%" },
  soil_moisture: { min: 0, max: 100, unit: "%" },
} as const;

// Divergence from the weather API beyond what canopy/aspect/elevation can plausibly explain.
const DIVERGENCE = {
  temperatureC: 12, // regional-to-canopy differences rarely exceed ~8-10C
  humidityPct: 35, // microclimate RH swings ~15-25%; 35+ points at a fault
};

const FLATLINE_MIN_SAMPLES = 6; // identical value this many times in a row...
const FLATLINE_MIN_HOURS = 3; // ...spanning at least this long = stuck sensor
const SILENT_MIN_HOURS = 3; // reported within the last ~2 days but silent this long = went dark
const SILENT_MAX_HOURS = 48;
const ACTIVE_WINDOW_HOURS = 48;

type DeviceRow = {
  id: string;
  name: string;
  farm_id: string;
  farm_name: string;
  latitude: number | null;
  longitude: number | null;
  last_seen_at: string;
};

type ReadingRow = { sensor_type: string; value: number; created_at: string };

type Candidate = {
  deviceId: string;
  deviceName: string;
  farmId: string;
  farmName: string;
  kind: "out_of_range" | "flatline" | "went_silent" | "weather_divergence";
  sensorType: string | null;
  severity: "warning" | "critical";
  detail: string;
  sensorValue: number | null;
  referenceValue: number | null;
};

/** Minimal weather snapshot for comparison; converts the API's °F to °C to match sensor units. */
async function fetchWeatherCelsius(
  lat: number,
  lng: number
): Promise<{ temperatureC: number; humidityPct: number } | null> {
  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lng),
    current: "temperature_2m,relative_humidity_2m",
    temperature_unit: "celsius",
    forecast_days: "0",
    past_days: "1",
    timezone: "auto",
  });
  try {
    const res = await fetch(`https://api.open-meteo.com/v1/forecast?${params.toString()}`);
    if (!res.ok) return null;
    const data = (await res.json()) as {
      current?: { temperature_2m?: number; relative_humidity_2m?: number };
    };
    const t = data.current?.temperature_2m;
    const h = data.current?.relative_humidity_2m;
    if (typeof t !== "number" || typeof h !== "number") return null;
    return { temperatureC: t, humidityPct: h };
  } catch {
    return null;
  }
}

function hoursSince(ms: number): number {
  return (Date.now() - ms) / (1000 * 60 * 60);
}

async function evaluateDevice(
  db: Pool,
  device: DeviceRow
): Promise<Candidate[]> {
  const candidates: Candidate[] = [];
  const base = {
    deviceId: device.id,
    deviceName: device.name,
    farmId: device.farm_id,
    farmName: device.farm_name,
  };

  const lastSeen = Number(device.last_seen_at);
  const silentHours = hoursSince(lastSeen);

  // Went silent: was active in the last couple of days but has stopped reporting.
  if (silentHours >= SILENT_MIN_HOURS && silentHours <= SILENT_MAX_HOURS) {
    candidates.push({
      ...base,
      kind: "went_silent",
      sensorType: null,
      severity: silentHours >= 12 ? "critical" : "warning",
      detail: `No readings for ${silentHours.toFixed(1)}h (last seen ${new Date(lastSeen).toISOString()}). Check power/network.`,
      sensorValue: null,
      referenceValue: null,
    });
    // A silent device has nothing fresh to range/flatline/compare; stop here.
    return candidates;
  }

  // Recent readings per sensor type (newest first), last 12h.
  const cutoff = Date.now() - 12 * 60 * 60 * 1000;
  const { rows } = await db.query<ReadingRow>(
    `SELECT sensor_type, value, created_at
     FROM sensor_readings
     WHERE device_id = $1 AND created_at >= $2
     ORDER BY created_at DESC`,
    [device.id, cutoff]
  );

  const byType = new Map<string, ReadingRow[]>();
  for (const row of rows) {
    const list = byType.get(row.sensor_type) ?? [];
    list.push(row);
    byType.set(row.sensor_type, list);
  }

  for (const [type, readings] of byType) {
    const latest = readings[0];
    if (!latest) continue;
    const value = Number(latest.value);

    // Out of physical range.
    const range = (RANGE as Record<string, { min: number; max: number; unit: string }>)[type];
    if (range && (value < range.min || value > range.max)) {
      candidates.push({
        ...base,
        kind: "out_of_range",
        sensorType: type,
        severity: "critical",
        detail: `${type} reading ${value}${range.unit} is outside the possible range ${range.min}–${range.max}${range.unit}. Sensor likely faulty.`,
        sensorValue: value,
        referenceValue: null,
      });
      continue; // an impossible value isn't worth flatline/divergence checks
    }

    // Flatline: identical value across enough samples spanning enough time.
    if (readings.length >= FLATLINE_MIN_SAMPLES) {
      const window = readings.slice(0, FLATLINE_MIN_SAMPLES);
      const allEqual = window.every((r) => Number(r.value) === value);
      const spanHours = hoursSince(Number(window[window.length - 1].created_at))
        - hoursSince(Number(window[0].created_at));
      if (allEqual && Math.abs(spanHours) >= FLATLINE_MIN_HOURS) {
        candidates.push({
          ...base,
          kind: "flatline",
          sensorType: type,
          severity: "warning",
          detail: `${type} has been stuck at exactly ${value} for ${Math.abs(spanHours).toFixed(1)}h (${FLATLINE_MIN_SAMPLES}+ identical readings). Sensor likely stuck.`,
          sensorValue: value,
          referenceValue: null,
        });
      }
    }
  }

  // Weather divergence — only if we know where the device is.
  if (device.latitude != null && device.longitude != null) {
    const weather = await fetchWeatherCelsius(device.latitude, device.longitude);
    if (weather) {
      const temp = byType.get("temperature")?.[0];
      if (temp) {
        const diff = Math.abs(Number(temp.value) - weather.temperatureC);
        if (diff > DIVERGENCE.temperatureC) {
          candidates.push({
            ...base,
            kind: "weather_divergence",
            sensorType: "temperature",
            severity: diff > DIVERGENCE.temperatureC * 1.6 ? "critical" : "warning",
            detail: `Temperature ${Number(temp.value).toFixed(1)}C differs from the weather API (${weather.temperatureC.toFixed(1)}C) by ${diff.toFixed(1)}C — larger than microclimate explains. Check placement/calibration.`,
            sensorValue: Number(temp.value),
            referenceValue: weather.temperatureC,
          });
        }
      }
      const hum = byType.get("humidity")?.[0];
      if (hum) {
        const diff = Math.abs(Number(hum.value) - weather.humidityPct);
        if (diff > DIVERGENCE.humidityPct) {
          candidates.push({
            ...base,
            kind: "weather_divergence",
            sensorType: "humidity",
            severity: diff > DIVERGENCE.humidityPct * 1.6 ? "critical" : "warning",
            detail: `Humidity ${Number(hum.value).toFixed(0)}% differs from the weather API (${weather.humidityPct.toFixed(0)}%) by ${diff.toFixed(0)} points — larger than microclimate explains. Check the sensor.`,
            sensorValue: Number(hum.value),
            referenceValue: weather.humidityPct,
          });
        }
      }
    }
  }

  return candidates;
}

/**
 * Runs one health sweep. Opens new alerts, refreshes ongoing ones, resolves cleared ones, and
 * emails the ops team about newly-opened alerts. Returns a summary for the admin endpoint.
 *
 * The (device, kind, sensor_type) unique index means an ongoing fault is one row, not a new alert
 * every 2 hours, so the team is emailed once per distinct problem, not spammed.
 */
export async function runSensorHealthCheck(
  db: Pool,
  logger: FastifyBaseLogger
): Promise<{ checked: number; opened: number; resolved: number; open: number }> {
  const activeCutoff = Date.now() - ACTIVE_WINDOW_HOURS * 60 * 60 * 1000;
  const { rows: devices } = await db.query<DeviceRow>(
    `SELECT d.id, d.name, d.farm_id, d.farm_name, d.latitude, d.longitude, d.last_seen_at
     FROM devices d
     WHERE d.last_seen_at >= $1`,
    [activeCutoff]
  );

  const detected: Candidate[] = [];
  for (const device of devices) {
    try {
      detected.push(...(await evaluateDevice(db, device)));
    } catch (error) {
      logger.error({ error, deviceId: device.id }, "sensor health check failed for device");
    }
  }

  const key = (c: { deviceId: string; kind: string; sensorType: string | null }) =>
    `${c.deviceId}|${c.kind}|${c.sensorType ?? ""}`;
  const detectedKeys = new Set(detected.map(key));

  const newlyOpened: Candidate[] = [];

  for (const c of detected) {
    // Upsert on the open-alert unique index: refresh if ongoing, insert if new.
    const res = await db.query<{ inserted: boolean }>(
      `INSERT INTO sensor_health_alerts
         (id, device_id, farm_id, kind, sensor_type, severity, detail, sensor_value, reference_value)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (device_id, kind, COALESCE(sensor_type, ''))
         WHERE resolved_at IS NULL
       DO UPDATE SET severity = EXCLUDED.severity,
                     detail = EXCLUDED.detail,
                     sensor_value = EXCLUDED.sensor_value,
                     reference_value = EXCLUDED.reference_value,
                     updated_at = NOW()
       RETURNING (xmax = 0) AS inserted`,
      [
        createId("sha"),
        c.deviceId,
        c.farmId,
        c.kind,
        c.sensorType,
        c.severity,
        c.detail,
        c.sensorValue,
        c.referenceValue,
      ]
    );
    if (res.rows[0]?.inserted) newlyOpened.push(c);
  }

  // Resolve open alerts whose condition is no longer detected.
  const { rows: openRows } = await db.query<{
    id: string;
    device_id: string;
    kind: string;
    sensor_type: string | null;
  }>(
    "SELECT id, device_id, kind, sensor_type FROM sensor_health_alerts WHERE resolved_at IS NULL"
  );
  let resolved = 0;
  for (const row of openRows) {
    if (!detectedKeys.has(`${row.device_id}|${row.kind}|${row.sensor_type ?? ""}`)) {
      await db.query("UPDATE sensor_health_alerts SET resolved_at = NOW() WHERE id = $1", [row.id]);
      resolved += 1;
    }
  }

  if (newlyOpened.length > 0) {
    const sent = await sendSensorHealthAlert(newlyOpened, logger);
    if (sent) {
      await db.query(
        `UPDATE sensor_health_alerts SET notified_at = NOW()
         WHERE resolved_at IS NULL AND notified_at IS NULL`
      );
    }
  }

  const openCount = openRows.length - resolved + newlyOpened.length;
  logger.info(
    { checked: devices.length, opened: newlyOpened.length, resolved },
    "sensor health check complete"
  );
  return { checked: devices.length, opened: newlyOpened.length, resolved, open: openCount };
}
