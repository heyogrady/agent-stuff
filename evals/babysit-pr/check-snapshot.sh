#!/usr/bin/env bash
# Deterministic checks for babysit-pr's scripts/pr-snapshot.
#
# Drives snapshot, mark, and watch against injected --fetch-file fixtures
# (no network, no gh). Covers the invocation contract, the claim-act-confirm
# dedup, typed needs-human residuals, branch-currency claim/park/inspect, the
# relationship-probe blocker, and the removed multi-PR flags.
#
# Usage: evals/babysit-pr/check-snapshot.sh
#   KEEP=1 keeps the scratch dir.
# Exit status: number of failed checks (0 = all pass).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PS="$REPO/skills/babysit-pr/scripts/pr-snapshot"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/babysit-pr-eval-XXXXXX")"
if [ "${KEEP:-0}" = 1 ]; then echo "scratch: $WORK"; else trap 'rm -r "$WORK"' EXIT; fi
FAILS=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }
jget() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print(json.dumps(d) if isinstance(d, (dict, list)) else d)' "$1" "$2"; }

python3 - "$WORK" <<'EOF'
import json, sys, os
w = sys.argv[1]
H, B, B2 = "a" * 40, "b" * 40, "d" * 40
base = {"host": "github.com", "repository": "acme/web", "ref": "main", "oid": B, "graphql_oid": B,
        "historical_oid": B, "merge_commit_oid": "c" * 40, "merge_parent_oids": [B, H], "identity": "current"}
chain = {"relationship_status": "independent", "default_branch": "main", "parent_prs": [], "dependent_prs": []}
check = {"key": "CI/test", "name": "test", "status": "COMPLETED", "conclusion": "FAILURE",
         "details_url": "https://github.com/acme/web/actions/runs/1/job/2", "created_at": None,
         "started_at": "2026-01-01T00:00:00Z", "completed_at": "2026-01-01T00:05:00Z"}
busy = {"pr_state": "OPEN", "pr_is_draft": False, "mergeable": "MERGEABLE", "merge_state_status": "UNSTABLE",
        "review_decision": None, "head_sha": H, "base": base, "host_branch_update_capability": "unknown",
        "url": "https://github.com/acme/web/pull/7", "checks": [check],
        "threads": [{"thread_id": "PRRT_1", "last_comment_id": "C1", "last_comment_at": "2026-01-01T00:00:00Z",
                     "url": "https://github.com/acme/web/pull/7#discussion_r1", "path": "a.py", "line": 3}],
        "feedback": [{"id": "IC_1", "kind": "comment", "author": "rev", "edit_id": "abc"}],
        "awaiting_approval": 0, "head_parents": [B], "pr_chain": chain}
def dump(name, d): json.dump(d, open(os.path.join(w, name), "w"))
dump("busy.json", busy)
clean = json.loads(json.dumps(busy))
clean.update(merge_state_status="CLEAN", threads=[], feedback=[])
clean["checks"][0]["conclusion"] = "SUCCESS"
dump("clean.json", clean)
behind = dict(clean, merge_state_status="BEHIND", host_branch_update_capability=True)
dump("behind.json", behind)
dirty = dict(clean, merge_state_status="DIRTY", mergeable="CONFLICTING")
dump("dirty.json", dirty)
dirty2 = json.loads(json.dumps(dirty)); dirty2["base"].update(oid=B2, graphql_oid=B2)
dump("dirty2.json", dirty2)
perr = json.loads(json.dumps(clean)); perr["pr_chain"]["relationship_status"] = "probe-error"
dump("perr.json", perr)
merged = dict(clean, pr_state="MERGED")
dump("merged.json", merged)
EOF

