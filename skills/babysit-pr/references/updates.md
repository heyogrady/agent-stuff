# Step 4: user updates and the stop summary

Read before writing any live update or stop summary.

Every stop, and every checkpoint tick, ends with a summary. Below the first line the format is yours; what matters is that it hits these goals, because each counters a specific way these summaries fail:

- **Outcome first: open with one status line.** Emoji, state, then one clause of evidence from the final snapshot (quiet time, CI, remaining backlog, parked residuals; real values). Only the state phrases are fixed:
  - `✅ Looks merge-ready — <evidence>. Your call to merge.` For a dependent PR with an open parent: `✅ Ready relative to its parent — <evidence>.`
  - `🟡 Cautiously looks ready — <stalled-reviewer evidence>. Your call to merge.`

  Other stops use the same shape with an emoji that states the condition: `🎉 Merged`, `🚫 Closed`, `⛔ Blocked`, `⏱️ Budget exhausted`, `⏸️ Paused`. A ready declaration opens only with ✅ or 🟡, and no other state uses those two.
- **PR state first in live updates.** Say what changed for the PR and what remains. Detector mechanics (a wake, a snapshot, a re-arm) are internal; mention them only when they explain a failure or a required user action.
- **A run recap at every true stop.** An hour-long watch resolves feedback and fixes CI the user never saw happen, and the stop summary is the only place that work becomes visible. After the status line, recap in a few short lines: what the feedback was about and how it settled (grouped by theme, with counts), what CI broke and the nature of each fix, what was pushed, how long the watch ran, and what remains parked. The test: the reader could decide whether to merge and explain the PR's journey without scrolling back. "Resolved 11 threads" without what they concerned fails it; so does a per-thread transcript. Build the recap from the PR's remote record (resolved threads, the commit list, check runs, via `gh`), the state dir's parked items, and the snapshot's elapsed time, not from conversation memory alone: a long watch outlives the context that saw its early rounds. If the watch changed nothing, one line says so.
- **Escalations are prominent.** Anything left for the human (a `needs-human` thread, a `needs-human` CI result, a merge conflict) is surfaced with its one-line "what it needs". **When quiet, this summary is the only place that analysis exists**, so carry each item's `decision_context` here with its thread link. Also name any review left stale by the run's own pushes.
- **Description freshness.** When the run's commits materially changed what the PR does, add one line: "Description may be stale — run `/open-pr <PR#|URL>` to refresh it, or `/open-pr describe-only <PR#|URL>` to preview." `open-pr` is manual-only, so never invoke it yourself. Omit the line otherwise.
- **Relationships are explicit.** For a dependent PR, name the parent and child PRs and qualify readiness relative to the parent. Never imply target-local success made the related PRs healthy.
- **Surface the judgment calls, not the routine fixes.** Where the loop did something other than the literal ask (a fix done differently than suggested, feedback declined or rebutted, a call the user steered mid-loop), name it in one line with the *why*. Skip routine "reviewer asked, we fixed it" items. If nothing non-routine was decided, say nothing.
- **Honest about settledness.** If it looks ready, say how long it has been quiet and that it is the user's call. Never imply "safe to merge".
- **Disclose a stalled reviewer briefly.** Name the reviewer or the observed signal, how long no further progress was observed, and that its lifecycle never produced a completion marker. Give the resume invocation; mention a manual review trigger only when the repository exposes one.
- **Checkpoint mode ends with the resume path.** State plainly that monitoring is paused and give the exact command for the next tick.
