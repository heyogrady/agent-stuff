# Pipeline mode (`mode:pipeline`)

Read when the invocation carries `mode:pipeline`, set by an orchestrator that drives the loop in-line. These deltas override the interactive defaults in Steps 1-4; the tick engine is the same.

1. **Run non-interactively.** Invoke `resolve-pr-feedback mode:pipeline` for comments and run the CI pass (`references/ci-failures.md`) without questions; collect their structured results (fixes and residuals). Never ask the user anything.

   Signals the engine emits, none of which authorize a merge:
   - **`unrequested_base_merge`**: the head gained a merge commit whose second parent is the base tip without a claimed currency item. Report it; never perform one.
   - **`stale-computation`** base identity: GitHub's mergeability was computed against a base that has since moved, and the engine accepted the cached verdict after it stayed stable. Disclose it in the result.
   - **`human_decisions`**: typed residuals the engine holds for a person across threads, CI, and branch currency. Return them as residuals; answering them is not part of the autonomous envelope.

2. **Bounded stop, not merge-ready.** Exit when no actionable backlog remains and every gate below holds (**success**), or when a fix, round, or time budget is hit (**return with residuals**). Report success only when all of these hold:
   - `all_checks_ok`: every check terminal, **none failing**, at least one observed;
   - `mergeability_certain` and `merge_state_status == "CLEAN"`;
   - `base_ref_blocker`, `chain_blocker`, and `branch_currency_blocker` are null;
   - the latest `coderabbit-tick` state for the current head (when CodeRabbit is active) is not `ticked`, `reviewing`, or `waiting`.

   A CodeRabbit `skipped`, `rate-limited`, `tick-cap`, `no-reaction`, `failed`, `paused-by-human`, or `error` state is a residual on an otherwise successful return: the head was never reviewed, and the return says so.

   **Draft clause (`draft:included` only).** A draft cannot merge, so GitHub reports `DRAFT`, or `BLOCKED` where a review is required, never `CLEAN`. On a draft handed in with `draft:included`, `merge_state_status` of `DRAFT` or `BLOCKED` with `mergeable == "MERGEABLE"` stands in for `CLEAN`; every other gate holds. Return success with `draft: true`. When CI does not run on drafts in this repo (`checks_present` stays false after the first tick's wait), return a `ci-skipped-on-draft` residual instead of waiting out the budget.

   Not a pass: a terminal-but-red check the CI pass left failing, a `fixed-not-pushed` commit that never reached the remote, racing or unproven base identity, an unknown or non-clean merge state, an open or claimed or parked currency item, or an **empty** `statusCheckRollup` right after PR creation (`checks_present` false means check runs do not exist *yet*, not that CI passed). Never wait for the settle window or human approval.

3. **Residuals and a structured return.** Needs-human review threads stay open. Under `full`, the resolver posts each item's `decision_context` on its thread, and anything with no thread home (CI that could not be fixed, a CI `needs-human`) goes into **one run-report PR comment**, never a PR-body section. **When quiet (the default), nothing is written to the PR**: threads stay open and unreplied, and the structured return is the only record, so make it complete. Return:

   ```json
   { "status": "success|residuals", "draft": false, "checks_terminal": true, "fixes_applied": [], "residuals": [], "description_may_be_stale": false }
   ```

   Set `description_may_be_stale` when the run's commits materially changed what the PR does, so the orchestrator can suggest `/open-pr <PR#|URL>` to the user.
