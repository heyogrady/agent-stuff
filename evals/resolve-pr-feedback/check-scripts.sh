#!/usr/bin/env bash
# Deterministic checks for resolve-pr-feedback's gh helper scripts.
#
# Runs the real scripts against the fake gh in fake-gh/ (no network). Covers
# the get-pr-comments output contract (unresolved threads only, blank bodies
# dropped, the author's own comment kept, pending-review detection), the
# REST reply path and its pending-review guard, and thread resolution.
#
# Usage: evals/resolve-pr-feedback/check-scripts.sh
# Exit status: number of failed checks (0 = all pass).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
S="$REPO/skills/resolve-pr-feedback/scripts"
command -v jq >/dev/null 2>&1 || { echo "check-scripts: needs jq" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/resolve-pr-feedback-eval-XXXXXX")"
trap 'rm -r "$WORK"' EXIT
export PATH="$HERE/fake-gh:$PATH" FAKE_GH_LOG="$WORK/gh.log"
FAILS=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }

out="$(bash "$S/get-pr-comments" 7 acme/web)"
summary="$(printf '%s' "$out" | jq -c '{t: [.review_threads[].node.id], r: [.review_threads[].root_comment_id], c: [.pr_comments[].id], b: [.review_bodies[].id], p: .pending_review, a: .pr_author, v: .viewer}')"
want='{"t":["PRRT_open"],"r":[101],"c":["IC_1"],"b":["PRR_2"],"p":null,"a":"dev","v":"me"}'
[ "$summary" = "$want" ] && pass get-pr-comments || fail get-pr-comments "$summary"

out="$(FAKE_GH_PENDING=1 bash "$S/get-pr-comments" 7 acme/web | jq -r .pending_review)"
[ "$out" = PRR_1 ] && pass pending-review || fail pending-review "$out"

: > "$FAKE_GH_LOG"
out="$(printf '> rename x\n\nRenamed in abc1234.\n' | bash "$S/reply-to-pr-thread" 7 101 acme/web)"; rc=$?
if [ "$rc" = 0 ] && grep -q 'repos/acme/web/pulls/7/comments/101/replies' "$FAKE_GH_LOG"; then
  pass reply-rest; else fail reply-rest "rc=$rc"; fi

printf 'body\n' | FAKE_GH_PENDING=1 bash "$S/reply-to-pr-thread" 7 101 acme/web >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && pass reply-pending-guard || fail reply-pending-guard "rc=$rc"

bash "$S/reply-to-pr-thread" 7 abc acme/web </dev/null >/dev/null 2>&1 && fail reply-validates-id "non-numeric id accepted" || pass reply-validates-id

out="$(bash "$S/get-thread-for-comment" 7 PRRC_1 acme/web | jq -c '{id, root_comment_id}')"
[ "$out" = '{"id":"PRRT_open","root_comment_id":101}' ] && pass thread-for-comment || fail thread-for-comment "$out"

out="$(bash "$S/resolve-pr-thread" PRRT_open | jq -r .data.resolveReviewThread.thread.isResolved)"
[ "$out" = true ] && pass resolve-thread || fail resolve-thread "$out"

echo "failures: $FAILS"
exit "$FAILS"
