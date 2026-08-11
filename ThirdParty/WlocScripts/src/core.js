export const MOTION_ACTIVITY_TYPE = 63;
export const MOTION_ACTIVITY_CONFIDENCE = 467;
export const WLOC_MARKER = Uint8Array.from([0, 0, 0, 1, 0, 0]);
const UINT32_RANGE = 0x100000000;

const concat = (...parts) => {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
};

const equal = (left, right) =>
  left.length === right.length && left.every((value, index) => value === right[index]);

function readVarint(data, offset) {
  let value = 0;
  let multiplier = 1;
  for (let index = 0; index < 10 && offset + index < data.length; index += 1) {
    const byte = data[offset + index];
    const chunk = byte & 0x7f;
    if (value !== null && chunk <= Math.floor((Number.MAX_SAFE_INTEGER - value) / multiplier)) {
      value += chunk * multiplier;
    } else {
      value = null;
    }
    if ((byte & 0x80) === 0) return { value, next: offset + index + 1 };
    multiplier *= 0x80;
  }
  throw new Error("invalid varint");
}

function writeVarint(input) {
  const value = Math.trunc(Number(input));
  if (!Number.isSafeInteger(value)) throw new Error("varint value is not a safe integer");
  let low = value >>> 0;
  let high = Math.floor(value / UINT32_RANGE) >>> 0;
  const bytes = [];
  do {
    const byte = low & 0x7f;
    low = ((low >>> 7) | ((high & 0x7f) << 25)) >>> 0;
    high >>>= 7;
    const hasMore = high !== 0 || low !== 0;
    bytes.push(byte | (hasMore ? 0x80 : 0));
  } while (high !== 0 || low !== 0);
  return Uint8Array.from(bytes);
}

const writeTag = (number, wireType) => writeVarint((number << 3) | wireType);

function writeLengthDelimited(number, value) {
  return concat(writeTag(number, 2), writeVarint(value.length), value);
}

export function parseFields(data) {
  const fields = [];
  let offset = 0;
  while (offset < data.length) {
    const start = offset;
    const tag = readVarint(data, offset);
    offset = tag.next;
    if (!Number.isSafeInteger(tag.value)) throw new Error("protobuf tag is too large");
    const number = Math.floor(tag.value / 8);
    const wireType = tag.value & 7;
    if (number === 0) throw new Error("invalid protobuf field 0");
    let value;
    if (wireType === 0) {
      const item = readVarint(data, offset);
      value = data.slice(offset, item.next);
      offset = item.next;
    } else if (wireType === 1) {
      if (offset + 8 > data.length) throw new Error("truncated fixed64");
      value = data.slice(offset, offset + 8);
      offset += 8;
    } else if (wireType === 2) {
      const length = readVarint(data, offset);
      offset = length.next;
      const size = length.value;
      if (!Number.isSafeInteger(size) || offset + size > data.length) {
        throw new Error("truncated length-delimited field");
      }
      value = data.slice(offset, offset + size);
      offset += size;
    } else if (wireType === 5) {
      if (offset + 4 > data.length) throw new Error("truncated fixed32");
      value = data.slice(offset, offset + 4);
      offset += 4;
    } else {
      throw new Error(`unsupported wire type ${wireType}`);
    }
    fields.push({ number, wireType, value, raw: data.slice(start, offset) });
  }
  return fields;
}

function patchLocation(data, config, stats) {
  const fields = parseFields(data);
  if (!fields.some((field) => field.number === 1 && field.wireType === 0) ||
      !fields.some((field) => field.number === 2 && field.wireType === 0)) {
    return data;
  }
  let hasMotionType = false;
  let hasMotionConfidence = false;
  const parts = fields.map((field) => {
    if (field.wireType !== 0) return field.raw;
    if (field.number === 1) return concat(writeTag(1, 0), writeVarint(Math.round(config.latitude * 1e8)));
    if (field.number === 2) return concat(writeTag(2, 0), writeVarint(Math.round(config.longitude * 1e8)));
    if (field.number === 3) return concat(writeTag(3, 0), writeVarint(config.accuracy));
    if (config.motionSimulationEnabled && field.number === 11) {
      hasMotionType = true;
      return concat(writeTag(11, 0), writeVarint(MOTION_ACTIVITY_TYPE));
    }
    if (config.motionSimulationEnabled && field.number === 12) {
      hasMotionConfidence = true;
      return concat(writeTag(12, 0), writeVarint(MOTION_ACTIVITY_CONFIDENCE));
    }
    return field.raw;
  });
  if (config.motionSimulationEnabled && !hasMotionType) {
    parts.push(concat(writeTag(11, 0), writeVarint(MOTION_ACTIVITY_TYPE)));
  }
  if (config.motionSimulationEnabled && !hasMotionConfidence) {
    parts.push(concat(writeTag(12, 0), writeVarint(MOTION_ACTIVITY_CONFIDENCE)));
  }
  const out = concat(...parts);
  if (!equal(out, data)) stats.locations += 1;
  return out;
}

function patchWifi(data, config, stats) {
  const fields = parseFields(data);
  const hasMac = fields.some((field) =>
    field.number === 1 && field.wireType === 2 &&
    /^[0-9a-fA-F]{1,2}(:[0-9a-fA-F]{1,2}){5}$/.test(
      Array.from(field.value, (byte) => String.fromCharCode(byte)).join("")
    )
  );
  if (!hasMac) return data;
  let changed = false;
  const parts = fields.map((field) => {
    if (field.number !== 2 || field.wireType !== 2) return field.raw;
    const value = patchLocation(field.value, config, stats);
    changed ||= !equal(value, field.value);
    return writeLengthDelimited(2, value);
  });
  if (changed) stats.wifi += 1;
  return concat(...parts);
}

