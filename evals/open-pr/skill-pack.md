# Open PR: Behavioral Eval Pack

`check-scripts.sh` covers what a script can decide: the config resolver, and
`lint-body.py`, which checks a body against the mechanical rules. This pack
covers what only a fresh agent running the skill can show: whether
`SKILL.md` and its references lead it to a PR description a reviewer
understands, with the right shape for the change, every material claim, and
nothing invented.

Never show this file, `lint-body.py`, or any results to the agent under test.

The method draws on compound-engineering's `tests/skill-eval-cell` (replays,
claim recall, blind grading) and pstack's eval playbook (organic prompts,
one cross-family judge seeing both versions).

## How to run a case

A case is one change, described twice by fresh agents: arm A follows the
skill on the branch under test, arm B follows the skill on `main`. Run each
case **three times per arm**; one run of a prose skill is noise.

1. **Freeze the change.** For a replay case, take a merged PR from a project
   you own and check out its head commit in a scratch clone, with `main`
   reset to the PR's base:
   ```bash
   git clone --no-local <project> ~/scratch/open-pr-eval/<case>/repo
   cd ~/scratch/open-pr-eval/<case>/repo
   git switch -C main <base-commit> && git switch -C <branch-name> <head-commit>
   git init -q --bare ../remote.git && git remote set-url origin ../remote.git
   git push -q origin main
   ```
   The bare remote takes the push, so nothing reaches GitHub. For a scenario
   case, build the same layout from the setup the case names.
2. **Fake `gh`.** Put `evals/open-pr/fake-gh` first on `PATH` and point
   `FAKE_GH_STATE` at an empty folder per run. It captures the title and body
   in `title.txt` and `body.md`, and fails any call it does not know. To
   stand in for an existing PR, seed `title.txt` and `body.md` first.
3. **Prompt like a user.** Spawn each arm as a fresh agent with the project
   repo as its working directory and only this prompt, changed per case:
   - "Read `<SKILL.md path>` and follow it: open a PR for this branch."
   Never use the words eval, test case, judge, rubric, or arm in anything
   the agent sees, and never name the expected shape.
4. **Collect.** Copy `title.txt`, `body.md`, and `calls.log` to
   `~/scratch/open-pr-eval/results/<case>/<arm>-<trial>/`, outside this repo.
   Then check the transcript for `curl`, `git fetch`, or any `gh` call that
   failed: a run that reached the real PR may have read the answer, so drop
   it and run again.

## Cases

Pick replay PRs whose real description you know was good, and write each
case's **claims list** (below) before any run.

| Case | Source | What it tests | Expected from arm A |
|---|---|---|---|
| P1 | Replay: a dependency bump or one-line config change | Staying tiny | Lede and ticket line only; no sections, no collapsibles |
| P2 | Replay: a bug fix whose test was committed before the fix | The bug-fix shape with real proof | The six bug-fix sections in order; *Evidence* quotes the failing run at the earlier commit and the passing run |
| P3 | Scenario: a bug fix with no test and no failing run | Not inventing proof | *Evidence* says in one line that there was no failing run |
| P4 | Replay: a change to existing behavior (a default, a rule, a layout) | Before/After | A Before/After table and a **What did not change:** line |
| P5 | Replay: a new user-facing feature | Walk-through | `## What you can do now` steps from the user's chair; *How it works* answers what a reviewer would question |
| P6 | Replay: the first PR of a multi-PR series, with the series named in the prompt | Program altitude | The lede names the series outcome and what this PR contributes; no invented neighbors |
| P7 | Scenario: P5's repo plus a `docs/plans/` file describing the work | Private-source leaks | The why from the plan is stated as fact; nothing cites the plan, phases, or units |
| P8 | Scenario: P4's repo plus a `.github/pull_request_template.md` with its own headings | Respecting a template | The template's headings kept, the content placed within them |
| P9 | Scenario: P1's repo plus a template line asking for "Generated with ..." | Attribution stays off | No attribution anywhere in the title or body |
| P10 | Scenario: P4 with a seeded existing PR whose body has `## Summary`, `## Demo`, and a screenshot | Refreshing an old body | `describe-only` rewrites it into the current shape and keeps the screenshot |
| P11 | Scenario: a bug fix on branch `fix/web-4f-blank-coupon` | Error-tracker IDs | A `Related:` line for `WEB-4F`, no `Resolves WEB-4` ticket line, bug-fix shape |

When a real PR from `open-pr` goes wrong in a way no case catches, add it as
a replay case.

## Claims list

Before running a case, write the material claims a reviewer must come away
with, one line each, from the real PR and diff. A claim is an outcome, a
decision a reviewer would question, a number, or a risk:

```
P4-1  New invoices default to a due date 30 days out instead of 14.
P4-2  The default is per client, because some clients are on net 45 or 60.
P4-3  Existing invoices are not changed.
```

## Grading

1. **Lint every body.** Run
   `python3 evals/open-pr/lint-body.py body.md --title "$(cat title.txt)" --title-style outcome`
   (use `--title-style any` when the project has its own title convention).
   Record the hit count per rule.
2. **Score claims.** For each body on its own, mark every claim *covered*,
   *partial*, or *missing*, and mark any statement the diff does not support
   as *invented*. Recall is covered plus half of partial, over the claim
   count. Any invented statement fails the run.
3. **Compare blind.** Give one judge both bodies of a trial under the labels
   X and Y, with the diff and the claims list, and ask which one a reviewer
   who never opens the code would rather read, and why, in one paragraph.
   Use a judge from a different model family than the agents that wrote the
   bodies. Run every comparison in both orders; when the verdict flips with
   the order, record a tie.
4. **Read them yourself.** Read every body and compare your view with the
   judge's. When you disagree, either the judge is biased or the rubric is
   unclear; fix the rubric before trusting the next round.

## Rubric

| Measure | How |
|---|---|
| Lint | Hits from `lint-body.py`, by rule. Zero is the target |
| Recall | Covered claims, as above. Report per case and overall |
| Invented | Statements the diff does not support. Any one fails the run |
| Shape | The type the case expects, with that type's sections (yes / partly / no) |
| Lede | Names an outcome for users, not a mechanism (yes / no) |
| Skim | A reviewer who reads only the lede and the first section knows what changed and what to check (1-5) |
| Preference | Blind pairwise: A wins, B wins, or tie, after both orders |
| Time | Wall time from start to report |

Keep results outside the skill folder, so a later agent under test cannot
read them. A change to the skill ships when arm A is no worse on recall and
invented statements in every case, and wins or ties the blind comparison
overall.
