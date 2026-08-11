export const MODULE_VERSION = "1.0.0";
export const PROTOCOL_VERSION = 1;
export const CAPABILITIES = [
  "wifi", "cellTower", "arpc", "marker", "synthetic", "bare", "motionSimulation"
];
export const STORAGE_KEY = "locationSpoofer.settings.v1";

export function environment() {
  if (typeof $task !== "undefined") return "quantumultX";
  if (typeof $loon !== "undefined") return "loon";
  if (typeof $rocket !== "undefined") return "shadowrocket";
  if (typeof Egern !== "undefined") return "egern";
  if (typeof $environment !== "undefined" && $environment["stash-version"]) return "stash";
  if (typeof $environment !== "undefined" && $environment["surge-version"]) return "surge";
  return "unknown";
}

export function readPersistent(key) {
  const raw = environment() === "quantumultX"
    ? $prefs.valueForKey(key)
    : $persistentStore.read(key);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

export function writePersistent(key, value) {
  const raw = value == null ? "" : JSON.stringify(value);
  return environment() === "quantumultX"
    ? $prefs.setValueForKey(raw, key)
    : $persistentStore.write(raw, key);
}

export function responseBytes() {
  const response = typeof $response === "undefined" ? null : $response;
  const value = response && response.bodyBytes != null ? response.bodyBytes : response && response.body;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  if (typeof value === "string") {
    return Uint8Array.from(value, (character) => character.charCodeAt(0) & 0xff);
  }
  return new Uint8Array();
}

function cleanHeaders(headers, length) {
  const out = Object.assign({}, headers || {});
  for (const name of ["Content-Encoding", "content-encoding", "Transfer-Encoding", "transfer-encoding"]) {
    delete out[name];
  }
  out["Content-Length"] = String(length);
  return out;
}

export function finishBinary(bytes) {
  const response = typeof $response === "undefined" ? {} : $response;
  const headers = cleanHeaders(response.headers, bytes.length);
  const env = environment();
  if (env === "quantumultX") {
    delete headers["Content-Length"];
    $done({ status: "HTTP/1.1 200 OK", headers, bodyBytes: bytes.buffer });
  } else if (env === "stash") {
    $done(Object.assign({}, response, { status: 200, headers, body: bytes }));
  } else {
    $done({ response: Object.assign({}, response, { status: 200, headers, body: bytes }) });
  }
}

export function finishPassthrough() {
  $done({});
}

export function finishJSON(value) {
  const response = {
    status: 200,
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(value)
  };
  if (environment() === "quantumultX") {
    $done(Object.assign({}, response, { status: "HTTP/1.1 200 OK" }));
  } else if (environment() === "stash") {
    $done(response);
  } else {
    $done({ response });
  }
}

export function queryParameters(url) {
  const query = url.split("?")[1] || "";
  const values = {};
  query.split("&").forEach((item) => {
    if (!item) return;
    const separator = item.indexOf("=");
    const rawKey = separator < 0 ? item : item.slice(0, separator);
    const rawValue = separator < 0 ? "" : item.slice(separator + 1);
    let key = rawKey;
    let value = rawValue;
    try { key = decodeURIComponent(rawKey.replace(/\+/g, " ")); } catch {}
    try { value = decodeURIComponent(rawValue.replace(/\+/g, " ")); } catch {}
    if (!Object.prototype.hasOwnProperty.call(values, key)) values[key] = value;
  });
  return values;
}

export function requestPath(url) {
  const withoutQuery = url.split("?")[0];
  const scheme = withoutQuery.indexOf("://");
  if (scheme < 0) return withoutQuery;
  const path = withoutQuery.indexOf("/", scheme + 3);
  return path < 0 ? "/" : withoutQuery.slice(path);
}