function patchCell(data, config, stats) {
  let changed = false;
  const parts = parseFields(data).map((field) => {
    if (field.number !== 5 || field.wireType !== 2) return field.raw;
    const value = patchLocation(field.value, config, stats);
    changed ||= !equal(value, field.value);
    return writeLengthDelimited(5, value);
  });
  if (changed) stats.cell += 1;
  return concat(...parts);
}

export function patchPayload(data, config, stats = { wifi: 0, cell: 0, locations: 0 }) {
  const parts = parseFields(data).map((field) => {
    if (field.number === 2 && field.wireType === 2) {
      return writeLengthDelimited(2, patchWifi(field.value, config, stats));
    }
    if ((field.number === 22 || field.number === 24) && field.wireType === 2) {
      return writeLengthDelimited(field.number, patchCell(field.value, config, stats));
    }
    return field.raw;
  });
  return { data: concat(...parts), stats };
}

const uint16 = (data, offset) => (data[offset] << 8) | data[offset + 1];
const uint32 = (data, offset) =>
  ((data[offset] * 0x1000000) + (data[offset + 1] << 16) +
   (data[offset + 2] << 8) + data[offset + 3]) >>> 0;
const writeUint16 = (value) => Uint8Array.from([(value >>> 8) & 0xff, value & 0xff]);
const writeUint32 = (value) => Uint8Array.from([
  (value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff
]);

function findBytes(data, marker) {
  outer: for (let offset = 0; offset <= data.length - marker.length; offset += 1) {
    for (let index = 0; index < marker.length; index += 1) {
      if (data[offset + index] !== marker[index]) continue outer;
    }
    return offset;
  }
  return -1;
}

function patchARPC(body, config) {
  if (body.length < 2) throw new Error("short ARPC");
  let offset = 2;
  for (let index = 0; index < 3; index += 1) {
    if (offset + 2 > body.length) throw new Error("truncated ARPC string");
    offset += 2 + uint16(body, offset);
  }
  const lengthOffset = offset + 4;
  const payloadOffset = lengthOffset + 4;
  if (payloadOffset > body.length) throw new Error("truncated ARPC header");
  const length = uint32(body, lengthOffset);
  if (!length || payloadOffset + length > body.length) throw new Error("invalid ARPC length");
  const patched = patchPayload(body.slice(payloadOffset, payloadOffset + length), config);
  if (equal(patched.data, body.slice(payloadOffset, payloadOffset + length))) throw new Error("unchanged ARPC");
  return { data: concat(body.slice(0, lengthOffset), writeUint32(patched.data.length),
    patched.data, body.slice(payloadOffset + length)), stats: patched.stats };
}

function patchMarker(body, config) {
  const markerOffset = findBytes(body, WLOC_MARKER);
  if (markerOffset < 0) throw new Error("marker not found");
  const lengthOffset = markerOffset + WLOC_MARKER.length;
  const payloadOffset = lengthOffset + 2;
  const length = uint16(body, lengthOffset);
  if (!length || payloadOffset + length > body.length) throw new Error("invalid marker length");
  const patched = patchPayload(body.slice(payloadOffset, payloadOffset + length), config);
  if (patched.data.length > 65535 || equal(patched.data, body.slice(payloadOffset, payloadOffset + length))) {
    throw new Error("unchanged marker");
  }
  return { data: concat(body.slice(0, lengthOffset), writeUint16(patched.data.length),
    patched.data, body.slice(payloadOffset + length)), stats: patched.stats };
}

function patchSynthetic(body, offset, config) {
  if (offset + 10 > body.length) throw new Error("short frame");
  const length = uint16(body, offset + 8);
  if (!length || offset + 10 + length > body.length) throw new Error("invalid frame");
  const patched = patchPayload(body.slice(offset + 10, offset + 10 + length), config);
  if (patched.data.length > 65535 || equal(patched.data, body.slice(offset + 10, offset + 10 + length))) {
    throw new Error("unchanged frame");
  }
  return { data: concat(body.slice(0, offset + 8), writeUint16(patched.data.length),
    patched.data, body.slice(offset + 10 + length)), stats: patched.stats };
}

export function patchWlocBody(body, config) {
  for (const patcher of [patchARPC, patchMarker]) {
    try { return patcher(body, config); } catch {}
  }
  const offsets = [...new Set([0, 2, 4, 6, 8, 10, 12, 14, 16,
    ...Array.from({ length: Math.min(96, Math.max(0, body.length - 10)) + 1 }, (_, index) => index)])];
  for (const offset of offsets) {
    try { return patchSynthetic(body, offset, config); } catch {}
  }
  for (let offset = 0; offset <= Math.min(256, body.length); offset += 1) {
    try {
      const patched = patchPayload(body.slice(offset), config);
      if (!equal(patched.data, body.slice(offset))) {
        return { data: concat(body.slice(0, offset), patched.data), stats: patched.stats };
      }
    } catch {}
  }
  throw new Error("no patchable wloc payload found");
}

export const internals = { concat, writeVarint, writeTag, writeLengthDelimited, equal };
