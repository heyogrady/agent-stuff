# Watch loop: scheduling, state, dedup, edge cases

Read once per babysit session, before acting on the first tick's output. It defines how ticks are scheduled per host, the on-disk state contract, the claim-act-confirm dedup protocol that makes ticks idempotent and crash-safe, and the edge cases. SKILL.md and `references/tick.md` own the ordering invariant; this file owns the mechanics.

## Step 5: Sustain the watch

**The self-sustaining watch runs autonomously after scope is set.** It never asks permission for the fixes, pushes, replies, and resolves it owns (Step 2's pre-authorization). After a tick that hit no **true** Step 3 stop (terminal / looks-ready-settled / `blocked-external-drained` / budget), go back to **waiting on the background `pr-snapshot watch` sentinel**. The detector wakes you when there is work to inspect or a new stop condition, so quiet time costs no reasoning.

**A tick that produced only a standing residual (a `needs-human` you parked, a `blocked-failing` you surfaced) is not a stop: re-arm and keep going.** The residual blocks *declaring* merge-ready, but new review rounds and CI keep coming and you must keep handling them; the detector will not re-wake on an already-surfaced residual (arm-time baseline). Re-arm `watch` after any mutation that moved the head, with the same invocation ID, start, and budget. A not-ready-but-not-blocked state (green but not settled, CI still running, a review still expected, an approval-gated PR inside its review drain) is neither a stop nor a question; keep waiting.

**Watcher silence carries no PR-state information.** It means only that no wake condition fired; a review may have finished quietly while the settle clock runs. Never narrate silence as "review still active". When the user asks for status before a wake, run a fresh `snapshot` with the same invocation fields (never `--start-invocation`) and report from that.

In **checkpoint mode** you are done after Step 4; the next tick is the user re-running the skill. Every tick is resumable from disk, so each wake (a sentinel, a scheduler fire, or a manual re-run) is a clean re-entry into Step 2.

## How the watch sustains itself

A skill's turn ends when it returns, so *the skill sets up its own loop*. Run the change detector in the background and wait for its output with the host's tools:

- **`pr-snapshot watch`** is the detector: the same fetch and diff on an interval, **no agent tokens**, one `BABYSIT_WAKE {reason,url,...}` line on work or a stop condition, then exit. Wake reasons are listed in `references/tick.md`.
- At the budget deadline, the final refresh preserves `terminal` and an already-settled `merge-ready`; `max-runtime` outranks every non-terminal work or residual wake so the cap cannot start another agent round.
- The agent waits for that line, runs a tick, and re-arms. Keep the session active while waiting, so each wake returns to *this* agent with the conversation's decisions intact (declined nits, a reviewer judged wrong, the user's mid-run steering).

Use the host's tools to run the detector and wait. A skill drives **tool calls**, never user-typed slash commands. Examples, not a required list:

| Host | Run and wait | Durable beyond the session? |
|------|--------------|-----------------------------|
| Claude Code | background `Bash` plus a monitor or wait tool | No; use cron for durable |
| Codex | `exec_command` to start the detector, then `write_stdin` to wait on its session | No |
| Cursor | background shell plus an output-notification sentinel | No |

**Checkpoint:** only when the user asks for it, or when the host cannot keep the session active while waiting. Run one tick, persist, report, and print the resume invocation (`references/setup.md`); monitoring is *paused*, say so plainly. Never fake a loop with a foreground `sleep` or a detached `nohup`.

**Durability:** the in-session watch dies with the session; re-invoking resumes from disk. For an unattended multi-day watch, use a durable scheduler (cron running `<host-cli> exec '<resume invocation>'`); a fresh headless run is context-blind, so persist consequential decisions to disk.

## Cadence

