#!/usr/bin/env bash
# nono session_hooks.before, installed by nono-setup.sh. Runs on the host
# before the sandbox goes up: runs the hook it replaced, then starts this
# session's browser launcher in the background. A launcher failure never
# blocks the session.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -s "$H/chain-before" ]; then
  "$(head -n 1 "$H/chain-before")" || exit $?
fi
mkdir -p "$H/logs"
nohup "$(head -n 1 "$H/node-path")" "$H/launcher.mjs" --workdir "$PWD" --session "${NONO_SESSION_ID:-}" \
  >> "$H/logs/launcher.log" 2>&1 < /dev/null &
exit 0
