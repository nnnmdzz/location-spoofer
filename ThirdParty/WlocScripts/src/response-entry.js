import { ungzip } from "pako";
import { patchWlocBody } from "./core.js";
import {
  STORAGE_KEY, finishBinary, finishPassthrough, readPersistent, responseBytes
} from "./runtime.js";

try {
  const settings = readPersistent(STORAGE_KEY);
  const input = responseBytes();
  if (!settings || !settings.enabled || !input.length) {
    finishPassthrough();
  } else {
    const isGzip = input.length >= 2 && input[0] === 0x1f && input[1] === 0x8b;
    const body = isGzip ? ungzip(input) : input;
    const patched = patchWlocBody(body, {
      latitude: Number(settings.latitude),
      longitude: Number(settings.longitude),
      accuracy: Number(settings.accuracy != null ? settings.accuracy : 25),
      motionSimulationEnabled: settings.motionSimulationEnabled === true
    });
    finishBinary(patched.data);
  }
} catch (error) {
  console.log(`[Location Spoofer] ${error && error.message ? error.message : error}`);
  finishPassthrough();
}
