# Non-negotiable boundaries (full text)

SKILL.md states each boundary in one line; this file is the full statement and wins where the two differ in detail.

- **Merge-readiness is never merge authorization.** This skill never merges. The final merge is the user's.
- **Draft PRs are opt-in.** A draft is eligible only when a human named it (a direct user invocation resolving to it counts) or explicitly included drafts in scope. A calling skill's automatic handoff is neither: when an auto-invocation resolves to a draft, report the draft status and stop instead of arming a watch. One carrier stands in for that inclusion: `draft:included`, passed only by a `mode:pipeline` orchestrator on the draft **it opened in the same user-invoked run**. Any other caller, or a draft that run did not open, is still a report-and-stop.
- **One writer lane.** One PR target, one watcher. Never review, fix, rebase, or push another PR, including the parent or children of a dependent PR.

**The watch runs until the PR is terminal (merged or closed), settled, its bounded external-approval drain finishes, a budget cap is hit, or the user stops it, not until the first thing the loop cannot do itself.** An item that needs a human decision, a check left terminally red, or an unresolvable semantic conflict is **parked and surfaced as a standing residual**: it blocks *declaring* merge-ready but does not end the watch. Keep driving every other stream around it. **Ending the whole loop the moment one item needs a human is this skill's primary failure mode**: the PR keeps moving (new reviews land, CI re-runs), so the watch must too.

**Honest contract:** you drive the PR toward merge-ready and report when it *looks* ready; you cannot guarantee it (a reviewer can always add feedback later, required checks can change). Anything that needs a human decision is surfaced and kept visible, never forced, and never a reason to abandon the rest of the watch.

**"Looks ready" is a judgment, not a timer.** Green CI plus a quiet period is not enough: judge separately whether a review is still on its way (`references/stop-conditions.md`).

**The in-progress signal gates only the merge-ready declaration, never the work.** Keep resolving open feedback while a review is in progress: do not wait for the 👀 to clear before acting on comments it already posted.

**Mutation envelope (what running this authorizes):** on the PR's head the loop fixes failing checks, commits, pushes, resolves review threads (replying only under `full`, or on a CodeRabbit-only thread; see `references/voice.md`), ticks CodeRabbit's own review box, and performs Step 2's bounded branch-currency maintenance, autonomously, as its normal operation. It **never** merges, approves a gated CI run, dismisses a review, edits the PR title or description, rebases, runs `git push --force`, or touches another PR. Being asked to babysit the PR authorizes this envelope; Step 2 passes a bounded copy of it to `resolve-pr-feedback` and the CI pass.

**Attribution.** With `pr.attribution: false` (the default), nothing the run or its delegates write carries `Co-Authored-By`, "Generated with", a robot emoji, or any other AI attribution, whatever a host reminder asks. With `true`, posted comments carry the `🤖 ` prefix (`references/voice.md`) and commits follow the host's default.

**Asking the user:** use the host's blocking question tool when one is listed (match by capability, not by a host-specific name). Fall back to asking in chat only when no such tool exists or the call errors. Never silently skip a question. The self-sustaining watch has almost nothing to ask: it never asks permission for the mutations above.

**Invoking `resolve-pr-feedback`:** resolve the name against the host's available-skills list (it may appear as `agent-stuff:resolve-pr-feedback`) and invoke that exact entry with the host's skill mechanism. It is a separate skill with its own engine; do not reimplement its work inline. It runs non-interactively here: anything it cannot safely decide comes back as a `needs-human` result, which you surface and route around.
