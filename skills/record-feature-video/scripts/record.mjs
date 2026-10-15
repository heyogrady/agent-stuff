#!/usr/bin/env node
/**
 * Feature recorder — a browser walkthrough driven by a visible, human-paced
 * cursor, captured at device-pixel resolution, finished as a GIF or an MP4.
 *
 *   node record.mjs --actions shots.json [--rehearse] [--until N] [--shots]
 *                   [--keep-frames] [--max-seconds N] [--repo DIR] [--out DIR] [--cdp P]
 *
 * --rehearse  every step at speed with short timeouts and no capture; a miss
 *             is diagnosed (no match / hidden / covered / disabled, with
 *             candidate selectors) and the run continues, so one rehearsal
 *             lists every bad step. Steps still act on the app.
 * --until N   (with --rehearse) stop after step N and screenshot it — tune
 *             framing, zoom, and labels without a take (a spotlight step is
 *             shot with its label up).
 * --shots     (with --rehearse) screenshot after every step.
 *
 * The last stdout line is always `RESULT {json}`, also saved as
 * <name>.result.json (a rehearsal: <name>.rehearse.json, its screenshots under
 * <out>/rehearse/, so nothing it writes is mistaken for the take's).
 * references/shot-list.md is the contract.
 */
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lint } from "./lib/lint.mjs";
import {
  CURSOR, CHANGE_TRACKER, spotlightOn, spotlightOff, cutCover, hitTest, busyAt, dragEvent, pasteInto, scrollPlan,
} from "./lib/page-scripts.mjs";
import {
  loadPlaywright, repoRoot, checkServer, startDevServer, stopDevServer, proxyOption, inNono, launcherInfo, launcherOpen, launcherClose, nonoHint,
} from "./lib/env.mjs";
import { chooseCrop, assemble, regionChanged, psnrSaysChanged } from "./lib/finish.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));

/* ------------------------------------------------------------- arguments -- */

const argv = process.argv.slice(2);
const opt = (f) => (argv.includes(f) ? argv[argv.indexOf(f) + 1] : undefined);
const actionsPath = opt("--actions") ?? argv.find((a) => a.endsWith(".json"));
if (!actionsPath) {
  console.error("usage: record.mjs --actions <shots.json> [--rehearse [--until N] [--shots]] [--keep-frames] [--max-seconds N] [--repo DIR] [--out DIR] [--cdp P]");
  process.exit(1);
}
const REHEARSE = argv.includes("--rehearse") || argv.includes("--until");
const UNTIL = opt("--until") ? Number(opt("--until")) : null;
const SHOTS = argv.includes("--shots");
const KEEP_FRAMES = argv.includes("--keep-frames");
const cfg = JSON.parse(readFileSync(actionsPath, "utf8"));
// File paths in the shot list resolve against the shot list's own folder.
const cfgDir = path.dirname(path.resolve(actionsPath));
const rel = (p) => (p == null ? p : Array.isArray(p) ? p.map(rel) : path.resolve(cfgDir, p));
for (const k of ["filePicker", "cookiesFile", "storageState"]) if (cfg[k]) cfg[k] = rel(cfg[k]);
for (const a of cfg.actions ?? []) {
  if (a.file) a.file = rel(a.file);
  if (a.files) a.files = rel(a.files);
}
const viewport = cfg.viewport ?? { width: 1440, height: 900 };
const dsf = cfg.deviceScaleFactor ?? 2;
const outDir = path.resolve(opt("--out") ?? cfg.output?.dir ?? path.join(cfgDir, "out"));
const outName = cfg.output?.name ?? "feature-demo";
const framesDir = path.join(outDir, `_frames-${outName}`);
const shotDir = path.join(outDir, "rehearse");
mkdirSync(outDir, { recursive: true });

const PACE = REHEARSE ? 0.12 : 1;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms * PACE));
const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Width and height from a base64 JPEG's SOF marker.
function jpegSize(b64) {
  if (!b64) return [0, 0];
  const b = Buffer.from(b64, "base64");
  for (let i = 2; i + 9 < b.length;) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xc3) return [b.readUInt16BE(i + 7), b.readUInt16BE(i + 5)];
    i += 2 + b.readUInt16BE(i + 2);
  }
  return [0, 0];
}
const now = () => Date.now() / 1000;
const warnings = [];
// Rehearsal fails fast; an explicit per-step `timeout` (a known-slow backend
// wait) is honored in both modes.
const T = (a, take) => a.timeout ?? (REHEARSE ? cfg.rehearseTimeout ?? 4000 : take);

/* --------------------------------------------------------------- finish -- */

const state = { browser: null, context: null, external: false, launcher: null, dev: null, finished: false, step: 0, watchdog: null };

async function finish(result, code) {
  if (state.finished) return;
  state.finished = true;
  clearTimeout(state.watchdog);
  // A browser this run did not launch outlives it: close only this run's
  // context, and hand a launcher's browser back.
  try { await Promise.race([state.external ? state.context?.close() : state.browser?.close(), realSleep(4000)]); } catch {}
  if (state.launcher) await launcherClose(state.launcher);
  stopDevServer(state.dev);
  if (!KEEP_FRAMES) rmSync(framesDir, { recursive: true, force: true });
  const full = { ...result, warnings: [...warnings, ...(result.warnings ?? [])] };
  try { writeFileSync(path.join(outDir, `${outName}.${REHEARSE ? "rehearse" : "result"}.json`), JSON.stringify(full, null, 2)); } catch {}
  console.log("RESULT " + JSON.stringify(full));
  process.exit(code);
}
const fail = (stage, error, code = 2, extra = {}) => finish({ ok: false, stage, error, step: state.step || null, ...extra }, code);
process.on("SIGINT", () => fail("interrupted", "interrupted", 130));
process.on("SIGTERM", () => fail("interrupted", "terminated", 143));
process.on("unhandledRejection", (e) => fail("internal", String(e?.message ?? e)));
process.on("uncaughtException", (e) => fail("internal", String(e?.message ?? e)));

/* ------------------------------------------------------------- preflight -- */

const checked = lint(cfg);
for (const w of checked.warnings) warnings.push(w);
if (checked.errors.length) {
  console.error("✖ shot list rejected:\n  - " + checked.errors.join("\n  - "));
  await fail("lint", "shot list rejected", 3, { errors: checked.errors });
}
const takeStart = checked.takeStart;
// The worktree whose dev server the take must film: --repo, `repo`, the shot
// list's own repo, else the cwd's (shot lists usually live under /tmp).
const repo = opt("--repo") ? path.resolve(opt("--repo")) : cfg.repo ? path.resolve(cfg.repo) : repoRoot(cfgDir) ?? repoRoot(process.cwd());

const maxSeconds = Number(opt("--max-seconds") ?? cfg.maxSeconds ?? 300);
state.watchdog = setTimeout(() => fail("watchdog", `exceeded ${maxSeconds}s (at step ${state.step}); raise maxSeconds only if the app is genuinely that slow`), maxSeconds * 1000);

