# Record Feature Video: Behavioral Eval Pack

The recorder and the helpers are covered by `check-recorder.sh` and
`check-helpers.sh`, which are deterministic and free. This pack covers what
only a fresh agent running the skill can show: whether `SKILL.md` and its
references lead it to film the right story with few retakes, judge its own
take honestly, and stop at the right time.

Never show this file to the agent under test.

## How to run a case

A case is one merged PR with a UI change, filmed twice by fresh agents: arm A
follows the skill on the branch under test, arm B follows the skill on
`main`. Both run in `mode:pipeline` against the same dev server, with posting
disabled.

1. Check out the PR's merge commit in a detached worktree, so the dev server
   serves exactly that change:
   ```bash
   git -C <project> worktree add --detach ~/worktrees/<project>-eval-<N> <merge-commit>
   ```
   Start the app's dev server from that worktree on a free port. Prefer a
   fake-data or fixture mode when the app has one, so neither arm writes
   real data.
2. Spawn both arms as fresh subagents with the same prompt, differing only in
   the `SKILL.md` path:
   - "Read `<SKILL.md>` and follow it with `<N> <base URL> mode:pipeline`."
   - The project worktree as the working directory.
   - Never post or upload: arm A runs `post.sh --dry-run`; arm B prints the
     command it would run.
   - Copy the file it would post to a results folder.
   - Report rehearsals, takes and why each extra one happened, and every
     workaround.
3. Record each arm's wall time and tool calls from its completion notice.
4. Grade quality blind: a third fresh agent gets both files under neutral
   names (`clip-1`, `clip-2`), the PR's description, and the rubric below,
   and extracts frames itself with `ffmpeg`.

## Cases

| Case | PR | Why it is here | Expected from arm A |
|---|---|---|---|
| F1 | A merged PR that changes one screen (a title, a label, a badge) | A one-screen change: a short, plain take | A GIF cropped to the changed region, or a short MP4 if it must search |
| F2 | A merged PR that adds a button inside a table | One click on a button inside a table | A cropped GIF of the click and its result, or the full screen if the table must scroll |
| F3 | A merged PR that reorders a long page (cards above a table) | A layout change over a long page | An MP4 with a zoom or spotlight on the moved sections |
| S1 | Any backend-only PR | `pr-context.sh` says SKIP | `video skipped: no user-visible change`, with no browser opened |

## Rubric

| Measure | How |
|---|---|
| Time | Wall time from the agent's start to its report |
| Turns | Tool calls in the completion notice |
| Retakes | Takes beyond the first, and the cause of each |
| Accuracy | Does the clip show the PR's stated change, ending on the proof? (yes / partly / no) |
| Clarity | Can a reviewer who has not read the PR tell what changed in one viewing? 1-5 |
| Craft | Visible cursor at every step, no dead time over 3 s, legible text, no stale build, errors, spinners, or blank frames. 1-5 |
| Fit | GIF for a plain short take, MP4 for a guided one; cropped when the change sits in one region |

Keep results outside the skill folder, so a later agent under test cannot read them.
