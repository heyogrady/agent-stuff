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

## Tests

Deterministic checks live in `evals/`, outside the skill folders so an agent under test cannot read them:

```
/bin/bash evals/record-feature-video/check-helpers.sh
bash evals/record-feature-video/check-recorder.sh     # real Chromium and ffmpeg
bash evals/babysit-pr/check-snapshot.sh
bash evals/resolve-pr-feedback/check-scripts.sh
```

## Credits

`open-pr`, `babysit-pr`, `resolve-pr-feedback` and `noslop` began as adaptations of skills from [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) by Every, used under the MIT License; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Contribution rules are in [CONTRIBUTING.md](CONTRIBUTING.md).

MIT License.
