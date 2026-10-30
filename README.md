# agent-stuff

Skills for the last mile of a change: a pull request a reviewer can read, a video that shows the change working, and an agent that keeps the PR moving until it is ready to merge.

| Skill | What it does | Runs |
|---|---|---|
| [`open-pr`](skills/open-pr/SKILL.md) | Commits what is uncommitted, pushes, and opens a draft PR with a description written for someone who did not watch the work. Refreshes an existing PR's description too. | Only when you type it |
| [`record-feature-video`](skills/record-feature-video/SKILL.md) | Films the UI change with a visible cursor: rehearses the steps, records, crops to the action, picks GIF or MP4, checks a contact sheet, and posts it into the PR body. | On request |
| [`babysit-pr`](skills/babysit-pr/SKILL.md) | Watches an open PR: answers review comments, fixes CI failures, keeps the branch current, and stops when the PR looks ready, is blocked, or runs out of budget. | On request |
| [`resolve-pr-feedback`](skills/resolve-pr-feedback/SKILL.md) | Judges each review comment, fixes the valid ones in parallel, replies, and resolves the threads. `babysit-pr` uses it. | On request |
| [`noslop`](skills/noslop/SKILL.md) | Rewrites or checks prose so it reads plainly and carries no AI writing tells. `open-pr` writes in its author mode. | On request |

## Install

**Claude Code**

```
/plugin marketplace add heyogrady/agent-stuff
/plugin install agent-stuff@agent-stuff
```

Skills then appear as `/open-pr` (or `/agent-stuff:open-pr` when another plugin uses the same name).

**Codex**: add the repo as a plugin marketplace (`.agents/plugins/marketplace.json`), or copy the folders under `skills/` into your Codex skills directory.

**Any other agent**: point it at this repo and ask it to install the skills you want. Each folder under `skills/` is self-contained; keep `noslop` with `open-pr`, and `resolve-pr-feedback` with `babysit-pr`.

## Requirements

- `git` and the GitHub CLI `gh`, signed in. `record-feature-video` posts with `gh pr edit --attach`, which needs **gh 2.99 or later**.
- For videos: Node.js 20+, `ffmpeg` and `ffprobe`. The first run of `skills/record-feature-video/scripts/setup.sh` installs Playwright 1.64.0 and headless Chromium into `~/.cache/feature-recorder`. `gifski` (optional) makes better GIFs.
- For `babysit-pr`: Python 3.
- Linear tickets are optional: a Linear MCP server, else the `linctl` CLI, else `open-pr` uses the ticket ID from the branch name.

### Running your agent inside nono

