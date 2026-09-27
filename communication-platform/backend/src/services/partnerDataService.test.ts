import assert from "node:assert/strict";
import test from "node:test";
import {
  PARTNER_FARMS,
  publicDeviceId,
  recommendationsFromDailyMetrics,
} from "./partnerDataService.js";

test("partner device ids do not expose internal farm ids", () => {
  const farm = PARTNER_FARMS[0];
  const result = publicDeviceId(farm, `${farm.farmId}-A7`, "PB Node A7");
  assert.equal(result, "farm-1-a7");
  assert.equal(result.includes(farm.farmId), false);
});
test("moist conditions produce evidence-linked scouting guidance", () => {
  const farm = PARTNER_FARMS[0];
  const items = recommendationsFromDailyMetrics(farm, [{
    date: "2026-08-20",
    sampleCount: 72,
    temperature: { average: 22, minimum: 17, maximum: 27, unit: "C" },
    humidity: { average: 90, minimum: 70, maximum: 99, unit: "%" },
    leafWetness: { average: 60, minimum: 20, maximum: 90, unit: "%" },
  }]);
  assert.equal(items[0].severity, "attention");
  assert.match(items[0].recommendation, /scouting/i);
  assert.match(items[0].evidence, /99%/);
  assert.match(items[0].disclaimer, /not a fertilizer-rate/i);
});

test("ordinary conditions retain a reproducible routine record", () => {
  const farm = PARTNER_FARMS[1];
  const items = recommendationsFromDailyMetrics(farm, [{
    date: "2026-09-14",
    sampleCount: 72,
    temperature: { average: 20, minimum: 14, maximum: 26, unit: "C" },
    humidity: { average: 70, minimum: 45, maximum: 84, unit: "%" },
    leafWetness: { average: 30, minimum: 10, maximum: 45, unit: "%" },
  }]);
  assert.equal(items.length, 1);
  assert.equal(items[0].severity, "normal");
});
