import test from "node:test";
import assert from "node:assert/strict";
import {
  MOTION_ACTIVITY_CONFIDENCE, MOTION_ACTIVITY_TYPE, internals, parseFields, patchWlocBody
} from "../src/core.js";

const { concat, writeVarint, writeTag, writeLengthDelimited } = internals;

function location(withMotion = false) {
  const fields = [
    concat(writeTag(1, 0), writeVarint(100)),
    concat(writeTag(2, 0), writeVarint(200)),
    concat(writeTag(3, 0), writeVarint(25))
  ];
  if (withMotion) {
    fields.push(concat(writeTag(11, 0), writeVarint(7)));
    fields.push(concat(writeTag(12, 0), writeVarint(88)));
  }
  return concat(...fields);
}

function wifiPayload(value = location()) {
  const device = concat(
    writeLengthDelimited(1, new TextEncoder().encode("aa:bb:cc:dd:ee:ff")),
    writeLengthDelimited(2, value)
  );
  return writeLengthDelimited(2, device);
}

function frame(payload) {
  return concat(Uint8Array.from([0, 1, 0, 0, 0, 1, 0, 0]),
    Uint8Array.from([payload.length >> 8, payload.length & 0xff]), payload);
}

const config = {
  latitude: 31.230416,
  longitude: 121.473701,
  accuracy: 50,
  motionSimulationEnabled: false
};

test("patches synthetic Wi-Fi response", () => {
  const result = patchWlocBody(frame(wifiPayload()), config);
  assert.equal(result.stats.wifi, 1);
  assert.equal(result.stats.locations, 1);
});

test("preserves motion fields while disabled", () => {
  const result = patchWlocBody(frame(wifiPayload(location(true))), config);
  const payload = result.data.slice(10);
  assert.ok(payload.includes(7));
  assert.ok(payload.includes(88));
});

test("replaces motion fields while enabled", () => {
  const result = patchWlocBody(frame(wifiPayload(location(true))), {
    ...config, motionSimulationEnabled: true
  });
  const root = parseFields(result.data.slice(10));
  const device = parseFields(root[0].value);
  const fields = parseFields(device.find((field) => field.number === 2).value);
  const motionType = fields.find((field) => field.number === 11);
  const motionConfidence = fields.find((field) => field.number === 12);
  assert.deepEqual(motionType.value, writeVarint(MOTION_ACTIVITY_TYPE));
  assert.deepEqual(motionConfidence.value, writeVarint(MOTION_ACTIVITY_CONFIDENCE));
});

test("patches CellTower fields 22 and 24", () => {
  for (const number of [22, 24]) {
    const cell = writeLengthDelimited(5, location());
    const result = patchWlocBody(frame(writeLengthDelimited(number, cell)), config);
    assert.equal(result.stats.cell, 1);
  }
});

test("encodes signed int64 coordinates without BigInt", () => {
  assert.deepEqual(
    Array.from(writeVarint(-18_000_000_000)),
    [128, 152, 247, 248, 188, 255, 255, 255, 255, 1]
  );
  assert.deepEqual(
    Array.from(writeVarint(18_000_000_000)),
    [128, 232, 136, 135, 67]
  );
});