try {
  state.dev = await startDevServer(cfg, repo, (m) => console.log(`  ${m}`));
} catch (err) {
  await fail("server", err.message, 4);
}
const server = checkServer(cfg, repo);
if (!server.ok) {
  console.error(`✖ ${server.error}`);
  await fail("server", server.error, 4);
}
if (server.warning) warnings.push(server.warning);

/* ---------------------------------------------------------------- launch -- */

let chromium;
try { ({ chromium } = loadPlaywright(path.join(HERE, "setup.sh"))); } catch (err) { console.error(`✖ ${err.message}`); await fail("setup", err.message, 1); }
// --cdp (a port or URL), FEATURE_VIDEO_CDP, or `cdp` in the shot list names a
// running browser. Inside nono Chromium cannot start, so the session's
// launcher (nono-setup.sh) starts one at this shot list's size.
const cdpOf = (v) => (v == null || v === "" ? null : /^\d+$/.test(String(v)) ? `http://127.0.0.1:${v}` : String(v));
let cdpUrl = cdpOf(opt("--cdp") ?? process.env.FEATURE_VIDEO_CDP ?? cfg.cdp);
if (!cdpUrl && inNono()) {
  const launcher = launcherInfo(repo);
  if (!launcher) {
    const msg = nonoHint(HERE, repo);
    console.error(`✖ ${msg}`);
    await fail("launch", msg, 2);
  }
  // The launcher takes no Chromium flags, only whether to render WebGL in
  // software (the SwiftShader flags maps need headless).
  const soft = /^--(enable-unsafe-swiftshader|use-angle=swiftshader|use-gl=swiftshader|ignore-gpu-blocklist)$/;
  const args = cfg.launchArgs ?? [];
  if (args.some((a) => !soft.test(a))) warnings.push(`the nono browser takes no launchArgs but SwiftShader's; ignored ${args.filter((a) => !soft.test(a)).join(" ")}`);
  try {
    cdpUrl = await launcherOpen(launcher, { width: viewport.width, height: viewport.height, dsf, gl: args.some((a) => soft.test(a)) });
    state.launcher = launcher;
  } catch (err) {
    console.error(`✖ the browser launcher could not start a browser: ${err.message}`);
    await fail("launch", `the browser launcher could not start a browser: ${err.message}`, 2);
  }
} else if (cdpUrl && cfg.launchArgs?.length) {
  warnings.push(`launchArgs do not reach a running browser (${cfg.launchArgs.join(" ")})`);
}
if (cdpUrl) {
  try {
    state.browser = await chromium.connectOverCDP(cdpUrl, { timeout: 5000 });
    state.external = true;
  } catch (err) {
    console.error(`✖ no browser answers at ${cdpUrl}: ${err.message.split("\n")[0]}`);
    await fail("launch", `no browser answers at ${cdpUrl}: ${err.message.split("\n")[0]}`, 2);
  }
} else {
  try {
    state.browser = await chromium.launch({
      headless: cfg.headless !== false,
      // The screencast delivers device-pixel frames only when the browser
      // itself renders at that scale; deviceScaleFactor alone yields 1x.
      args: [`--force-device-scale-factor=${dsf}`, ...(cfg.launchArgs ?? [])],
      proxy: proxyOption(cfg),
    });
  } catch (err) {
    const msg = err.message.split("\n")[0];
    console.error(`✖ browser launch failed: ${msg}`);
    await fail("launch", msg, 2);
  }
}
const context = await state.browser.newContext({
  viewport,
  deviceScaleFactor: dsf,
  ...(cfg.storageState ? { storageState: cfg.storageState } : {}),
  ...(cfg.timezoneId ? { timezoneId: cfg.timezoneId } : {}),
  ...(cfg.locale ? { locale: cfg.locale } : {}),
});
const cookies = [...(cfg.cookies ?? []), ...(cfg.cookiesFile ? JSON.parse(readFileSync(cfg.cookiesFile, "utf8")) : [])];
if (cookies.length) await context.addCookies(cookies);
state.context = context;
const page = await context.newPage();
if (state.external) {
  // An external browser's frame size was fixed when it launched;
  // a mismatch would record a cut-off or blurred take, so refuse it up front.
  const probe = await context.newCDPSession(page);
  const frame = await new Promise((resolve) => {
    probe.on("Page.screencastFrame", (f) => { probe.send("Page.screencastFrameAck", { sessionId: f.sessionId }).catch(() => {}); resolve(f); });
    probe.send("Page.startScreencast", { format: "jpeg", quality: 10 }).catch(() => resolve(null));
    page.setContent("<body style='background:#fff'></body>").then(() => page.evaluate(() => { document.body.style.background = "#fefefe"; })).catch(() => {});
    setTimeout(() => resolve(null), 3000);
  });
  await probe.send("Page.stopScreencast").catch(() => {});
  await probe.detach().catch(() => {});
  const [fw, fh] = jpegSize(frame?.data);
  const [ww, wh] = [Math.round(viewport.width * dsf), Math.round(viewport.height * dsf)];
  if (fw && (Math.abs(fw - ww) > 2 || Math.abs(fh - wh) > 2)) {
    const port = new URL(cdpUrl).port;
    await fail("launch", `the browser at ${cdpUrl} renders ${fw}x${fh}, but this shot list needs ${ww}x${wh} (viewport ${viewport.width}x${viewport.height} at ${dsf}x). Restart it with --window-size=${viewport.width},${viewport.height} --force-device-scale-factor=${dsf} (port ${port}).`, 2);
  }
}
if (cfg.filePicker) page.on("filechooser", (fc) => fc.setFiles(cfg.filePicker).catch(() => {}));
const base = cfg.baseUrl;

/* --------------------------------------------------------------- capture -- */

const capture = { on: false, t0: 0, frames: [], writes: [], cdp: null, n: 0 };
const timeline = []; // { t (node s), type, rect?, ms? }
const zooms = [];
let navigated = false;

page.on("framenavigated", (f) => {
  // Any route change — the page or an app iframe, hash routes included —
  // means the take is not one region, so auto-crop stands down.
  if (capture.on && (f === page.mainFrame() || f.parentFrame() === page.mainFrame())) navigated = true;
});

async function startCapture() {
  if (REHEARSE || capture.on) return;
  rmSync(framesDir, { recursive: true, force: true });
  mkdirSync(framesDir, { recursive: true });
  capture.cdp = await context.newCDPSession(page);
  capture.cdp.on("Page.screencastFrame", (f) => {
    // Ack first: a late ack throttles the screencast.
    capture.cdp.send("Page.screencastFrameAck", { sessionId: f.sessionId }).catch(() => {});
    if (!capture.on) return;
    const file = path.join(framesDir, `${String(capture.n++).padStart(6, "0")}.jpg`);
    capture.frames.push({ file, ts: f.metadata?.timestamp ?? null, arrived: now() });
    capture.writes.push(writeFile(file, Buffer.from(f.data, "base64")));
  });
  await injectAll(CHANGE_TRACKER);
  capture.t0 = now();
  capture.on = true;
  await capture.cdp.send("Page.startScreencast", {
    format: "jpeg", quality: 88,
    maxWidth: Math.round(viewport.width * dsf), maxHeight: Math.round(viewport.height * dsf),
  });
}

