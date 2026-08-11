import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const bundles = [
  new URL("../dist/v1/wloc.js", import.meta.url),
  new URL("../dist/v1/wloc-settings.js", import.meta.url)
];

test("generated bundles avoid newer JavaScriptCore runtime requirements", async () => {
  for (const bundle of bundles) {
    const source = await readFile(bundle, "utf8");
    for (const unsupported of [
      /\bBigInt\b/,
      /\bglobalThis\b/,
      /\bURLSearchParams\b/,
      /\bObject\.fromEntries\b/,
      /\?\./,
      /\?\?/
    ]) {
      assert.equal(unsupported.test(source), false, `${bundle.pathname} contains ${unsupported}`);
    }
  }
});

test("settings bundle runs without modern URL and text globals", async () => {
  const source = await readFile(bundles[1], "utf8");
  let result;
  const storage = new Map();
  vm.runInNewContext(source, {
    $rocket: {},
    $request: {
      url: "https://gs-loc.apple.com/wloc-settings/save?lon=121.1&lat=31.2&acc=25"
    },
    $persistentStore: {
      read: (key) => storage.get(key) || null,
      write: (value, key) => {
        storage.set(key, value);
        return true;
      }
    },
    $done: (value) => { result = value; },
    JSON,
    Number,
    Object,
    String,
    decodeURIComponent
  });

  assert.equal(JSON.parse(result.response.body).success, true);
});
