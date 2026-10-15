#!/usr/bin/env node
/*
 * launcher.mjs: the recorder's browser broker for one nono session. It runs on
 * the host, outside every sandbox, from the copy nono-setup.sh installed in
 * ~/.local/share/feature-recorder (a folder the agent's sandbox can read
 * but never write). hook-before.sh starts it when a session starts and
 * hook-after.sh stops it.
 *
 *   node launcher.mjs --workdir DIR [--session ID] [--no-jail]
 *
 * record.mjs inside the sandbox reads <git dir>/feature-recorder.json for
 * the port and token, asks for a browser of the shot list's size, and closes
 * it after the take. The request carries numbers and one boolean only: no
 * paths and no Chromium flags, which could make Chromium run a program. Each
 * browser runs in its own nono sandbox (nono-browser.json) that reaches only
 * the localhost ports and hosts the agent's own sandbox reaches.
 * --no-jail exists for the recorder's evals, run by hand on a machine without
 * nono; nothing a client sends can turn the jail off.
 */
import http from "node:http";
import net from "node:net";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";
import { spawn, execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, unlinkSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const POOL = Array.from({ length: 20 }, (_, i) => 47810 + i);
const GL_FLAGS = ["--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--ignore-gpu-blocklist"];
const IDLE_MS = 15 * 60 * 1000;

const argv = process.argv.slice(2);
const opt = (f) => (argv.includes(f) ? argv[argv.indexOf(f) + 1] : undefined);
const workdir = opt("--workdir") ? path.resolve(opt("--workdir")) : null;
const session = (opt("--session") ?? "").replace(/[^A-Za-z0-9_-]/g, "") || `pid${process.pid}`;
const jail = !argv.includes("--no-jail");
const log = (m) => console.log(`${new Date().toISOString()} [${session}] ${m}`);

if (!workdir) { console.error("usage: launcher.mjs --workdir DIR [--session ID] [--no-jail]"); process.exit(2); }
if (process.env.NONO_CAP_FILE) { console.error("launcher.mjs runs outside the sandbox"); process.exit(2); }

let gitDir;
try {
  gitDir = execFileSync("git", ["rev-parse", "--absolute-git-dir"], { cwd: workdir, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
} catch { log(`${workdir} is not a git repo; nothing to serve`); process.exit(0); }

const readList = (f) => {
  try { return readFileSync(f, "utf8").split("\n").map((l) => l.replace(/#.*/, "").trim()).filter(Boolean); } catch { return []; }
};
const nonoConf = path.join(os.homedir(), ".config", "nono");
// The same lists the user's nono wrapper hands the agent's sandbox, read once
// at start as nono does: the browser reaches what the agent reaches, nothing more.
const allowPorts = [...new Set([...readList(path.join(workdir, ".nono-ports")), ...readList(path.join(nonoConf, "extra-ports"))]
  .map(Number).filter((p) => Number.isInteger(p) && p > 0 && p < 65536))];
const allowDomains = [...new Set([...readList(path.join(workdir, ".nono-domains")), ...readList(path.join(nonoConf, "extra-domains"))]
  .filter((d) => /^[A-Za-z0-9*.-]+$/.test(d)))];
const nonoBin = readList(path.join(HERE, "nono-path"))[0] ?? "nono";

const free = (port) => new Promise((resolve) => {
  const s = net.createServer().once("error", () => resolve(false)).once("listening", () => s.close(() => resolve(true)));
  s.listen(port, "127.0.0.1");
});
async function freePort(skip = []) {
  for (const p of POOL) if (!skip.includes(p) && (await free(p))) return p;
  return null;
}

const token = crypto.randomBytes(24).toString("hex");
const tokenFile = path.join(gitDir, "feature-recorder.json");
const pidDir = path.join(HERE, "sessions");
let port = null;
let browser = null; // { child, cdp, idle }

function writeTokenFile() {
  writeFileSync(tokenFile, JSON.stringify({ port, token, workdir }) + "\n", { mode: 0o600 });
}
function ownsTokenFile() {
  try { return JSON.parse(readFileSync(tokenFile, "utf8")).token === token; } catch { return false; }
}

function closeBrowser() {
  if (!browser) return;
  clearTimeout(browser.idle);
  try { process.kill(-browser.child.pid, "SIGTERM"); } catch {}
  log(`browser on :${browser.cdp} closed`);
  browser = null;
}

async function openBrowser({ width, height, dsf, gl }) {
  closeBrowser();
  const cdp = await freePort([port]);
  if (!cdp) throw new Error(`no free port in ${POOL[0]}-${POOL.at(-1)}`);
  const child = [process.execPath, path.join(HERE, "browser-child.mjs"), "--port", String(cdp), "--width", String(width), "--height", String(height), "--dsf", String(dsf), ...(gl ? ["--gl"] : [])];
  const cmd = jail
    ? [nonoBin, "run", "-s", "--profile", path.join(HERE, "nono-browser.json"),
        "--read", HERE, "--read", path.dirname(path.dirname(process.execPath)),
        ...[cdp, ...allowPorts].flatMap((p) => ["--open-port", String(p)]),
        ...(allowDomains.length ? allowDomains.flatMap((d) => ["--allow-domain", d]) : ["--block-net"]),
        "--", ...child]
    : child;
  const proc = spawn(cmd[0], cmd.slice(1), {
    cwd: HERE, detached: true, stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      ...(existsSync(path.join(HERE, "browsers")) ? { PLAYWRIGHT_BROWSERS_PATH: path.join(HERE, "browsers") } : {}),
      FEATURE_RECORDER_GL: gl ? GL_FLAGS.join(" ") : "",
    },
  });
  let out = "";
  proc.stdout.on("data", (b) => { out += b; });
  proc.stderr.on("data", (b) => { out += b; });
  const ready = await new Promise((resolve) => {
    const t = setTimeout(() => resolve(false), 30000);
    const check = () => { if (/^READY/m.test(out)) { clearTimeout(t); resolve(true); } };
    proc.stdout.on("data", check);
    proc.on("exit", () => { clearTimeout(t); resolve(false); });
  });
  if (!ready) {
    try { process.kill(-proc.pid, "SIGTERM"); } catch {}
    throw new Error(`browser did not start: ${out.slice(-600)}`);
  }
  browser = { child: proc, cdp, idle: setTimeout(closeBrowser, IDLE_MS) };
  proc.on("exit", () => { if (browser?.child === proc) browser = null; });
  log(`browser on :${cdp} ${width}x${height} at ${dsf}x${gl ? " gl" : ""} (${jail ? "own nono sandbox" : "no sandbox"})`);
  return `http://127.0.0.1:${cdp}`;
}

const int = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;
function validate(body) {
  const keys = Object.keys(body ?? {});
  const extra = keys.filter((k) => !["width", "height", "dsf", "gl"].includes(k));
  if (extra.length) return `unknown field(s): ${extra.join(", ")}`;
  if (!int(body.width, 320, 3840) || !int(body.height, 240, 2160)) return "width and height must be whole numbers within 320x240 to 3840x2160";
  if (![1, 2, 3].includes(body.dsf)) return "dsf must be 1, 2 or 3";
  if (body.gl != null && typeof body.gl !== "boolean") return "gl must be true or false";
  return null;
}

const send = (res, code, obj) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };
const server = http.createServer((req, res) => {
  const given = Buffer.from(String(req.headers["x-recorder-token"] ?? ""));
  const want = Buffer.from(token);
  if (given.length !== want.length || !crypto.timingSafeEqual(given, want)) return send(res, 403, { error: "bad token" });
  let body = "";
  req.on("data", (c) => { body += c; if (body.length > 1024) req.destroy(); });
  req.on("end", async () => {
    try {
      if (req.method === "GET" && req.url === "/health") return send(res, 200, { ok: true, workdir, jail, browser: browser ? `http://127.0.0.1:${browser.cdp}` : null });
      if (req.method === "POST" && req.url === "/browser") {
        let parsed;
        try { parsed = JSON.parse(body || "{}"); } catch { return send(res, 400, { error: "body must be JSON" }); }
        const bad = validate(parsed);
        if (bad) return send(res, 400, { error: bad });
        return send(res, 200, { cdp: await openBrowser(parsed) });
      }
      if (req.method === "DELETE" && req.url === "/browser") { closeBrowser(); return send(res, 200, { ok: true }); }
      return send(res, 404, { error: "not found" });
    } catch (err) {
      return send(res, 500, { error: err.message });
    }
  });
});

port = await freePort();
if (!port) { log(`no free port in ${POOL[0]}-${POOL.at(-1)}`); process.exit(1); }
server.listen(port, "127.0.0.1", () => {
  writeTokenFile();
  mkdirSync(pidDir, { recursive: true });
  writeFileSync(path.join(pidDir, `${session}.pid`), `${process.pid}\n`);
  log(`listening on 127.0.0.1:${port} for ${workdir} (${jail ? "jailed" : "no sandbox"}); ports ${allowPorts.length}, domains ${allowDomains.length}`);
});
// Another session in the same worktree may take the token file over and
// remove it when it ends; put ours back so this session keeps working.
setInterval(() => { if (!existsSync(tokenFile)) writeTokenFile(); }, 10000).unref();

const stop = () => {
  closeBrowser();
  if (ownsTokenFile()) { try { unlinkSync(tokenFile); } catch {} }
  try { unlinkSync(path.join(pidDir, `${session}.pid`)); } catch {}
  log("stopped");
  process.exit(0);
};
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
setTimeout(stop, 24 * 60 * 60 * 1000).unref();
