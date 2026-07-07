import { FastifyInstance } from "fastify";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { Pool } from "pg";
import { badRequest } from "../lib/badRequest.js";

export type BlockWeatherReading = {
  blockId: string;
  airTemperatureF: number;
  relativeHumidityPct: number;
  leafWetnessHours: number;
  soilMoisturePct: number;
  soilTemperatureF: number;
  rainfallInches24h: number;
  solarExposureMJ: number;
  windSpeedMph: number;
  windDirectionDegrees: number;
  fetchedAt: number;
};

type OpenMeteoCurrent = {
  temperature_2m?: number;
  relative_humidity_2m?: number;
  wind_speed_10m?: number;
  wind_direction_10m?: number;
};

type OpenMeteoHourly = {
  time?: string[];
  precipitation?: Array<number | null>;
  shortwave_radiation?: Array<number | null>;
  soil_temperature_0cm?: Array<number | null>;
  soil_moisture_0_to_7cm?: Array<number | null>;
  relative_humidity_2m?: Array<number | null>;
};

type OpenMeteoResponse = {
  current?: OpenMeteoCurrent;
  hourly?: OpenMeteoHourly;
};

const blockPointSchema = z.object({
  blockId: z.string().min(1),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
});

const batchSchema = z.object({
  points: z.array(blockPointSchema).min(1).max(32),
});

function num(value: number | null | undefined, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function sumLast(values: Array<number | null | undefined>, count: number): number {
  const slice = values.slice(-count);
  return slice.reduce<number>((acc, v) => acc + (typeof v === "number" ? v : 0), 0);
}

function latest(values: Array<number | null | undefined>, fallback: number): number {
  for (let i = values.length - 1; i >= 0; i -= 1) {
    const v = values[i];
    if (typeof v === "number" && Number.isFinite(v)) return v;
  }
  return fallback;
}

function estimateLeafWetnessHours(
  humidityPct: number,
  rainInches24h: number,
  hourlyHumidity: Array<number | null | undefined>
): number {
  const humidHours = hourlyHumidity.slice(-24).filter((v) => typeof v === "number" && v >= 85).length;
  if (rainInches24h >= 0.05) {
    return Math.min(8, humidHours * 0.45 + rainInches24h * 12);
  }
  if (humidityPct >= 90) {
    return Math.min(4, (humidityPct - 85) * 0.25);
  }
  return Math.min(2, humidHours * 0.2);
}

async function fetchOpenMeteoWeather(latitude: number, longitude: number): Promise<BlockWeatherReading | null> {
  const params = new URLSearchParams({
    latitude: String(latitude),
    longitude: String(longitude),
    current: "temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m",
    hourly: "precipitation,shortwave_radiation,soil_temperature_0cm,soil_moisture_0_to_7cm,relative_humidity_2m",
    past_days: "1",
    forecast_days: "0",
    temperature_unit: "fahrenheit",
    wind_speed_unit: "mph",
    precipitation_unit: "inch",
    timezone: "auto",
  });

  const response = await fetch(`https://api.open-meteo.com/v1/forecast?${params.toString()}`);
  if (!response.ok) return null;

  const data = (await response.json()) as OpenMeteoResponse;
  const current = data.current ?? {};
  const hourly = data.hourly ?? {};

  const airTemperatureF = num(current.temperature_2m, 70);
  const relativeHumidityPct = num(current.relative_humidity_2m, 50);
  const windSpeedMph = num(current.wind_speed_10m, 0);
  const windDirectionDegrees = num(current.wind_direction_10m, 0);
  const rainfallInches24h = sumLast(hourly.precipitation ?? [], 24);
  const solarExposureMJ = sumLast(hourly.shortwave_radiation ?? [], 24) * 0.0036;
  const soilTemperatureF = latest(hourly.soil_temperature_0cm ?? [], airTemperatureF - 4);
  const soilMoistureRaw = latest(hourly.soil_moisture_0_to_7cm ?? [], 0.35);
  const soilMoisturePct = soilMoistureRaw <= 1 ? soilMoistureRaw * 100 : soilMoistureRaw;
  const leafWetnessHours = estimateLeafWetnessHours(
    relativeHumidityPct,
    rainfallInches24h,
    hourly.relative_humidity_2m ?? []
  );

  return {
    blockId: "",
    airTemperatureF,
    relativeHumidityPct,
    leafWetnessHours,
    soilMoisturePct,
    soilTemperatureF,
    rainfallInches24h,
    solarExposureMJ,
    windSpeedMph,
    windDirectionDegrees,
    fetchedAt: Date.now(),
  };
}

export async function weatherRoutes(app: FastifyInstance, db: Pool) {
  app.post("/v1/weather/blocks", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = batchSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send(badRequest(parsed.error));

    const items: BlockWeatherReading[] = [];
    for (const point of parsed.data.points) {
      const weather = await fetchOpenMeteoWeather(point.latitude, point.longitude);
      if (!weather) continue;
      items.push({ ...weather, blockId: point.blockId });
    }

    return { items };
  });
}
