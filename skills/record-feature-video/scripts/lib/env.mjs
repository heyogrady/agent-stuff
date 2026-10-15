// Everything outside the page: finding Playwright, the dev server the take
// depends on, and sandboxes (nono) that restrict the browser.
import { createRequire } from "node:module";
import { existsSync, readFileSync } from "node:fs";
import { execFileSync, spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

export const RECORDER_HOME = process.env.FEATURE_RECORDER_HOME ?? path.join(os.homedir(), ".cache", "feature-recorder");

export function loadPlaywright(setupScript) {
  const homes = [RECORDER_HOME];
  // Inside nono, the copy nono-setup.sh installed, which no session can edit.
  if (inNono()) {
    try { homes.splice(0, homes.length, readFileSync(path.join(NONO_HOME, "playwright-dir"), "utf8").trim()); } catch { homes.length = 0; }
  }
  for (const home of homes) {
    if (existsSync(path.join(home, "node_modules", "playwright"))) {
      return createRequire(path.join(home, "package.json"))("playwright");
    }
  }
  throw new Error(inNono() ? nonoHint(path.dirname(setupScript), null) : `playwright is not installed — run: bash ${setupScript}`);
}

const LOCAL = new Set(["localhost", "127.0.0.1", "0.0.0.0", "[::1]", "::1"]);

export function originOf(cfg) {
  const first = cfg.baseUrl ?? cfg.actions?.find((a) => a.type === "goto" && /^[a-z]+:/i.test(a.url ?? ""))?.url;
  try { return new URL(first); } catch { return null; }
}

export function portOf(url) {
  return url.port || (url.protocol === "https:" ? "443" : "80");
}

function listeners(port) {
  try {
    return execFileSync("lsof", ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-t"], { stdio: ["ignore", "pipe", "ignore"] })
      .toString().trim().split("\n").filter(Boolean);
  } catch { return []; }
}

// lsof prints the cwd as an `n/...` line. Inside a sandbox it may print an
// error in that slot instead (`ncwd|rtd info error: ...`); only a real
// absolute path counts.
export function parseLsofCwd(out) {
  const line = String(out).split("\n").find((l) => l.startsWith("n/"));
  return line ? line.slice(1) : null;
}

function cwdOf(pid) {
  try {
    return parseLsofCwd(execFileSync("lsof", ["-a", "-p", pid, "-d", "cwd", "-Fn"], { stdio: ["ignore", "pipe", "ignore"] }).toString());
  } catch { return null; }
}

// Localhost ports served by processes running from the repo. Ephemeral ports
// are skipped: a sandbox's proxy runs from the worktree too.
export function repoPorts(repo) {
  if (!repo) return [];
  try {
    const out = execFileSync("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"], { stdio: ["ignore", "pipe", "ignore"] }).toString();
    const byPid = new Map();
    let pid = null;
    for (const l of out.split("\n")) {
      if (l.startsWith("p")) pid = l.slice(1);
      else if (l.startsWith("n") && pid) {
        const port = Number(l.slice(l.lastIndexOf(":") + 1));
        if (port > 0 && port < 32768) byPid.set(pid, new Set([...(byPid.get(pid) ?? []), port]));
      }
    }
    const ports = new Set();
    for (const [p, set] of byPid) { const c = cwdOf(p); if (c && inside(c, repo)) set.forEach((x) => ports.add(x)); }
    return [...ports].sort((a, b) => a - b);
  } catch { return []; }
}

export function repoRoot(dir) {
  try {
    return execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: dir, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
  } catch { return null; }
}

const inside = (a, b) => a === b || a.startsWith(b + path.sep);

// A take recorded against another worktree's dev server shows the wrong build
// and looks clean. Returns { ok, error?, warning? }.
export function checkServer(cfg, repo) {
  const url = originOf(cfg);
  if (!url || !LOCAL.has(url.hostname)) return { ok: true };
  const port = portOf(url);
  const pids = listeners(port);
  const mine = () => { const ps = repoPorts(repo); return ps.length ? `; this worktree serves ${ps.map((p) => `:${p}`).join(", ")}, so point baseUrl there` : ""; };
  if (!pids.length) return { ok: false, listening: false, error: `nothing is listening on :${port} — start the dev server (or add a \`devServer\` block)${mine()}` };
  if (cfg.allowForeignServer) return { ok: true };
  const cwds = pids.map(cwdOf).filter(Boolean);
  if (!repo) {
    const from = cwds.length ? ` (:${port} is served from ${cwds.join(", ")})` : "";
    return { ok: true, warning: `dev-server ownership not checked: neither the shot list nor the cwd is inside a git repo; pass --repo <this worktree>${from}` };
  }
  if (!cwds.length) return { ok: true, warning: `dev-server ownership not checked: cannot read the cwd of the process on :${port} (sandboxed?)` };
  if (cwds.some((c) => inside(c, repo) || inside(repo, c))) return { ok: true };
  return {
    ok: false,
    listening: true,
    error: `:${port} is served from ${cwds.join(", ")}, not this repo (${repo})${mine() || ". Start this worktree's server on a free port"}, or set "allowForeignServer": true if that is intended`,
  };
}

// `devServer: { command, cwd?, port?, ready?, timeoutMs? }` — start this
// worktree's server for the take and stop it afterwards. An already-running
// server from this repo is reused.
export async function startDevServer(cfg, repo, log) {
  const ds = cfg.devServer;
  if (!ds) return null;
  const url = originOf(cfg);
  if (!url) throw new Error("devServer needs a localhost baseUrl");
  const port = String(ds.port ?? portOf(url));
  const existing = checkServer(cfg, repo);
  if (existing.ok) { log(`dev server already up on :${port}`); return null; }
  if (existing.listening) throw new Error(existing.error);
  const cwd = path.resolve(repo ?? process.cwd(), ds.cwd ?? ".");
  log(`starting dev server: ${ds.command}  (cwd ${cwd}, PORT=${port})`);
  const child = spawn(ds.command, { cwd, shell: true, detached: true, stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, PORT: port } });
  let tail = "";
  const keep = (b) => { tail = (tail + b.toString()).slice(-4000); };
  child.stdout.on("data", keep);
  child.stderr.on("data", keep);
  const ready = new URL(ds.ready ?? "/", url).toString();
  const deadline = Date.now() + (ds.timeoutMs ?? 120000);
  while (Date.now() < deadline) {
    if (child.exitCode != null) throw new Error(`dev server exited (${child.exitCode}):\n${tail.slice(-1200)}`);
    try {
      const res = await fetch(ready, { redirect: "manual" });
      if (res.status < 500) { log(`dev server ready (${res.status})`); return child; }
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  stopDevServer(child);
  throw new Error(`dev server not ready at ${ready} within ${(ds.timeoutMs ?? 120000) / 1000}s:\n${tail.slice(-1200)}`);
}

export function stopDevServer(child) {
  if (!child || child.exitCode != null) return;
  try { process.kill(-child.pid, "SIGTERM"); } catch {}
}

// Chromium does not read HTTPS_PROXY; a sandbox that routes traffic through
// a local proxy (nono) needs it passed explicitly. Localhost stays direct.
export function proxyOption(cfg) {
  if (cfg.proxy === false) return undefined;
  if (cfg.proxy) return cfg.proxy;
  const p = process.env.HTTPS_PROXY ?? process.env.https_proxy ?? process.env.HTTP_PROXY ?? process.env.http_proxy;
  if (!p) return undefined;
  return { server: p, bypass: "localhost,127.0.0.1,[::1]" };
}

// Inside nono Chromium cannot start. nono-setup.sh installs a launcher that
// the session's hooks run on the host; it starts each browser in a sandbox of
// its own, and <git dir>/feature-recorder.json says where it listens.
export const NONO_HOME = process.env.FEATURE_RECORDER_NONO_HOME ?? path.join(os.homedir(), ".local", "share", "feature-recorder");

export function launcherInfo(repo) {
  try {
    const gitDir = execFileSync("git", ["rev-parse", "--absolute-git-dir"], { cwd: repo ?? process.cwd(), stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    const info = JSON.parse(readFileSync(path.join(gitDir, "feature-recorder.json"), "utf8"));
    return Number.isInteger(info.port) && typeof info.token === "string" ? info : null;
  } catch { return null; }
}

async function launcherCall(info, method, route, body) {
  const r = await fetch(`http://127.0.0.1:${info.port}${route}`, {
    method,
    headers: { "x-recorder-token": info.token, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(method === "POST" ? 45000 : 3000),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error ?? `launcher answered ${r.status}`);
  return j;
}
export const launcherOpen = (info, spec) => launcherCall(info, "POST", "/browser", spec).then((j) => j.cdp);
export const launcherClose = (info) => launcherCall(info, "DELETE", "/browser").catch(() => {});

export function nonoHint(scriptsDir, repo) {
  return existsSync(path.join(NONO_HOME, "launcher.mjs"))
    ? `Chromium cannot start inside nono, and this session has no browser launcher: it was started without the nono wrapper, or before nono-setup.sh ran. Start a new session through the wrapper, or outside the sandbox run and leave running:
  node ${path.join(NONO_HOME, "launcher.mjs")} --workdir ${repo ?? "<this worktree>"}`
    : `Chromium cannot start inside nono. Once, outside the sandbox, in a terminal of your own:
  bash ${path.join(scriptsDir, "nono-setup.sh")}
then start a new session; the recorder finds its browser by itself.`;
}

export const inNono = () => Boolean(process.env.NONO_CAP_FILE);
