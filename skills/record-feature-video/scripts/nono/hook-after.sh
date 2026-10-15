#!/usr/bin/env bash
# nono session_hooks.after, installed by nono-setup.sh: stops this session's
# browser launcher. The pid file lives in the install folder, which the
# sandbox cannot write, so a session cannot point this at another process.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -s "$H/chain-after" ]; then
  "$(head -n 1 "$H/chain-after")" || true
fi
f="$H/sessions/${NONO_SESSION_ID:-none}.pid"
if [ -f "$f" ]; then
  pid="$(head -n 1 "$f")"
  case "$pid" in ''|*[!0-9]*) ;; *) kill -TERM "$pid" 2>/dev/null ;; esac
fi
exit 0