async function stopCapture(end) {
  if (!capture.on) return null;
  const t1 = end ?? now();
  capture.on = false;
  await capture.cdp.send("Page.stopScreencast").catch(() => {});
  await Promise.all(capture.writes);
  // Frame timestamps are the browser's clock; actions are Node's. The
  // smallest arrival-minus-timestamp is the clock offset (latency ~0).
  const deltas = capture.frames.filter((f) => f.ts != null).map((f) => f.arrived - f.ts);
  const offset = deltas.length ? Math.min(...deltas) : 0;
  for (const f of capture.frames) f.t = Math.max(capture.t0, f.ts != null ? f.ts + offset : f.arrived);
  return t1;
}

/* ---------------------------------------------------------------- frames -- */

async function frameFor(a) {
  if (!a.frame || a.frame === "page") return page;
  const sel = cfg.frames[a.frame];
  const handle = await page.waitForSelector(sel, { state: "attached", timeout: T(a, 30000) });
  const frame = await handle.contentFrame();
  if (!frame) throw new Error(`frames.${a.frame} (${sel}) is not an iframe`);
  return frame;
}

// Page-coordinate offset of a frame's content box (borders included).
async function frameOffset(frame) {
  let x = 0, y = 0;
  if (frame === page) return { x, y }; // frameFor() hands back the Page itself
  for (let f = frame; f && f.parentFrame(); f = f.parentFrame()) {
    const el = await f.frameElement();
    const o = await el.evaluate((e) => { const r = e.getBoundingClientRect(); return { x: r.left + e.clientLeft, y: r.top + e.clientTop }; });
    x += o.x; y += o.y;
  }
  return { x, y };
}

async function injectAll(script) {
  for (const f of page.frames()) await f.evaluate(script).catch(() => {});
}

async function changedRegion() {
  const boxes = [];
  for (const f of page.frames()) {
    const u = await f.evaluate(() => window.__fr_changes).catch(() => null);
    if (!u?.n) continue;
    const o = await frameOffset(f).catch(() => null);
    if (o) boxes.push({ x1: u.x1 + o.x, y1: u.y1 + o.y, x2: u.x2 + o.x, y2: u.y2 + o.y });
  }
  return boxes;
}

async function canvasRects() {
  const rects = [];
  for (const f of page.frames()) {
    const rs = await f.evaluate(() => [...document.querySelectorAll("canvas")].map((c) => c.getBoundingClientRect())
      .filter((r) => r.width > 100 && r.height > 100).map((r) => ({ x: r.left, y: r.top, width: r.width, height: r.height }))).catch(() => []);
    if (!rs.length) continue;
    const o = await frameOffset(f).catch(() => ({ x: 0, y: 0 }));
    for (const r of rs) rects.push({ x: r.x + o.x, y: r.y + o.y, width: r.width, height: r.height });
  }
  return rects;
}

/* ---------------------------------------------------------------- cursor -- */

let cursor = { x: viewport.width * 0.5, y: viewport.height * 0.8 };
let badge = "";
async function injectCursor() {
  await page.evaluate(([s, x, y, b]) => { window.__fr_x = x; window.__fr_y = y; window.__fr_badgeText = b; window.eval(s); }, [CURSOR, cursor.x, cursor.y, badge]).catch(() => {});
}
page.on("load", () => { injectCursor(); });

async function moveCursorTo(x, y, ms = 900, during) {
  const from = { ...cursor };
  // Control points either side of the straight line: a shallow arc, the way
  // a hand travels, eased in and out.
  const dx = x - from.x, dy = y - from.y;
  const dist = Math.hypot(dx, dy);
  const bow = Math.min(140, dist * 0.22) * (Math.random() < 0.5 ? -1 : 1);
  const nx = -dy / (dist || 1), ny = dx / (dist || 1);
  const c1 = { x: from.x + dx * 0.3 + nx * bow, y: from.y + dy * 0.3 + ny * bow };
  const c2 = { x: from.x + dx * 0.7 + nx * bow * 0.6, y: from.y + dy * 0.7 + ny * bow * 0.6 };
  // Driven by the clock, not a step count: each step costs browser round
  // trips, so fixed sleeps would make a 900ms move take twice that.
  const dur = ms * PACE, start = Date.now();
  for (let raw = 0; raw < 1;) {
    // Only a zero-length move jumps; a 0 ms first sample is the start.
    raw = dur > 0 ? Math.min(1, (Date.now() - start) / dur) : 1;
    const t = raw < 0.5 ? 2 * raw * raw : 1 - Math.pow(-2 * raw + 2, 2) / 2;
    const u = 1 - t;
    const px = u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * x;
    const py = u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * y;
    await page.evaluate(([ax, ay]) => window.__fr_move && window.__fr_move(ax, ay), [px, py]).catch(() => {});
    await page.mouse.move(px, py).catch(() => {});
    if (during) await during(raw, px, py);
    if (raw < 1) await realSleep(6);
  }
  cursor = { x, y };
}
const ripple = (x, y) => page.evaluate(([ax, ay]) => window.__fr_click && window.__fr_click(ax, ay), [x, y]).catch(() => {});
// Glide the cursor just outside a box it is resting on, so it never hides
// the result it just produced: the nearest spot over empty page, since a
// cursor resting on a label reads as pointing at it. Skipped when there is no
// room around the box.
async function parkOutside(b, ms = 600) {
  if (cursor.x < b.x1 - 4 || cursor.x > b.x2 + 4 || cursor.y < b.y1 - 4 || cursor.y > b.y2 + 4) return;
  const spots = [];
  for (const m of [36, 72]) for (const s of [0, -90, 90]) {
    spots.push([cursor.x + s, b.y2 + m], [cursor.x + s, b.y1 - m], [b.x2 + m, cursor.y + s], [b.x1 - m, cursor.y + s]);
  }
  const ok = spots.filter(([x, y]) => x > 8 && y > 8 && x < viewport.width - 8 && y < viewport.height - 8);
  if (!ok.length) return;
  const busy = await page.evaluate(busyAt, ok).catch(() => ok.map(() => 0));
  const cost = (i) => busy[i] * 1e6 + Math.hypot(ok[i][0] - cursor.x, ok[i][1] - cursor.y);
  const best = ok.map((_, i) => i).sort((i, j) => cost(i) - cost(j))[0];
  await moveCursorTo(ok[best][0], ok[best][1], ms);
}
const setBadge = async (text) => { badge = text; await page.evaluate((b) => { window.__fr_badgeText = b; window.__fr_badge && window.__fr_badge(b); }, text).catch(() => {}); };

/* --------------------------------------------------------------- locating -- */

async function locate(a, selector = a.selector) {
  const root = await frameFor(a);
  let loc = root.locator(selector);
  if (a.hasText && selector === a.selector) loc = loc.filter({ hasText: a.hasText });
  return loc.nth(a.nth ?? 0);
}

const record = (type, box, extra = {}) => {
  if (!capture.on) return null;
  const e = { t: now(), type, rect: box ? { ...box } : null, ...extra };
  timeline.push(e);
  return e;
};

