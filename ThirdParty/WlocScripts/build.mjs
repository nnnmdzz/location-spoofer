import { build } from "esbuild";
import { mkdir } from "node:fs/promises";

await mkdir(new URL("./dist/v1/", import.meta.url), { recursive: true });

for (const [entry, outfile] of [
  ["src/response-entry.js", "dist/v1/wloc.js"],
  ["src/settings-entry.js", "dist/v1/wloc-settings.js"]
]) {
  await build({
    entryPoints: [entry],
    outfile,
    bundle: true,
    format: "iife",
    target: ["es2017"],
    minify: true,
    legalComments: "eof"
  });
}
