# Voice: quiet by default, `full` to speak

Read in Step 1 when resolving the run's voice; it governs every reply, comment, and thread resolution the loop makes.

Babysitting is **quiet on the PR conversation by default.** The loop does its work (fixes, commits, pushes, thread resolution) without writing anything a human reads as the bot talking on the PR, and reports to the invoking user instead (Step 4, or the structured return in `mode:pipeline`). The carrier is the literal word `full` on the invocation. (`full` is this skill's *voice* word; it is unrelated to `resolve-pr-feedback`'s "full mode", which this skill always uses.)

| Voice | Behavior |
| --- | --- |
| **quiet** (default) | **No review-thread replies and no top-level PR comments**, except the CodeRabbit-only carve-out below. A `needs-human` item is parked and reported to the user, not written onto its thread; the pipeline run report lives only in the structured return. The loop still fixes, commits, pushes, and resolves the threads it handled. |
| `full` | Restores the conversational surface: replies on any thread (including a `needs-human` item's `decision_context` on its own thread) and the one pipeline run-report comment. |

**CodeRabbit-only carve-out (applies even when quiet).** A review thread whose comments are **all** authored by CodeRabbit, with no reply from any other account, is still replied to normally. Judge it from the thread's own comment authors, not from who opened the review: one other commenter makes it a conversation, and a conversation stays quiet. This keeps the bot-to-bot loop CodeRabbit expects (it reacts to replies) without the babysitter narrating into a human's thread.

**Ticking CodeRabbit's review box is not speaking.** Tick step 8 edits CodeRabbit's own status comment to tick its trigger checkbox (`references/coderabbit.md`). It adds no comment, so the quiet voice allows it. `@coderabbitai review` does post a comment: never use it as a substitute.

**Attribution follows config.** With `pr.attribution: true`, every comment or reply the run posts starts with `🤖 ` so a reader can tell which messages came from the babysitter; this carries down to `resolve-pr-feedback`'s replies on this run. With `false` (the default), posted text carries no robot emoji, signature, or other AI marker.

**Write every posted message in plain, short English** (in the spirit of ASD-STE100 Simplified Technical English). A reply tells the reviewer what changed; it does not perform diligence. Lead with the outcome in one sentence, give the reason only when the diff does not show it, then stop:

- One idea per sentence, under 20 words each, and at most four sentences.
- Active voice, simple tense: "I moved the check into `validate()`", not "The check has been moved".
- One word, one meaning: reuse a term verbatim instead of reaching for a synonym.
- No idiom, metaphor, slang, or hedging filler ("just", "simply", "I think we could probably").
- No courtesy padding ("Good catch", "Thanks for the review").
- Never restate the reviewer's comment back at them; the quote line already carries it.

A `needs-human` reply under `full` may run longer: state the decision needed, the options, and your lean, in that order. When the host lists the sibling `noslop` skill, you may pass a draft reply through it.

**Quiet narrows the delegates' envelope.** When quiet, the scope you pass to `resolve-pr-feedback` and the CI pass excludes `reply` except on CodeRabbit-only threads. A delegate may never restore a channel the run disabled: a result that posted a suppressed reply is rejected and re-surfaced like any other broadened action.