# start <state-dir> <fixture>: bootstrap one invocation, export INV_* for later calls.
start() {
  mkdir -p "$1"
  python3 "$PS" snapshot --pr 7 --repo github.com/acme/web --state-dir "$1" --fetch-file "$WORK/$2" \
    --start-invocation > "$1/s0.json" || return 1
  INV_ID="$(jget "$1/s0.json" invocation_id)"
  INV_AT="$(jget "$1/s0.json" invocation_started_at)"
  INV_BU="$(jget "$1/s0.json" invocation_budget_seconds)"
}
snap() { python3 "$PS" snapshot --pr 7 --repo github.com/acme/web --state-dir "$1" --fetch-file "$WORK/$2" \
  --invocation-id "$INV_ID" --session-started-at "$INV_AT" --invocation-budget-seconds "$INV_BU"; }
mark() { local st="$1"; shift; python3 "$PS" mark --pr 7 --repo github.com/acme/web --state-dir "$st" \
  --invocation-id "$INV_ID" --session-started-at "$INV_AT" --invocation-budget-seconds "$INV_BU" "$@"; }
watch() { local st="$1" fx="$2"; shift 2; python3 "$PS" watch --pr 7 --repo github.com/acme/web --state-dir "$st" \
  --fetch-file "$WORK/$fx" --interval 1 \
  --invocation-id "$INV_ID" --session-started-at "$INV_AT" --invocation-budget-seconds "$INV_BU" "$@"; }

# 1. bootstrap emits the attention set and a fresh invocation
ST="$WORK/s1"
if start "$ST" busy.json && [ "$(jget "$ST/s0.json" counts)" = '{"threads": 1, "ci": 1, "comments": 1, "needs_human": 0}' ] \
   && [ "$(jget "$ST/s0.json" chain_blocker)" = None ]; then pass bootstrap; else fail bootstrap "$(jget "$ST/s0.json" counts)"; fi

# 2. a resume without the invocation token is refused
if python3 "$PS" snapshot --pr 7 --state-dir "$ST" --fetch-file "$WORK/busy.json" >/dev/null 2>&1; then
  fail resume-needs-token "snapshot without --invocation-id succeeded"; else pass resume-needs-token; fi

# 3. marks silence each stream; the next snapshot is empty
mark "$ST" --fetch-file "$WORK/busy.json" --thread PRRT_1 --disposition dispatched --invariant-key k1 >/dev/null \
  && mark "$ST" --comment IC_1 --disposition dispatched >/dev/null \
  && mark "$ST" --check CI/test >/dev/null && snap "$ST" busy.json > "$ST/s1.json"
if [ "$(jget "$ST/s1.json" counts)" = '{"threads": 0, "ci": 0, "comments": 0, "needs_human": 0}' ]; then
  pass marks-silence; else fail marks-silence "$(jget "$ST/s1.json" counts)"; fi

# 4. a stale invocation token cannot mark
if python3 "$PS" mark --state-dir "$ST" --invocation-id deadbeef --session-started-at "$INV_AT" \
     --invocation-budget-seconds "$INV_BU" --check CI/test >/dev/null 2>&1; then
  fail stale-token "mark with a wrong token succeeded"; else pass stale-token; fi

# 5. needs-human requires a typed residual; one residual parks a thread and a comment together
ST="$WORK/s5"; start "$ST" busy.json
cat > "$WORK/res.json" <<'EOF'
{"type":"needs-human","sources":[{"id":"PRRT_1","kind":"thread"},{"id":"IC_1","kind":"comment"}],
 "decision_context":{"quoted_feedback":"q","investigation":"i","decision_reason":"r",
 "options":[{"option":"a","tradeoff":"t"}],"recommendation":null},
 "thread_urls":["https://github.com/acme/web/pull/7#discussion_r1"]}
EOF
if mark "$ST" --fetch-file "$WORK/busy.json" --thread PRRT_1 --disposition needs-human >/dev/null 2>&1; then
  fail residual-required "needs-human without --residual-file succeeded"; else pass residual-required; fi
mark "$ST" --fetch-file "$WORK/busy.json" --disposition needs-human --residual-file "$WORK/res.json" >/dev/null
snap "$ST" busy.json > "$ST/s1.json"
if [ "$(jget "$ST/s1.json" open_needs_human)" = 1 ] && [ "$(jget "$ST/s1.json" counts.threads)" = 0 ] \
   && [ "$(jget "$ST/s1.json" counts.comments)" = 0 ]; then pass residual-parks; else fail residual-parks "$(jget "$ST/s1.json" counts)"; fi