// Poll the box until it stops moving: a box measured mid-scroll or mid-
// animation puts the cursor where the element was, not where it is.
async function stableBox(loc) {
  let prev = await loc.boundingBox();
  const deadline = Date.now() + (REHEARSE ? 600 : 2500);
  while (Date.now() < deadline) {
    await realSleep(80);
    const cur = await loc.boundingBox();
    if (prev && cur && Math.abs(cur.x - prev.x) < 0.5 && Math.abs(cur.y - prev.y) < 0.5 && Math.abs(cur.width - prev.width) < 0.5 && Math.abs(cur.height - prev.height) < 0.5) return cur;
    prev = cur;
  }
  return prev;
}

async function rectOf(a, { selector = a.selector, scroll = true } = {}) {
  const loc = await locate(a, selector);
  await loc.waitFor({ state: "visible", timeout: T(a, 30000) });
  if (scroll && a.scrollIntoView !== false) {
    // Scroll only when the target is not comfortably on screen, on either
    // axis — an unneeded scroll costs a second and reads as a twitch.
    const moved = await loc.evaluate((el) => {
      const r = el.getBoundingClientRect();
      const m = 60;
      if (r.top >= m && r.bottom <= innerHeight - m && r.left >= 0 && r.right <= innerWidth) return false;
      el.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
      return true;
    });
    let movedTop = false;
    const box = await stableBox(loc);
    // Inside an iframe, the element can sit in the frame's viewport while the
    // frame itself runs off the page; scroll the page too.
    if (box && (box.y < 0 || box.y + box.height > viewport.height || box.x < 0 || box.x + box.width > viewport.width)) {
      movedTop = await page.evaluate(([y, h]) => { const d = y + h / 2 - innerHeight / 2; if (Math.abs(d) < 1) return false; window.scrollBy({ top: d, behavior: "smooth" }); return true; }, [box.y, box.height]);
    }
    if (moved || movedTop) {
      record("scroll", null);
      await sleep(a.scrollMs ?? 250);
    }
  }
  const box = await stableBox(loc);
  if (!box) throw new Error(`no box for ${selector}`);
  return { loc, box };
}

function pointIn(b, a) {
  const x = a.xFrac != null ? b.x + b.width * a.xFrac : a.offsetX != null ? b.x + a.offsetX : b.x + b.width / 2;
  const y = a.yFrac != null ? b.y + b.height * a.yFrac : a.offsetY != null ? b.y + a.offsetY : b.y + b.height / 2;
  return [x, y];
}

// The cursor animating onto a control hidden behind a sticky header looks
// fine and clicks the header. Prove the point reaches the target. `soft`
// (hover, move, spotlight in a take) warns instead of failing.
async function reachable(loc, box, x, y, a, { soft = false } = {}) {
  if (a.force) return;
  const why = await unreachable(loc, box, x, y, a);
  if (!why) return;
  const msg = `${a.selector} is not reachable at the cursor point — ${why}`;
  if (soft && !REHEARSE) warnings.push(`step ${state.step}: ${msg}`);
  else throw new Error(msg);
}

// Why the point does not reach the element, or null.
async function unreachable(loc, box, x, y, a) {
  let why = null;
  if (x < 0 || y < 0 || x > viewport.width || y > viewport.height) why = "the point is outside the viewport";
  if (!why) {
    const r = await loc.evaluate(hitTest, [(x - box.x) / (box.width || 1), (y - box.y) / (box.height || 1)]);
    if (!r.ok) why = r.why;
  }
  if (!why && a.frame && a.frame !== "page") {
    const r = await page.locator(cfg.frames[a.frame]).first().evaluate((frameEl, [px, py]) => {
      const hit = document.elementFromPoint(px, py);
      if (!hit || hit === frameEl || frameEl.contains(hit)) return { ok: true };
      return { ok: false, why: `covered by <${hit.tagName.toLowerCase()}${hit.id ? "#" + hit.id : ""}> in the top page` };
    }, [x, y]);
    if (!r.ok) why = r.why;
  }
  return why;
}

/* ------------------------------------------------------------- spotlight -- */

const union = (bs) => {
  const x1 = Math.min(...bs.map((b) => b.x)), y1 = Math.min(...bs.map((b) => b.y));
  const x2 = Math.max(...bs.map((b) => b.x + b.width)), y2 = Math.max(...bs.map((b) => b.y + b.height));
  return { x: x1, y: y1, width: x2 - x1, height: y2 - y1 };
};

// One target, or a list whose union box is spotlit (two rows that are not
// adjacent). A list is scrolled so the union, not just its first target, is
// centred when it fits.
async function spotTargets(a) {
  if (!Array.isArray(a.selector)) {
    const { loc, box } = await rectOf(a);
    return { box, parts: [{ loc, box, selector: a.selector }] };
  }
  const each = { ...a, hasText: undefined, nth: undefined };
  const parts = [];
  for (const [i, sel] of a.selector.entries()) parts.push({ ...(await rectOf(each, { selector: sel, scroll: i === 0 })), selector: sel });
  let box = union(parts.map((p) => p.box));
  if ((box.y < 0 || box.y + box.height > viewport.height) && box.height < viewport.height - 40) {
    const d = box.y + box.height / 2 - viewport.height / 2;
    await parts[0].loc.evaluate((el, dy) => {
      let n = el.parentElement;
      for (; n; n = n.parentElement) {
        const st = getComputedStyle(n);
        if (/(auto|scroll|overlay)/.test(st.overflowY) && n.scrollHeight > n.clientHeight + 1) break;
      }
      (n ?? document.scrollingElement).scrollBy({ top: dy, behavior: "smooth" });
    }, d);
    record("scroll", null);
    await sleep(a.scrollMs ?? 250);
    for (const p of parts) p.box = await stableBox(p.loc);
    box = union(parts.map((p) => p.box));
  }
  return { box, parts };
}

// Framing that makes the label land on content or the page scroll mid-beat:
// a target taller than the viewport, or one whose top edge is hidden (under a
// sticky header, or off screen). Warned in rehearsal and in the take.
async function spotlightFit(box, parts, pad, a) {
  const say = (m) => warnings.push(`step ${state.step}: spotlight ${m}`);
  if (box.height + 2 * pad > viewport.height) {
    say(`target is ${Math.round(box.height)}px tall, taller than the ${viewport.height}px viewport: part of it is off screen and the label lands on content; spotlight a smaller element`);
    return;
  }
  const top = parts.reduce((p, q) => (q.box.y < p.box.y ? q : p));
  const y = top.box.y + Math.min(4, top.box.height / 2);
  const why = await unreachable(top.loc, top.box, top.box.x + top.box.width / 2, y, a).catch(() => null);
  if (why) say(`top edge of ${top.selector} is hidden (${why}); the dim and label would cover content — scroll it clear first (\`scroll\` with \`to\`)`);
}

/* ----------------------------------------------------------- assertions -- */

// An expect's failure is its own diagnosis: tagged so a rehearsal reports it
// rather than re-inspecting the step's target (now disabled, say).
const expectError = (msg) => Object.assign(new Error(msg), { expect: true });