- `--interval` is the poll cadence: about 150 seconds while active; widen to 5-10 minutes when quiet. Each poll is a `gh` call, so respect rate limits.
- `--settle-seconds` (default 300) is the quiet window before a `merge-ready` wake. Leave it unset on the normal arm; only the widened re-arm in `references/stop-conditions.md` sets it.
- `--feedback-coalesce-seconds` (default 180) is the quiet window before a **comment-only** wake, so the ordinary push, bots comment, CI finishes sequence costs one agent round instead of two. Candidates stay actionable meanwhile; any other wake reason handles them. Leave it unset.
- `--blocked-external-drain-seconds` is set only after an approval-gate wake. Keep the ~150s interval during this short drain; the persisted head-scoped review clock decides expiry.
- `--stop-file <path>`: the watch exits with `stop-signal` when that file exists.
- Every re-arm presents the same three invocation values; only the first snapshot uses `--start-invocation`.
- Honor GitHub rate-limit reset headers; back off on `403`/`429`.

## Pipeline mode bound (`mode:pipeline`)

An orchestrator drives ticks in-line and needs the loop to end. Run ticks back-to-back until the stop below. **To wait for CI between ticks, use the host's non-blocking wait, never a bare foreground `sleep`.** If the host has none, do one tick and return control to the orchestrator rather than busy-spinning. Loop until:

- **success**, under the exact gates in `references/pipeline.md`; or
- a **budget** is hit: default **3 CI fix rounds** per head lineage and an overall time cap of about 30-45 minutes. Still-red checks and `needs-human` items become residuals.

Never wait on the merge-ready settle window or human review in pipeline mode. A check stuck `IN_PROGRESS` past the time cap ends the run with a "CI still running" residual. The round/time budget is a blunt cost floor, not a convergence detector; prefer to stop because the trajectory shows the loop is not converging.

## Non-convergence (trigger, route, park, re-open)

A loop can churn without finishing: CI **ping-pong** (fix A surfaces B, fix B brings A back), a review-bot **treadmill** (each commit spawns fresh nits), or **wrong-approach whack-a-mole** (each nit is valid but the approach is the problem). A raw counter cannot tell these from legitimate progress, so the decision is reasoning over the trajectory, and the split is strict:

- **`pr-snapshot` ships facts.** `check_recur_max` / `recurring_checks` (a check that failed, cleared, and failed again on a *new* head), `unresolved_trend` and `new_threads_this_tick`, `stream_alternations` (CI and review bouncing), `heads_since_progress`, and `invariant_rounds` (resolver-supplied `invariant_key` values counted per unique head; the script never infers a key). It never labels anything non-convergence.
- **The pass that owns the stream judges.** When a trigger fires (thresholds in `references/tick.md`), pass the trajectory to that tick's `resolve-pr-feedback` call or CI pass as mandatory input. It either names the invariant its next bounded fix resolves, or returns a `needs-human` that **parks the whole stream** with a `decision_context`. On a fix, the resolver returns a stable `invariant_key` per fixed root; babysit records it on the dispatched mark. A pass that would begin a third unique-head round for the same key (`rounds >= 2`) routes the trajectory **before** another push.

