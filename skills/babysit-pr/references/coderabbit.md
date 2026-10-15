# CodeRabbit on the head

Read at tick step 8 when CodeRabbit is active on the PR (its bot comments or `CodeRabbit` status context appear). Skip this file on repos without CodeRabbit; the helper's `absent` state also says so. It gets CodeRabbit to review every head the PR reaches, and feeds where CodeRabbit stands into the stop decision.

## Why this step exists

CodeRabbit skips most draft PRs (`Review skipped: draft pull request`), and pauses reviews on a branch that receives many commits (`Reviews paused`). In both cases it leaves a checkbox in its own status comment, and nothing reviews the head until someone ticks it. A push to a draft is skipped again, so every push needs a new tick. Worse, the `CodeRabbit` status context reads **success** for a skipped review, a rate-limited one, and a completed one alike. Only its description tells them apart, and `statusCheckRollup` does not carry the description. So a loop that reads only the check rollup counts a review that never ran as a pass.

Ticking the box edits CodeRabbit's own comment. It posts nothing new, so it is inside the quiet voice and inside the mutation envelope: do it without asking.

## Run the helper

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/babysit-pr/<host>-<owner>-<repo>-<N>";
python3 "$SKILL_DIR/scripts/coderabbit-tick" --repo <host>/<owner>/<repo> --pr <N> --ledger "$STATE_DIR/coderabbit-ticks.json" --wait <seconds>
```

Pass `--wait 180` on the first tick and on any tick that pushed. CodeRabbit posts its skip comment a little while after the push, and the helper returns as soon as CodeRabbit reacts. Pass `--wait 0` otherwise. **Give the shell call a timeout of at least 240 seconds** (or run it in the background and wait for it): many hosts default to 120, and a killed call prints no state. Always pass the ledger: it caps ticks at two per head commit, so a box CodeRabbit keeps offering cannot loop forever, and it records when each head was first seen, which turns an endless `waiting` into `no-reaction`.

The helper ticks only **Trigger a manual review**, **Resume reviews**, and **Trigger review**. It never ticks **Run on-demand review**, which bills per file, **Autopilot** or **Fix CodeRabbit comments**, which make CodeRabbit push code, or **Check again** after `No files to review`, which spends quota on a verdict that already stands. Do not tick any box by hand.

## Act on the state

| `state` | Meaning | Do this |
|---|---|---|
| `ticked` | A review of the head is starting. | Review still coming. Keep watching; its findings arrive as ordinary review threads. |
| `reviewing` | CodeRabbit is reviewing the head. | Review still coming. Keep watching. |
| `waiting` | CodeRabbit has not reacted to the head yet (this includes a new PR it has not reached). | Review still coming. Run the helper again next tick. |
| `reviewed` | CodeRabbit finished a review of the head. | Nothing. Its threads are handled by the feedback pass. |
| `no-new-files` | Nothing new since its last review; that verdict binds to this head. | Nothing. |
| `absent` | The PR is over ten minutes old with no CodeRabbit comment or status. | Skip this step for the rest of the run. |
| `skipped` | CodeRabbit skipped the head and offered no box. | Residual: CodeRabbit did not review the head. |
| `rate-limited` | The org is out of included reviews. | Residual naming it. When `billable` is true, the only offer is a paid on-demand review: that is the user's call. Never tick it. |
| `tick-cap` | Ticked twice on this head and still no review. | Residual: CodeRabbit is not responding to the box. |
| `no-reaction` | No verdict 30 minutes after the head was first seen (for example, the repo turned CodeRabbit's commit status off). | Residual: CodeRabbit never reviewed this head. |
| `failed` | CodeRabbit's status on the head is `error` or `failure`. | Residual naming the status description. |
| `paused-by-human` | Someone typed `@coderabbitai pause` and has not resumed it. | Leave it paused. Report it; resuming is theirs. |
| `error` | A `gh` call failed or returned something unreadable. | Retry next tick. Two errors in a row become a residual. An `error` on the run's last tick is a residual too. |

A residual here does not end the watch, and it does not block CI work. It does block **declaring** the PR looks ready, because nobody reviewed the head. Report it with the head SHA.

## In the stop decision

`ticked`, `reviewing`, and `waiting` mean a review is still coming (`waiting` ends at `no-reaction`, so this never blocks forever), under the review-still-coming judgment in `references/stop-conditions.md` and the pipeline gate in `references/pipeline.md`. Do not settle, and do not report pipeline success, while the latest result for the current head is one of them. Once the review lands, its threads go through the feedback pass like any other reviewer's.

A CodeRabbit review loop does not always converge. Each round reviews the code written to satisfy the previous round, and CodeRabbit sometimes re-raises findings it already withdrew. When a round brings only re-raises of settled items, the feedback pass declines them with that reasoning. Do not tick for another round in that case: the head's existing review is its verdict.