async function check(spec, a) {
  const root = await frameFor({ ...a, frame: spec.frame ?? a.frame });
  let loc = spec.selector ? root.locator(spec.selector) : root.getByText(String(spec.text));
  if (spec.selector && spec.hasText) loc = loc.filter({ hasText: spec.hasText });
  if (spec.selector && spec.text != null) loc = loc.filter({ hasText: String(spec.text) });
  // A selector Playwright cannot parse is the shot list's bug, not the build's.
  try { await loc.count(); } catch (e) { throw expectError(`expect selector is invalid: ${e.message.split("\n")[0].replace(/^[\w.]+: /, "")}`); }
  // `count` counts what the viewer can see: a hidden duplicate (a responsive
  // copy of a table) is not a row on screen.
  const shown = loc.filter({ visible: true });
  const timeout = spec.timeout ?? (REHEARSE ? Math.max(cfg.rehearseTimeout ?? 4000, 5000) : 8000);
  const st = spec.state ?? "visible";
  const until = async (fn) => {
    const end = Date.now() + timeout;
    while (Date.now() < end) { if (await fn().catch(() => false)) return; await realSleep(150); }
    throw new Error("timeout");
  };
  const what = `${spec.selector ?? ""}${spec.text != null ? ` "${spec.text}"` : ""} ${spec.value != null ? `value~"${spec.value}"` : spec.count != null ? `count=${spec.count}` : st}`.trim();
  try {
    if (spec.value != null) await until(async () => String(await loc.first().inputValue()).includes(String(spec.value)));
    else if (spec.count != null) await until(async () => (await shown.count()) === spec.count);
    else if (["visible", "hidden", "attached", "detached"].includes(st)) await loc.first().waitFor({ state: st, timeout });
    else if (st === "enabled") await until(() => loc.first().isEnabled());
    else if (st === "disabled") await until(() => loc.first().isDisabled());
    else if (st === "checked") await until(() => loc.first().isChecked());
    else throw new Error(`unknown state ${st}`);
  } catch {
    const n = await loc.count().catch(() => null), v = await shown.count().catch(() => null);
    const val = spec.value != null && n ? await loc.first().inputValue().then((x) => `, value "${String(x).slice(0, 40)}"`).catch(() => "") : "";
    // With a text filter that matched nothing, say what the element does read.
    const reads = spec.selector && spec.text != null && n === 0
      ? await root.locator(spec.selector).first().innerText({ timeout: 500 }).then((x) => `; ${spec.selector} reads "${x.trim().slice(0, 60)}"`).catch(() => "") : "";
    const saw = n == null ? "" : ` (saw ${v} visible of ${n} match${n === 1 ? "" : "es"}${val}${reads})`;
    throw expectError(`expect failed: ${what}${saw} — the build or data is not what the shot list assumes`);
  }
}

/* ------------------------------------------------------------- actions -- */

let zoomOpen = null;
const SPOT_OUT = 150; // ms the spotlight takes to fade out
const MIME = { csv: "text/csv", json: "application/json", txt: "text/plain", png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", pdf: "application/pdf", xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", geojson: "application/geo+json", zip: "application/zip" };

