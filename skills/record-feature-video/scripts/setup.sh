#!/usr/bin/env bash
# Idempotent: prints "Ready" fast when everything is in place; otherwise
# installs Playwright (pinned, without install scripts) and its headless
# Chromium into a cache dir outside the skill (a plugin update never wipes it)
# and names any missing system tool.
# Inside nono, use nono-setup.sh instead.
set -euo pipefail;
HOME_DIR="${FEATURE_RECORDER_HOME:-$HOME/.cache/feature-recorder}";
missing=();
for t in node npm ffmpeg ffprobe; do command -v "$t" >/dev/null || missing+=("$t"); done;
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing: ${missing[*]}. Install Node.js 20+ (nodejs.org, or your package manager) and ffmpeg (ffmpeg.org; e.g. brew install ffmpeg, sudo apt-get install ffmpeg, winget install ffmpeg)" >&2;
  exit 1;
fi;
command -v gifski >/dev/null || echo "Note: gifski not found; GIFs fall back to ffmpeg's palette (larger, banded). Install it from gif.ski (or brew install gifski, cargo install gifski)" >&2;
command -v lsof >/dev/null || echo "Note: lsof not found; the dev-server ownership check is skipped." >&2;
PW_VERSION=1.64.0;
have="$(node -p "require('$HOME_DIR/node_modules/playwright/package.json').version" 2>/dev/null || true)";
if [ -f "$HOME_DIR/.ready" ] && [ "$have" = "$PW_VERSION" ]; then
  echo "Ready";
  exit 0;
fi;
mkdir -p "$HOME_DIR";
cd "$HOME_DIR";
[ -f package.json ] || printf '{ "name": "feature-recorder", "private": true }\n' > package.json;
npm install --silent --no-audit --no-fund --ignore-scripts "playwright@$PW_VERSION";
node "$HOME_DIR/node_modules/playwright/cli.js" install chromium-headless-shell;
touch .ready;
echo "Ready";
