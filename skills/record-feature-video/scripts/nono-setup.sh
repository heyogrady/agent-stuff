#!/usr/bin/env bash
# nono-setup.sh -- once per machine, for developers who run their agent inside nono.
# Without nono there is nothing to set up: the recorder launches its own
# browser (setup.sh installs it).
#
# Run it outside the sandbox, right after installing or updating the plugin
# (it copies from the plugin folder, which a sandboxed session can write).
# It is idempotent, and re-running it after a plugin update refreshes the copy.
#
#   bash nono-setup.sh [--extends PROFILE] [--profile-dir DIR] [--dry-run]
#
# What it changes, and nothing else:
#   ~/.local/share/feature-recorder/   the launcher, the browser's sandbox
#       profile, the two session hooks, Playwright 1.64.0 (installed with
#       --ignore-scripts) and its headless Chromium. The agent's sandbox can
#       read this folder but never write it, so nothing that runs on the host
#       can be changed from inside a session.
#   ~/.config/nono/extra-ports             adds 47810-47829 (launcher and
#       browser ports); the nono wrapper must pass this file's ports to
#       `nono run --open-port` so the agent's sandbox can reach them.
#   ~/.config/nono/profiles/personal.json  (nono's per-user profile) read
#       access to that folder, and session hooks that start a launcher with
#       each session and stop it after. The hooks it replaces still run
#       first. An existing personal.json is updated in place, keeping its own
#       extends, with a backup beside it; a new one extends --extends PROFILE
#       (default: claude-code).
set -euo pipefail

PW_VERSION=1.64.0
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/nono" && pwd)"
H="${FEATURE_RECORDER_NONO_HOME:-$HOME/.local/share/feature-recorder}"
PROFILES="$HOME/.config/nono/profiles"
DRY=0
EXTENDS=''
while [ $# -gt 0 ]; do
  case "$1" in
    --profile-dir) PROFILES="$2"; shift 2 ;;
    --extends) EXTENDS="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "nono-setup: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "${NONO_CAP_FILE:-}" ]; then
  echo "nono-setup: run this outside the nono sandbox, in a terminal of your own." >&2
  exit 2
fi
NONO="$(command -v nono || true)"
if [ -z "$NONO" ]; then
  echo "nono is not installed, so there is nothing to set up: the recorder launches its own browser."
  exit 0
fi
for t in node npm python3 git; do
  command -v "$t" >/dev/null || { echo "nono-setup: needs $t" >&2; exit 1; }
done
NODE="$(node -p 'process.execPath')"

if [ "$DRY" = 1 ]; then
  echo "would install into $H, add ports 47810-47829 to ~/.config/nono/extra-ports, and add hooks to $PROFILES/personal.json"
  exit 0
fi

umask 022
mkdir -p "$H/logs" "$H/sessions"
for f in launcher.mjs browser-child.mjs nono-browser.json hook-before.sh hook-after.sh; do
  install -m "$(case "$f" in *.sh) echo 755 ;; *) echo 644 ;; esac)" "$SRC/$f" "$H/$f"
done
printf '%s\n' "$NODE" > "$H/node-path"
printf '%s\n' "$NONO" > "$H/nono-path"

# Playwright in a fresh, versioned folder: no install scripts run, and no
# project .npmrc is read.
PW="$H/playwright-$PW_VERSION"
if [ ! -f "$PW/node_modules/playwright/package.json" ]; then
  mkdir -p "$PW"
  printf '{ "name": "feature-recorder-nono", "private": true }\n' > "$PW/package.json"
  (cd "$PW" && npm install --silent --no-audit --no-fund --ignore-scripts "playwright@$PW_VERSION")
fi
printf '%s\n' "$PW" > "$H/playwright-dir"
PLAYWRIGHT_BROWSERS_PATH="$H/browsers" "$NODE" "$PW/node_modules/playwright/cli.js" install chromium-headless-shell

EXTRA="$HOME/.config/nono/extra-ports"
mkdir -p "$(dirname "$EXTRA")"
if ! grep -q '^47810' "$EXTRA" 2>/dev/null; then
  { echo "# record-feature-video: browser launcher and browsers (nono-setup.sh)"; seq 47810 47829; } >> "$EXTRA"
  echo "added ports 47810-47829 to $EXTRA"
fi

mkdir -p "$PROFILES"
python3 - "$PROFILES" "$H" "$NONO" "$EXTENDS" <<'PY'
import json, os, re, subprocess, sys, time
profiles, home, nono, extends = sys.argv[1:5]
p = os.path.join(profiles, "personal.json")
ours = {"before": os.path.join(home, "hook-before.sh"), "after": os.path.join(home, "hook-after.sh")}

def inherited(name):
    try:
        out = subprocess.run([nono, "profile", "show", name], capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return {}
    hooks = {}
    for kind in ("before", "after"):
        m = re.search(rf"^\s*{kind}:\s*(\S+)", out, re.M)
        if m:
            hooks[kind] = m.group(1)
    return hooks

if os.path.exists(p):
    d = json.load(open(p))
    base = d.get("extends")
    prior = {k: v.get("script") for k, v in (d.get("session_hooks") or {}).items() if isinstance(v, dict)}
    if extends and extends != base:
        print(f"{p} already extends {base}; left as is (--extends applies only to a new personal.json)")
else:
    base = extends or "claude-code"
    d = {"extends": base, "meta": {"name": "personal", "version": "0.1.0", "description": f"{base} plus the feature-video browser launcher"}}
    prior = {}
chain = {}
for kind in ("before", "after"):
    cur = prior.get(kind)
    if not cur or cur == ours[kind]:
        cur = inherited(base).get(kind) if base else None
    if cur and cur != ours[kind]:
        chain[kind] = cur
for kind in ("before", "after"):
    f = os.path.join(home, f"chain-{kind}")
    with open(f, "w") as fh:
        fh.write(chain.get(kind, "") + ("\n" if kind in chain else ""))

new = json.loads(json.dumps(d))
fs = new.setdefault("filesystem", {})
if home not in fs.setdefault("read", []):
    fs["read"].append(home)
new["session_hooks"] = {k: {"script": ours[k], "timeout_secs": 10} for k in ("before", "after")}
if new != d:
    if os.path.exists(p):
        bak = f"{p}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        os.replace(p, bak)
        print(f"backed up {p} to {bak}")
    with open(p, "w") as fh:
        json.dump(new, fh, indent=2)
        fh.write("\n")
    print(f"updated {p}: read {home}; session hooks start and stop the launcher" + (f"; still runs {', '.join(chain.values())} first" if chain else ""))
else:
    print(f"{p} already set up")
PY
"$NONO" profile validate "$PROFILES/personal.json" >/dev/null

echo "Ready. Start a new nono session; the recorder will find its browser by itself."