If you run your coding agent inside the [nono](https://nono.sh) sandbox, Chromium cannot start inside the agent's sandbox. Run this once per machine, **outside** the sandbox, and again after each update of these skills:

```
bash skills/record-feature-video/scripts/nono-setup.sh
```

It installs a small browser launcher in `~/.local/share/feature-recorder` (which the sandbox can read but not write), adds two session hooks to your nono `personal.json` profile (keeping a backup), and opens ports 47810-47829. Each nono session then starts a launcher on the host; the recorder asks it for a browser of a given size, and that browser runs in its own nono sandbox. Without nono, skip this section.

## Settings

Each repo can carry an optional settings file at its root:

- `agent-stuff.local.md`: your personal settings. Add `/*.local.md` to `.gitignore` so it is never committed.
- `agent-stuff.md`: team defaults, committed.

Both are Markdown files with YAML frontmatter; the local file wins. In a git worktree with neither file, the skills read the main checkout's.

```markdown
---
pr:
  draft: true            # new PRs open as drafts; `ready` on the command line overrides
  attribution: false     # no Co-Authored-By or "Generated with" lines
  body: full             # or quick
  title_style: repo      # repo | outcome | conventional
  visuals: optional      # required | optional | off, for frontend changes
  branch_naming:
    pattern: "feature/{ticket}-{slug}"
    pattern_no_ticket: "feature/{slug}"
feature_video:
  base_url: http://localhost:3000
  format: auto           # auto | gif | mp4
  gif_max_seconds: 12
  auto_post: true        # false: keep the file and print the post command
  viewport: { width: 1440, height: 900 }
  username: admin@example.test
  password: <dev-only password>
---
```

Every key is optional. Full lists: [`open-pr` settings](skills/open-pr/references/config.md), [`record-feature-video` settings](skills/record-feature-video/references/context.md). The recorder warns when a file that holds a password or cookies is not git-ignored.

## Arguments

Type the skill name followed by any of these; plain language works too ("open a ready PR", "film the new export button").

| Skill | Arguments |
|---|---|
| `open-pr` | `[PR#\|URL] [describe-only] [ready] [quick] [options] [exclude:<paths>] [mode:pipeline]` |
| `record-feature-video` | `[PR#] [base-url] [what to show] [format:gif\|mp4] [mode:pipeline]` |
| `babysit-pr` | `[PR#\|URL] [watch\|checkpoint] [duration] [draft:included] [full]` |
| `resolve-pr-feedback` | `[PR#\|URL\|comment URL] [mode:pipeline]` |
| `noslop` | `[mode:author\|edit\|detect] [text, file path, or nothing]` |

`mode:pipeline` runs a skill without questions, for an orchestrator that calls it.

## Evals

Evals live in `evals/<skill>/`, outside `skills/`, so an agent running a skill cannot read the answers. There are two kinds.

**Deterministic checks** run a skill's scripts against fixtures: a stub `gh`, a small fixture web app, and throwaway git repos. They never touch the network, upload a file, or edit a real PR. Each script exits with its number of failed checks, so `0` means everything passed.

| Script | What it checks | Checks | Time | Needs |
|---|---|---|---|---|
| `record-feature-video/check-helpers.sh` | Where the video lands in the PR body, which diffs get a video and which are skipped, settings lookup, the warning when a file holding a password is not git-ignored | 50 | ~20 s | bash, git, jq, python3 |
| `record-feature-video/check-recorder.sh` | The recorder end to end in real headless Chromium: shot-list lint, rehearsal, GIF and MP4 takes, cropping, scene cuts, and the nono browser launcher | 29 | ~2 min | Node.js 20+, ffmpeg, the recorder's Playwright |
| `babysit-pr/check-snapshot.sh` | The PR snapshot: work already claimed is not done twice, items that need a person are flagged, and an out-of-date branch is caught | 13 | seconds | python3 |
| `resolve-pr-feedback/check-scripts.sh` | Fetching only unresolved review threads, replying (and refusing while a review is pending), and resolving threads | 7 | seconds | jq |
| `open-pr/check-scripts.sh` | The settings resolver (defaults, personal over team, comments, invalid values, the main-checkout fallback); the body linter against one broken fixture per rule; and the skill's own worked examples against that linter | 36 | seconds | bash, git, python3 |

Run them from the repo root:

```
/bin/bash evals/record-feature-video/check-helpers.sh
bash skills/record-feature-video/scripts/setup.sh       # once, before the recorder check
bash evals/record-feature-video/check-recorder.sh
bash evals/babysit-pr/check-snapshot.sh
bash evals/resolve-pr-feedback/check-scripts.sh
bash evals/open-pr/check-scripts.sh
```

`evals/open-pr/lint-body.py` also works on its own: give it any PR body (and `--title`) to see which of `open-pr`'s mechanical rules it breaks.

`check-helpers.sh` runs under `/bin/bash` (bash 3.2 on macOS) on purpose, to keep the scripts portable. Pass check IDs to run a subset (`check-helpers.sh P6c C19`), and set `KEEP=1` to keep the scratch folder.

**Behavioral packs** test the instructions rather than the scripts: whether `SKILL.md` leads a fresh agent to a good result. A pack is run by hand. Two fresh agents run the skill on the same real PR, one following your branch and one following `main`, and you score both against the pack's rubric (time, retakes, accuracy, clarity, craft). Never show a pack to the agent under test. There are two:

- [`record-feature-video/skill-pack.md`](evals/record-feature-video/skill-pack.md): four cases, scored on time, retakes, accuracy, clarity and craft.
- [`open-pr/skill-pack.md`](evals/open-pr/skill-pack.md): eleven cases, one per way a description can go wrong, run three times per arm against a fake `gh` that captures the body. Each body is linted, scored for recall of a claims list written before the run, and compared blind by a judge from a different model family, in both orders.

**When you change a skill**, run its deterministic checks; when you change its `SKILL.md` or references, run its pack too if it has one. There is no CI, so nothing runs these for you.

**Not covered yet:** `noslop` has no evals, and `babysit-pr` and `resolve-pr-feedback` have no behavioral packs.

## Credits

`open-pr`, `babysit-pr`, `resolve-pr-feedback` and `noslop` began as adaptations of skills from [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) by Every, used under the MIT License; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Contribution rules are in [CONTRIBUTING.md](CONTRIBUTING.md).

MIT License.