# 6. BEHIND emits a claimable currency item and wakes branch-currency
ST="$WORK/s6"; start "$ST" behind.json
out="$(watch "$ST" behind.json)"
if [ "$(jget "$ST/s0.json" branch_currency.attention)" = claim ] && printf '%s' "$out" | grep -q '"reason": "branch-currency"'; then
  pass behind-currency; else fail behind-currency "$out"; fi

# 7. DIRTY: park with a fingerprint, then a moved base demands inspection first
ST="$WORK/s7"; start "$ST" dirty.json
KEY="$(jget "$ST/s0.json" branch_currency.key)"
python3 - "$KEY" "$WORK/cres.json" <<'EOF'
import json, sys
json.dump({"type": "needs-human", "sources": [{"id": sys.argv[1], "kind": "currency"}],
           "decision_context": {"quoted_feedback": "conflict", "investigation": "i", "decision_reason": "r",
                                "options": [{"option": "a", "tradeoff": "t"}], "recommendation": None},
           "thread_urls": []}, open(sys.argv[2], "w"))
EOF
mark "$ST" --disposition needs-human --residual-file "$WORK/cres.json" --semantic-conflict-fingerprint fp1 >/dev/null
snap "$ST" dirty2.json > "$ST/s1.json"
KEY2="$(jget "$ST/s1.json" branch_currency.key)"
claim_refused=0; mark "$ST" --currency-key "$KEY2" --currency-disposition claimed >/dev/null 2>&1 || claim_refused=1
if [ "$(jget "$ST/s1.json" branch_currency.attention)" = inspect ] && [ "$claim_refused" = 1 ]; then
  pass dirty-inspect-before-claim; else fail dirty-inspect-before-claim "attention=$(jget "$ST/s1.json" branch_currency.attention) refused=$claim_refused"; fi

# 8. a relationship probe error blocks readiness and currency
ST="$WORK/s8"; start "$ST" perr.json
if [ "$(jget "$ST/s0.json" chain_blocker)" = relationship-probe-error ] && [ "$(jget "$ST/s0.json" branch_currency)" = None ]; then
  pass chain-blocker; else fail chain-blocker "$(jget "$ST/s0.json" chain_blocker)"; fi

# 9. a clean, quiet PR wakes merge-ready; a merged PR wakes terminal
ST="$WORK/s9"; start "$ST" clean.json
out="$(watch "$ST" clean.json --settle-seconds 0.01)"
printf '%s' "$out" | grep -q '"reason": "merge-ready"' && pass merge-ready || fail merge-ready "$out"
out="$(watch "$ST" merged.json)"
printf '%s' "$out" | grep -q '"reason": "terminal"' && pass terminal || fail terminal "$out"

# 10. watch without the bootstrap values refuses with a recovery hint
out="$(python3 "$PS" watch --pr 7 --state-dir "$ST" 2>&1)"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'invoke the babysit-pr skill'; then pass watch-hint; else fail watch-hint "rc=$rc"; fi

# 11. multi-PR continuation flags are gone
gone=1
out="$(python3 "$PS" snapshot --pr 7 --state-dir "$ST" --continue-invocation 2>&1)"
case "$out" in *'unrecognized arguments'*) ;; *) gone=0 ;; esac
out="$(python3 "$PS" watch --pr 7 --state-dir "$ST" --invocation-id x --session-started-at "$INV_AT" \
  --invocation-budget-seconds 1 --downstack-pr 1 2>&1)"
case "$out" in *'unrecognized arguments'*) ;; *) gone=0 ;; esac
out="$(python3 "$PS" snapshot --help; python3 "$PS" watch --help)"
case "$out" in *--continue*|*--downstack*) gone=0 ;; esac
[ "$gone" = 1 ] && pass no-multi-pr-flags || fail no-multi-pr-flags "a removed flag is still accepted"

echo "failures: $FAILS"
exit "$FAILS"
