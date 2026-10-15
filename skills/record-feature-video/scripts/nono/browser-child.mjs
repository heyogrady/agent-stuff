#!/usr/bin/env node
/*
 * browser-child.mjs: started by launcher.mjs inside the browser's own nono
 * sandbox (nono-browser.json). Launches headless Chromium with a remote
 * debugging port at a fixed window size and scale, prints READY, and stays up
 * until the launcher stops it.
 *
 *   node browser-child.mjs --port P --width W --height H --dsf N [--gl]
 */
import path from "node:path";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const num = (f) => Number(argv[argv.indexOf(f) + 1]);
const [port, width, height, dsf] = ["--port", "--width", "--height", "--dsf"].map(num);
const pwDir = readFileSync(path.join(HERE, "playwright-dir"), "utf8").trim();
const { chromium } = createRequire(path.join(pwDir, "package.json"))("playwright");

const browser = await chromium.launch({
  headless: true,
  // The window and scale fix the screencast's frame size, which a client
  // cannot change after launch; record.mjs checks them against its shot list.
  args: [`--remote-debugging-port=${port}`, `--force-device-scale-factor=${dsf}`, `--window-size=${width},${height}`,
    ...(argv.includes("--gl") ? (process.env.FEATURE_RECORDER_GL ?? "").split(" ").filter(Boolean) : [])],
});
await (await browser.newPage()).goto("about:blank");
console.log(`READY ${port}`);
const stop = async () => { await browser.close().catch(() => {}); process.exit(0); };
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
browser.on("disconnected", () => process.exit(0));
