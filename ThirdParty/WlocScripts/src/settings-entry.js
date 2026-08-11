import {
  CAPABILITIES, MODULE_VERSION, PROTOCOL_VERSION, STORAGE_KEY,
  finishJSON, queryParameters, readPersistent, requestPath, writePersistent
} from "./runtime.js";

const url = typeof $request === "undefined" ? "" : ($request.url || "");
const path = requestPath(url);
const parameters = queryParameters(url);

if (path === "/wloc-settings/version") {
  finishJSON({
    success: true,
    moduleVersion: MODULE_VERSION,
    protocolVersion: PROTOCOL_VERSION,
    capabilities: CAPABILITIES
  });
} else if (parameters.action === "query") {
  const settings = readPersistent(STORAGE_KEY);
  finishJSON(settings && settings.enabled
    ? { success: true, longitude: settings.longitude, latitude: settings.latitude,
        accuracy: settings.accuracy, motionSimulationEnabled: settings.motionSimulationEnabled === true }
    : { success: false, error: "无已保存的坐标" });
} else if (parameters.action === "clear") {
  writePersistent(STORAGE_KEY, null);
  finishJSON({ success: true });
} else {
  const longitude = Number(parameters.lon != null ? parameters.lon : parameters.longitude);
  const latitude = Number(parameters.lat != null ? parameters.lat : parameters.latitude);
  const accuracy = Number(parameters.acc != null
    ? parameters.acc
    : (parameters.accuracy != null ? parameters.accuracy : 25));
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) {
    finishJSON({ success: false, error: "缺少 lon/lat 参数" });
  } else {
    const settings = {
      enabled: true,
      longitude,
      latitude,
      accuracy,
      motionSimulationEnabled: parameters.motion === "1"
    };
    const success = writePersistent(STORAGE_KEY, settings);
    finishJSON(success
      ? { success: true, longitude, latitude, accuracy,
          motionSimulationEnabled: settings.motionSimulationEnabled }
      : { success: false, error: "保存配置失败" });
  }
}