async function run(a) {
  switch (a.type) {
    case "mark": break; // the take starts after this step
    case "goto": {
      await page.goto(new URL(a.url, base).toString(), { waitUntil: a.waitUntil ?? "domcontentloaded", timeout: T(a, 60000) });
      await sleep(a.settle ?? 1200);
      if (cfg.styleTag) await page.addStyleTag({ content: cfg.styleTag }).catch(() => {});
      await injectCursor();
      break;
    }
    case "hash": {
      const fr = await frameFor({ ...a, frame: a.frame ?? (cfg.frames?.app ? "app" : "page") });
      await fr.evaluate((h) => { location.hash = h; }, a.value);
      await sleep(a.settle ?? 1200);
      break;
    }
    case "eval": {
      await (await frameFor(a)).evaluate(a.script);
      await sleep(a.after ?? 0);
      break;
    }
    case "wait": await sleep(a.ms ?? 1000); break;
    case "waitFor": {
      const loc = await locate(a);
      await loc.waitFor({ state: a.state ?? "visible", timeout: T(a, 60000) });
      await sleep(a.settle ?? 300);
      break;
    }
    case "expect": await check(a, a); break;
    case "css": {
      await (await frameFor(a)).evaluate(([css, id, remove]) => {
        if (remove) { document.getElementById(remove)?.remove(); return; }
        const s = document.createElement("style");
        if (id) s.id = id;
        s.textContent = css;
        document.head.appendChild(s);
      }, [a.css ?? "", a.id ?? null, a.remove ?? null]);
      await sleep(a.after ?? 200);
      break;
    }
    case "press": await page.keyboard.press(a.key); await sleep(a.after ?? 500); break;
    case "cut": {
      // A deliberate scene change for a state no user path reaches: fade
      // out, change, fade back in.
      const fade = a.fade ?? 350, color = a.color ?? "#0f172a";
      record("cut", null);
      navigated = true;
      const label = a.label ?? "";
      await page.evaluate(cutCover, { on: true, color, fade, label }).catch(() => {});
      await sleep(fade + 60);
      const card = Date.now();
      if (a.url) {
        await page.goto(new URL(a.url, base).toString(), { waitUntil: "domcontentloaded", timeout: T(a, 60000) });
        if (cfg.styleTag) await page.addStyleTag({ content: cfg.styleTag }).catch(() => {});
        await page.evaluate(cutCover, { on: true, color, fade: 0, label }).catch(() => {});
      } else if (a.hash) {
        await (await frameFor({ ...a, frame: a.frame ?? (cfg.frames?.app ? "app" : "page") })).evaluate((h) => { location.hash = h; }, a.hash);
      } else {
        await (await frameFor(a)).evaluate(a.script);
      }
      await sleep(a.settle ?? 1000);
      // Hold a title card long enough to read (~1.4 s in all).
      if (label) await sleep(Math.max(0, 1400 - (Date.now() - card) / PACE));
      await injectCursor();
      await page.evaluate(cutCover, { on: false, color, fade }).catch(() => {});
      await sleep(fade + 60);
      break;
    }
    case "move":
    case "hover": {
      if (a.type === "move" && !a.selector) { record("move", { x: a.x - 1, y: a.y - 1, width: 2, height: 2 }); await moveCursorTo(a.x, a.y, a.ms ?? 900); break; }
      const { loc, box } = await rectOf(a);
      record(a.type, box);
      const [x, y] = pointIn(box, a);
      await moveCursorTo(x, y, a.ms ?? 900);
      await reachable(loc, box, x, y, a, { soft: true });
      if (a.type === "hover") await sleep(a.hold ?? 800);
      break;
    }
    case "click": {
      const { loc, box } = await rectOf(a);
      record("click", box);
      const [x, y] = pointIn(box, a);
      await moveCursorTo(x, y, a.ms ?? 900);
      await reachable(loc, box, x, y, a);
      if (await loc.isDisabled().catch(() => false)) warnings.push(`step ${state.step}: clicked a disabled control (${a.selector}) — fine for a refusal, otherwise the state is wrong`);
      await sleep(a.pause ?? 220);
      await ripple(x, y);
      await page.mouse.click(x, y);
      await sleep(a.after ?? 600);
      break;
    }
    case "type":
    case "paste": {
      const { loc, box } = await rectOf(a);
      record(a.type, box);
      const [x, y] = pointIn(box, a);
      await moveCursorTo(x, y, a.ms ?? 900);
      await reachable(loc, box, x, y, a);
      await ripple(x, y);
      await page.mouse.click(x, y);
      await sleep(240);
      if (a.clear) { await page.keyboard.press("ControlOrMeta+A"); await page.keyboard.press("Backspace"); }
      if (a.type === "paste") {
        // The app's paste handler sees a real `paste` event first; the text
        // is inserted only if the app does not take it.
        const taken = await loc.evaluate(pasteInto, a.text);
        if (!taken) await page.keyboard.insertText(a.text);
      } else {
        await page.keyboard.type(a.text, { delay: REHEARSE ? 0 : a.delay ?? 55 });
      }
      await sleep(a.after ?? 500);
      break;
    }
    case "select": {
      // A native <select> opens outside the page DOM; the cursor goes there
      // for the video and Playwright sets the value (the same `change`).
      const { loc, box } = await rectOf(a);
      record("select", box);
      const [x, y] = pointIn(box, a);
      await moveCursorTo(x, y, a.ms ?? 900);
      await reachable(loc, box, x, y, a);
      await sleep(a.pause ?? 220);
      await ripple(x, y);
      const label = a.option ?? a.label;
      await loc.selectOption(label != null ? { label } : a.value, { timeout: T(a, 10000) });
      await sleep(a.after ?? 600);
      break;
    }
    case "upload": {
      // The file lands on the input (hidden is fine); the cursor goes to what
      // a user would click: `via`, else the input's label or dropzone.
      const files = a.files ?? a.file ?? cfg.filePicker;
      const input = await locate(a);
      await input.waitFor({ state: "attached", timeout: T(a, 30000) });
      let via = a.via;
      if (!via) {
        const found = await input.evaluate((el) => {
          document.querySelectorAll("[data-fr-via]").forEach((n) => n.removeAttribute("data-fr-via"));
          const t = (el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`)) || el.closest("label")
            || el.closest('[data-drag-over],[class*="drop" i],[class*="upload" i]');
          if (!t || !t.getClientRects().length) return false;
          t.setAttribute("data-fr-via", "1");
          return true;
        });
        if (found) via = "[data-fr-via]";
        else if (await input.isVisible()) via = a.selector;
      }
      if (via) {
        const { box } = await rectOf({ ...a, hasText: undefined, nth: 0 }, { selector: via });
        record("upload", box);
        const [x, y] = pointIn(box, a);
        await moveCursorTo(x, y, a.ms ?? 900);
        await ripple(x, y);
      } else {
        warnings.push(`step ${state.step}: upload has no visible label or dropzone to point at; set \`via\``);
      }
      await input.setInputFiles(files);
      await sleep(a.after ?? 900);
      break;
    }
    case "drop": {
      // A file (or text) dragged in with the cursor, carrying a badge, firing
      // real dragenter/dragover/drop (or dragleave) with a real DataTransfer.
      const { loc, box } = await rectOf(a);
      record("drop", box);
      const paths = [a.files ?? a.file ?? []].flat();
      const files = paths.map((p) => ({ b64: readFileSync(p).toString("base64"), name: path.basename(p), mime: MIME[path.extname(p).slice(1).toLowerCase()] ?? "application/octet-stream" }));
      const [x, y] = pointIn(box, a);
      const fx = (x - box.x) / box.width, fy = (y - box.y) / box.height;
      const fire = (phase) => loc.evaluate(dragEvent, { phase, fx, fy, files, text: a.text ?? null }).catch(() => false);
      await setBadge(files.length ? files.map((f) => f.name).join(", ") : `“${String(a.text).slice(0, 28)}”`);
      let entered = false;
      await moveCursorTo(x, y, a.ms ?? 1100, async (raw) => {
        if (raw > 0.7 && !entered) { entered = true; await fire("dragenter"); }
        if (raw > 0.7) await fire("dragover");
      });
      const hold = a.hold ?? 900;
      for (let held = 0; held < hold; held += 300) { await fire("dragover"); await sleep(300); }
      await fire(a.leave ? "dragleave" : "drop");
      await setBadge("");
      await sleep(a.after ?? 900);
      break;
    }
    case "down": await page.mouse.down(); await sleep(a.after ?? 250); break;
    case "up": await page.mouse.up(); await sleep(a.after ?? 500); break;
    case "scroll": {
      // The wheel scrolls what is under the pointer: put the cursor over the
      // pane, wheel in small steps, then correct any remainder smoothly.
      const fr = await frameFor(a);
      const tgt = a.to && !["top", "bottom"].includes(a.to) ? await fr.locator(a.to).first().elementHandle({ timeout: T(a, 30000) }) : null;
      const pane = a.container ?? a.selector;
      const paneEl = pane ? await fr.locator(pane).first().elementHandle({ timeout: T(a, 30000) }) : null;
      const plan = await fr.evaluate(scrollPlan, { target: tgt, container: paneEl, block: a.block, offset: a.offset, to: ["top", "bottom"].includes(a.to) ? a.to : null, x: a.x, y: a.y });
      const off = await frameOffset(fr);
      // The cursor goes into the pane first (a frame's own page included) unless
      // it is already well inside: a page scrolling under a still cursor
      // elsewhere reads as moving by itself.
      const x1 = Math.max(0, off.x + plan.pane.x), y1 = Math.max(0, off.y + plan.pane.y);
      const x2 = Math.min(viewport.width, off.x + plan.pane.x + plan.pane.width), y2 = Math.min(viewport.height, off.y + plan.pane.y + plan.pane.height);
      const m = Math.min(40, (x2 - x1) / 4, (y2 - y1) / 4);
      if (!(cursor.x > x1 + m && cursor.x < x2 - m && cursor.y > y1 + m && cursor.y < y2 - m)) {
        await moveCursorTo((x1 + x2) / 2, y1 + (y2 - y1) * 0.55, a.ms ?? 700);
      }
      record("scroll", null);
      const steps = REHEARSE ? 1 : Math.max(6, Math.round(Math.max(Math.abs(plan.dy), Math.abs(plan.dx)) / 60));
      for (let i = 0; i < steps; i++) { await page.mouse.wheel(plan.dx / steps, plan.dy / steps); await sleep(18); }
      await sleep(250);
      await fr.evaluate(({ isDoc, startTop, startLeft, dx, dy }) => {
        const p = isDoc ? document.scrollingElement : document.querySelector("[data-fr-pane]");
        if (!p) return;
        const rt = startTop + dy - p.scrollTop, rl = startLeft + dx - p.scrollLeft;
        if (Math.abs(rt) > 4 || Math.abs(rl) > 4) p.scrollBy({ top: rt, left: rl, behavior: "smooth" });
      }, plan);
      await sleep(a.after ?? 700);
      break;
    }
    case "scrollTo": await rectOf(a); await sleep(a.after ?? 400); break;
    case "spotlight": {
      const { box, parts } = await spotTargets(a);
      const ms = a.ms ?? 2800, delay = a.delay ?? 700, fade = a.fade ?? 320, pad = a.padding ?? 10;
      const ev = record("spotlight", box, { ms, delay, fade, out: SPOT_OUT });
      await spotlightFit(box, parts, pad, a);
      for (const p of parts) {
        const [x, y] = pointIn(p.box, parts.length > 1 ? {} : a);
        await reachable(p.loc, p.box, x, y, { ...a, selector: p.selector }, { soft: true });
      }
      const t = Date.now();
      await parkOutside({ x1: box.x - pad, y1: box.y - pad, x2: box.x + box.width + pad, y2: box.y + box.height + pad });
      await sleep(Math.max(0, delay - (Date.now() - t) / PACE));
      const card = await page.evaluate(spotlightOn, { rect: box, label: a.label ?? "", padding: pad, position: a.position ?? "auto", fade });
      if (ev) ev.on = now();
      if (ev?.rect && card) {
        const x1 = Math.min(ev.rect.x, card.x), y1 = Math.min(ev.rect.y, card.y);
        ev.rect = { x: x1, y: y1, width: Math.max(ev.rect.x + ev.rect.width, card.x + card.width) - x1, height: Math.max(ev.rect.y + ev.rect.height, card.y + card.height) - y1 };
      }
      // A rehearsal shot of this step is taken with the label up.
      if (wantShot(state.step)) { await realSleep(fade + 60); await shoot(state.step); }
      await sleep(fade + ms);
      if (ev) ev.off = now();
      // Gone before the next beat starts: a label still fading over the next
      // step's cursor reads as a ghost.
      await page.evaluate(spotlightOff, SPOT_OUT);
      await page.waitForFunction(() => !document.querySelector(".__fr_spot"), null, { timeout: 1000, polling: 30 }).catch(() => {});
      await sleep(80);
      break;
    }
    case "zoom": {
      // The camera move is applied in post, keyed on this time and box, so
      // the live cursor and clicks never fight a CSS transform.
      const { box } = await rectOf(a);
      record("zoom", box);
      if (zoomOpen) zoomOpen.t1 = now();
      zoomOpen = { t0: now(), t1: null, rect: { ...box }, scale: a.scale, padding: a.padding ?? 40 };
      if (capture.on) zooms.push(zoomOpen);
      const ease = a.ease ?? 700;
      if (a.stay) { await sleep(ease); break; }
      await sleep(ease + (a.ms ?? 2500));
      zoomOpen.t1 = now();
      zoomOpen = null;
      await sleep(ease);
      break;
    }
    case "zoomOut":
      if (zoomOpen) { zoomOpen.t1 = now(); zoomOpen = null; }
      await sleep(a.ease ?? 700);
      break;
    default: throw new Error(`unknown action type ${a.type}`);
  }
  if (a.expect) await check(a.expect, a);
}

/* -------------------------------------------------------------- rehearse -- */

// For a missed step: what is actually on the page, and what to try instead.
async function diagnose(a, err) {
  const base = err.message.split("\n")[0].replace(/\x1b\[[0-9;]*m/g, "");
  if (err.expect || !a.selector) return { why: base };
  if (Array.isArray(a.selector)) {
    // A spotlight list: diagnose the first target that does not resolve.
    for (const sel of a.selector) {
      const d = await diagnose({ ...a, selector: sel, hasText: undefined, nth: undefined }, err);
      if (d.candidates || /hidden|no match/.test(d.why)) return { ...d, why: `${sel}: ${d.why}` };
    }
    return { why: base };
  }
  const hidden = (n) => `${n} match${n === 1 ? " exists" : "es exist"} but ${n === 1 ? "is" : "are"} hidden — add the step that reveals it (a click, a tab, a form value)`;
  try {
    const root = await frameFor(a);
    let loc = root.locator(a.selector);
    if (a.hasText) loc = loc.filter({ hasText: a.hasText });
    const n = await loc.count();
    if (n > 0) {
      let visible = 0;
      for (let i = 0; i < Math.min(n, 10); i++) if (await loc.nth(i).isVisible()) visible++;
      const disabled = await loc.first().isDisabled().catch(() => false);
      const why = visible === 0 ? hidden(n) : disabled && /timeout/i.test(base) ? `found ${n}; the first is disabled` : base;
      return { why };
    }
    // A role= selector never matches a hidden element, so a hidden target
    // reads as no match; ask again with hidden elements included.
    if (/role=/.test(a.selector)) {
      let all = root.locator(a.selector.replace(/(role=[\w-]+(?:\[[^\]]*\])*)/g, "$1[include-hidden]"));
      if (a.hasText) all = all.filter({ hasText: a.hasText });
      const h = await all.count().catch(() => 0);
      if (h > 0) return { why: hidden(h) };
    }
    const words = `${a.selector} ${a.hasText ?? ""} ${a.note ?? ""}`.toLowerCase().match(/[a-z0-9]{3,}/g) ?? [];
    const candidates = await root.evaluate((ws) => {
      const els = [...document.querySelectorAll('button, a[href], input, select, textarea, label, summary, [role], [data-testid], [aria-label]')]
        .filter((e) => e.getClientRects().length && getComputedStyle(e).visibility !== "hidden");
      const sel = (e) => {
        const tid = e.getAttribute("data-testid");
        if (tid) return `[data-testid="${tid}"]`;
        if (e.id && !/^\d|:/.test(e.id)) return `#${e.id}`;
        const tag = e.tagName.toLowerCase();
        if (e.getAttribute("name")) return `${tag}[name="${e.getAttribute("name")}"]`;
        const al = e.getAttribute("aria-label");
        if (al) return `${tag}[aria-label="${al}"]`;
        const t = (e.innerText || "").trim().split("\n")[0].slice(0, 40);
        return t ? `${tag} + hasText "${t}"` : null;
      };
      const scored = els.map((e) => {
        const hay = `${e.id} ${e.className} ${e.getAttribute("data-testid") ?? ""} ${e.getAttribute("aria-label") ?? ""} ${e.getAttribute("name") ?? ""} ${(e.innerText || "").slice(0, 80)}`.toLowerCase();
        return { s: sel(e), score: ws.reduce((n, w) => n + (hay.includes(w) ? 1 : 0), 0) };
      }).filter((c) => c.s && c.score > 0);
      scored.sort((x, y) => y.score - x.score);
      return [...new Set(scored.map((c) => c.s))].slice(0, 5);
    }, words);
    return { why: `no match for ${a.selector}${a.hasText ? ` with text "${a.hasText}"` : ""}`, candidates };
  } catch {
    return { why: base };
  }
}

/* ------------------------------------------------------------------ main -- */

const misses = [];
const shots = [];
const stepStarts = []; // node s, each step that starts during capture
let failure = null;
const wantShot = (n) => REHEARSE && (SHOTS || UNTIL === n);
const shotOf = (n) => path.join(shotDir, `${outName}-step-${String(n).padStart(2, "0")}.png`);
async function shoot(n) {
  mkdirSync(shotDir, { recursive: true });
  await page.screenshot({ path: shotOf(n), scale: "css" }).catch(() => {});
  if (!shots.includes(shotOf(n))) shots.push(shotOf(n));
}

// The take opens on the page at rest (`leadInMs`, 900): a first action fired
// at 0 s reads as a clip that starts mid-step. A leading `wait` or spotlight
// (its delay) already holds, so it counts toward the lead-in.
async function startTake() {
  await startCapture();
  if (!capture.on) return;
  const lead = cfg.leadInMs ?? 900;
  const first = cfg.actions.slice(takeStart).find((b) => !["mark", "expect", "waitFor", "css"].includes(b.type));
  const held = first?.type === "wait" ? first.ms ?? 1000 : first?.type === "spotlight" ? lead : 0;
  if (lead > held) await sleep(lead - held);
}
const expectText = (e) => e ? ` ⟶ expect ${e.selector ?? ""}${e.text != null ? ` "${e.text}"` : ""}${e.count != null ? ` count=${e.count}` : e.state ? ` ${e.state}` : ""}`.replace("expect  ", "expect ") : "";
const label = (a) => `${a.type}${a.selector ? ` ${[a.selector].flat().join(" + ")}` : ""}${a.hasText ? ` "${a.hasText}"` : ""}${a.type === "expect" ? `${a.text != null ? ` "${a.text}"` : ""}${a.count != null ? ` count=${a.count}` : a.state ? ` ${a.state}` : ""}` : expectText(a.expect)}${a.note ? ` — ${a.note}` : ""}`;

if (takeStart === 0) await startTake();
for (const [i, a] of cfg.actions.entries()) {
  state.step = i + 1;
  if (capture.on) stepStarts.push(now());
  const t = capture.on ? `t+${(now() - capture.t0).toFixed(1)}s` : i >= takeStart ? "take" : "setup";
  console.log(`[${i + 1}/${cfg.actions.length}] ${t.padEnd(7)} ${label(a)}`);
  const stall = setTimeout(() => console.log(`      … step ${i + 1} still running after 20s`), 20000);
  try {
    await run(a);
  } catch (err) {
    if (REHEARSE) {
      const d = await diagnose(a, err);
      misses.push({ step: i + 1, action: label(a), ...d });
      console.log(`      ✖ ${d.why}${d.candidates?.length ? `\n        try: ${d.candidates.join("  |  ")}` : ""}`);
    } else {
      failure = err;
    }
  } finally {
    clearTimeout(stall);
  }
  if (failure) break;
  await injectCursor();
  if (wantShot(i + 1) && !shots.includes(shotOf(i + 1))) {
    // Let a cut or spotlight fade finish: a shot mid-fade shows a half-dimmed page.
    await page.waitForFunction(() => !document.getElementById("__fr_cut") && !document.querySelector(".__fr_spot"), null, { timeout: 1500 }).catch(() => {});
    await shoot(i + 1);
  }
  if (UNTIL === i + 1) break;
  if (i + 1 === takeStart) await startTake();
}

if (REHEARSE) {
  const ok = misses.length === 0;
  for (const w of warnings) console.log(`  ! ${w}`);
  console.log(ok ? "\nrehearsal passed: every step resolved" : `\nrehearsal: ${misses.length} step(s) missed — fix them all, then rehearse again`);
  await finish({ ok, rehearse: true, misses, shots, steps: UNTIL ?? cfg.actions.length }, ok ? 0 : 2);
}

if (failure) {
  const msg = failure.message.split("\n")[0].replace(/\x1b\[[0-9;]*m/g, "");
  console.error(`\n✖ step ${state.step} failed: ${msg}`);
  const shot = path.join(outDir, `${outName}-failure.png`);
  await page.screenshot({ path: shot }).catch(() => {});
  await stopCapture();
  await fail("take", msg, 2, { failureShot: existsSync(shot) ? shot : null, hint: "rehearse with --rehearse to see every bad step at once; never re-run a failed take unchanged" });
}

const changes = capture.on ? await changedRegion() : [];
if (changes.length) {
  const u = changes.reduce((a, b) => ({ x1: Math.min(a.x1, b.x1), y1: Math.min(a.y1, b.y1), x2: Math.max(a.x2, b.x2), y2: Math.max(a.y2, b.y2) }));
  if ((u.x2 - u.x1) * (u.y2 - u.y1) < viewport.width * viewport.height * 0.6) await parkOutside(u);
}
// A plain take that is over in a blink reads as a glitch when it loops as a
// GIF; hold the end state until it lasts gifMinSeconds.
// A closing spotlight already held the end state; a long tail after it is
// dead air.
const endsOnSpotlight = cfg.actions.at(-1)?.type === "spotlight";
let tail = cfg.tailMs ?? (endsOnSpotlight ? 500 : 1600);
const plain = !zooms.length && !timeline.some((e) => e.type === "spotlight") && (cfg.format ?? "auto") !== "mp4";
if (capture.on && plain) tail = Math.max(tail, (cfg.gifMinSeconds ?? 5) * 1000 - (now() - capture.t0) * 1000);
await sleep(tail);
const tEnd = now();
if (zoomOpen) zoomOpen.t1 = tEnd;
const canvases = capture.on ? await canvasRects() : [];
const t1 = await stopCapture(tEnd);
if (!capture.frames.length) await fail("capture", "no frames captured");

try {
  const t0 = capture.t0;
  const since = (t) => (t == null ? t : t - t0);
  const take = timeline.map((e) => ({ ...e, t: e.t - t0, on: since(e.on), off: since(e.off) }));
  const zs = zooms.map((z) => ({ ...z, t0: z.t0 - t0, t1: (z.t1 ?? t1) - t0 }));
  // A canvas (WebGL map) redraw is invisible to the DOM tracker; compare
  // the first frame against later ones inside each canvas.
  const fr = capture.frames;
  for (const c of canvases) {
    const px = { x: c.x * dsf, y: c.y * dsf, w: c.width * dsf, h: c.height * dsf };
    const probes = [fr[Math.floor(fr.length / 2)], fr[fr.length - 1]];
    if (probes.some((p) => psnrSaysChanged(regionChanged(fr[0].file, p.file, px)))) changes.push({ x1: c.x, y1: c.y, x2: c.x + c.width, y2: c.y + c.height });
  }
  const { crop, why } = chooseCrop({ cfg, viewport, dsf, take, changes, navigated, zooms: zs });
  const frames = fr.map((f) => ({ file: f.file, t: f.t - t0 }));
  const out = assemble({ cfg, viewport, dsf, frames, t0: 0, t1: t1 - t0, outDir, outName, framesDir, take, steps: stepStarts.map(since), zooms: zs, crop, warnings });
  console.log(`\n${out.format.toUpperCase()} to post: ${out.post}  (${out.duration}s, ${out.size}${crop ? ", cropped" : ""}${out.zooms ? `, ${out.zooms} zoom` : ""})`);
  for (const w of warnings) console.log(`  ! ${w}`);
  await finish({ ok: true, ...out, crop: crop ? crop.css : null, cropWhy: why }, 0);
} catch (err) {
  await fail("assemble", String(err.stderr ?? err.message).split("\n").slice(0, 3).join(" "));
}