**The anti-cry-wolf line:** progressive failure migration (A fixed, then B appears once, B fixed, done) is ordinary repair; do not park. Oscillation (A returns after B's fix, the failing set cycles, the same invariant stays unsatisfied, or fix size grows) is non-convergence; park. "We've tried a lot" is never enough.

**A valid finding recurring across sibling sites** (each new head brings a fresh, valid thread with the same root and treatment) is one fix with a multi-site blast radius. Pass the cluster and the trajectory to `resolve-pr-feedback` and request a **bounded-class assessment**: it decides whether the sites are equivalent and fixes the class in one pass, falls back to per-site, or parks a wrong approach. Babysit never infers the root or the sites from churn counts.

**Guards:** moving-target is not non-convergence (base-branch merges, dependency bumps, flaky infra, and bot-rule changes create unrelated failures). If the CI pass concludes the review-requested behavior is invalid while the resolver concludes it is required, that is one cross-stream residual. A parked stream is a hard blocker but re-openable on material change: CI re-opens itself on a new head; a parked thread re-opens when a human answers it, or with `mark --thread <id> --disposition open`.

## Recording residuals

Every `needs-human` mark carries a typed residual file: the resolver's `needs-human` object written as JSON (`type`, `sources` with `id` and `kind`, `decision_context` with `quoted_feedback`, `investigation`, `decision_reason`, `options` of `{option, tradeoff}`, `recommendation` or null, and `thread_urls` with one URL per thread source). Write it under `$STATE_DIR` and park it with one residual mark:

```bash
python3 "$SKILL_DIR/scripts/pr-snapshot" mark --pr <N> --repo <host>/<owner>/<repo> --state-dir "$STATE_DIR" --invocation-id "<invocation_id>" --session-started-at "<invocation_started_at>" --invocation-budget-seconds "<invocation_budget_seconds>" --disposition needs-human --residual-file "$STATE_DIR/residual-<n>.json"
```

One mark freezes every source in the object under one decision; the script rejects a source already covered by another current decision. A CI residual you compose yourself uses source kind `check` with the check key; a branch-currency residual uses kind `currency` with the currency key (plus `--semantic-conflict-fingerprint` for a semantic conflict). When the user answers a parked decision in chat, record it with `mark ... --answer-decision <decision_id> --answer-file <file with their answer>`, then act on the answer next tick.

## On-disk state contract

State lives at `${XDG_CACHE_HOME:-$HOME/.cache}/babysit-pr/<host>-<owner>-<repo>-<pr>/state.json`, a stable path any later tick finds. The `<host>` segment keeps GitHub Enterprise PRs with the same `owner/repo#N` apart. `pr-snapshot` owns all reads and writes under a file lock. Main keys:

```json
{
  "pr": { "owner": "...", "repo": "...", "number": 123, "url": "..." },
  "head_sha": "abc123",
  "invocation_id": "<token>", "started_at": "<iso8601>", "invocation_budget_seconds": 28800,
  "last_activity_at": "<iso8601>", "dead_time_seconds": 0, "invocation_backstop_seconds": 259200,
  "watch_generation": "<opaque>",
  "checks": { "<check_key>": { "status": "COMPLETED", "conclusion": "FAILURE", "head_sha": "abc123" } },
  "threads": { "<thread_id>": { "last_comment_id": "...", "last_comment_at": "<iso8601>", "disposition": "open|dispatched|needs-human" } },
  "feedback": { "<comment_or_review_id>": { "kind": "comment|review", "disposition": "open|dispatched|needs-human" } },
  "ci_dispatched": { "<head_sha>": ["<check_key>"] },
  "human_decisions": [ { "id": "decision:<hash>", "residual": {}, "sources": [] } ],
  "base": { "host": "github.com", "repository": "owner/repo", "ref": "main", "oid": "...", "identity": "current" },
  "branch_currency_state": { "current_key": "currency:<hash>", "items": {}, "semantic_parks": {} },
  "pr_chain": { "relationship_status": "independent|dependent|probe-error", "default_branch": "main", "parent_prs": [], "dependent_prs": [] },
  "last_change_at": "<iso8601>",
  "trajectory": { "check_history": {}, "unresolved_series": [], "stream_series": [], "heads_since_progress": 0, "invariant_heads": {} }
}
```

A `check_key` is `"<workflow>/<name>"` (or `"<name>"` with no workflow). The blocked-external clock is head-scoped and narrower than `quiet_seconds`: external thread, comment, or review movement or a new head resets it; check, base, and disposition-only movement does not.

## Claim, act, confirm (the dedup protocol)

**The snapshot never marks an item handled just from observing it.** An item leaves the attention set only when you confirm you acted (`mark`) or remote truth removes it. A crashed or failed pass leaves its items actionable next tick, so the loop cannot silently drop work.

- **Review threads.** Actionable while unresolved and unmarked. A `dispatched` thread that is still unresolved is **reactivated** when a later reviewer comment moves its last-comment identity past the baseline captured at mark time (after your own reply), so your reply never re-triggers it but a reviewer's does. A parked thread stays parked, blocking merge-ready, until a human answers it on the thread, which reopens and wakes it.
- **Non-thread feedback** (top-level comments and review bodies) has no remote resolve, so a mark is the only thing that silences it. A `dispatched` item is never reactivated by a body edit (status bots rewrite their bodies on every push), though the edit still counts as review activity for the settle clock. A parked item does reactivate on an edit, because a human may answer by editing. Both count as one **review** stream for the trajectory and for the merge-ready backlog (`counts.threads` **and** `counts.comments` must both be 0).
- **CI checks.** A failing check on the current head is actionable until `mark --check <key>`. A new head SHA clears `ci_dispatched` and re-evaluates every check, so green is never carried across a push.
- **Current-base merge identity.** Mergeability is usable only when the live base OIDs match and the generated merge commit names that base and the observed head as parents. Otherwise `base_ref_blocker` is set (`race`, `mergeability-pending`, `probe-error`), no currency item is emitted, and the watch wakes `base-ref-blocked`. A `DIRTY` result may omit the generated merge; matching live-base observations still make it usable. GitHub sometimes leaves the merge computation on an old base; after the base has been stable for 10 minutes with the same head, the cached verdict is accepted with a `stale-computation` disclosure.
- **Branch currency.** Its identity binds the host-qualified live base ref and OID, the head SHA, the merge status, and the route. "Mergeable against the current base" and "head contains the latest base" are separate: only `BEHIND` or `DIRTY` requires maintenance. Claims, outcomes, and parks follow `references/tick.md` step 6.
- **Unrequested base merge.** When the head gains a merge commit whose second parent is the base tip without a claimed currency item, the snapshot reports `unrequested_base_merge`. Report it; never perform one on your own initiative.

## Merge-readiness and the settle window

Do not re-derive required checks or reviews; GitHub computes them. Use `mergeability_certain`, `mergeable == "MERGEABLE"`, and `merge_state_status == "CLEAN"`, then require `chain_blocker`, `base_ref_blocker`, and `branch_currency_blocker` to be null. A dependent PR can be ready relative to its parent but is not independently landable while that parent is open. `UNSTABLE` means mergeable with a non-required check red; `BLOCKED` means a required gate is unmet; `has_failing_checks` lets you act on red even under `UNSTABLE`.

The settle window guards the most damaging false positive: "CI went green, told the user to merge, then feedback landed." The script stamps `last_change_at` whenever anything observable moves, and each snapshot emits `quiet_seconds`. Whether a review is still coming is your judgment at the settle decision (`references/stop-conditions.md`). Quiet is a cooling-off signal, not a guarantee: report "looks ready, your call", never "safe to merge".

## Edge cases

- **Dependent PR:** keep the requested PR as the target, qualify readiness relative to an open parent, and report downstream impact. Never rebase, rewrite, or mutate a parent or child PR. A push to this PR may leave a child stale; that is a residual only.
- **Relationship probe error:** `chain_blocker` is set. Keep working review and CI, but do no branch-currency work and do not declare ready until a probe succeeds.
- **External head change or force-push:** the snapshot clears head-scoped CI state; re-snapshot and never clobber unrelated pushed work.
- **PR closed or merged externally:** `pr_state != "OPEN"` ends the run with a final status.
- **No push access / fork PR:** a push fails. Detect it from the result, report, and stop; the loop cannot make progress it has no permission to make.
- **CI that never completes:** when the budget is reached (the active cap or the 3-day wall-clock backstop), hand back with `invocation_elapsed_seconds` and the `max_runtime_ceiling` that fired; never substitute persisted-state age or start another budget automatically.
- **Rate limits / transient API errors:** honor the reset time, back off, resume. The claim-confirm protocol protects against replay.
