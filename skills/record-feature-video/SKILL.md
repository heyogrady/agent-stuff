---
name: record-feature-video
description: "Film a PR's UI change with a bundled Playwright recorder: visible cursor, rehearsal, auto-crop, zoom, spotlight; a GIF when short and plain, an MP4 when guided, posted to the PR with gh --attach."
argument-hint: "[PR#] [base-url] [what to show] [format:gif|mp4] [mode:pipeline]"
allowed-tools: Bash, Read, Write, Glob, Grep, Agent, AskUserQuestion
---

# Record Feature Video

The goal is a short, accurate clip that shows a reviewer the feature working: a visible cursor does what a user would do, and the clip ends on the result the PR promised. The bundled recorder owns the mechanics (cursor, capture, crop, zoom, encoding, format, posting checks). You own the judgment: what story to tell, which state proves it, and whether the clip shows it.

**What the recorder enforces, so you need not:** the cursor performs every on-camera step (navigation or scripting after `mark` is rejected, and each rejection names the replacement action); every click proves its point reaches the target; a dev server running from another checkout is refused; a short plain take becomes a cropped GIF and a guided one an MP4; every run ends with a `RESULT {json}` line, exit code, and cleaned-up frames.

**Never substitute a cursorless capture.** If the recorder cannot run, the result is `video skipped: <reason>`. Never fall back to a screenshot slideshow, another recorder, Playwright's `recordVideo`, or test output labelled as a demo. A missing video never blocks a PR.

**Arguments.** A blank PR means the current branch's PR. `format:gif|mp4` forces the format (else config `format`, else `auto`).

**`mode:pipeline`** (set by an orchestrator): unless `inline` is also given, the caller's context is already long, so hand the whole skill to one fresh subagent and wait for its result: pass this file's path and the same arguments plus `inline`, and return its report (result line, paths, claims). With `inline`, or without subagents, run every step yourself. Either way, ask nothing: the story is printed, not confirmed; credentials come only from config. A missing prerequisite or credentials, or a second failed take, ends as `video skipped: <reason>` with any local paths, never as a question or a loop.

```bash
SKILL_DIR="<absolute path of the directory containing this SKILL.md>";
```

Every script below lives in `$SKILL_DIR/scripts/`. Run each command in the foreground and unpiped (never through `tail`/`head`, never in the background); give the take a 600000 ms Bash timeout.

## 1. Is there anything to film?

```bash
bash "$SKILL_DIR/scripts/pr-context.sh" [PR]
```

Read `references/context.md` for what the digest holds, the `feature_video:` config, sign-in, the dev server, and nono. On `VERDICT: SKIP` stop with `video skipped: <reason>` (the reference names the one exception). Do not open the app to double-check. Pass any `WARNING:` line to the user (in `mode:pipeline`, into the report).

## 2. Prerequisites

```bash
bash "$SKILL_DIR/scripts/setup.sh"
```

It prints `Ready` at once when Playwright (in `~/.cache/feature-recorder`) and `ffmpeg` are present; otherwise it installs Playwright or names the missing tool. `gifski` (optional) makes sharper GIFs.

## 3. The story

A reviewer who has not read the PR should be able to tell, in one viewing, everything it changed. From the digest, the PR description, and the ticket's acceptance criteria:
- **List the claims**: every user-visible change the PR says it makes, including "X still works" claims. Each one a frame can show gets a beat, even a brief one; only what no frame can show goes in the caption.
- **Each beat**: the action a user would take, then the proof on screen. Pick a proof the old build could not show (a search that matched before proves nothing) that is visible in this data (two lines drawn on top of each other prove nothing); when no data shows it, spotlight what does differ and name the limit in the label. Where the screen holds its own contrast (a changed row beside an unchanged one), show both.
- **Label each proof**: a `spotlight` whose label is one plain sentence saying what changed ("An order with a coupon now shows its discount"), not a terse tag; when the old behaviour is not on screen, name it ("now amber, where it used to be green"). A `cut` to another scene gets a `label` too.
- **Start**: the page a user would start on, reached in setup and shown at rest. When a proof depends on how the data got that way, show that briefly on camera with a label saying why.
- **Format follows**: one self-evident claim (a toggle, a new button) can be plain, with no labels, and lands as a cropped GIF. Anything with labels or zooms is an MP4. Keep the whole under 45 s (cut "still works" beats first); data entry that is not itself a claim goes in setup or uses `paste`.
- **The caption** (`post.sh --caption`) names what no frame can show (the address bar, a native tooltip) and anything simulated (fake mode, seeded data).

Print the plan; unless `mode:pipeline`, ask the user to confirm or adjust it:

```markdown
**Demo for PR #<n>: <title>** · expected: <GIF | MP4> · ~<s>s
1. Start on <route> (setup: <sign-in / data>)
2. Claim: <change> — <click / type / drop> <control> → spotlight <proof> "<label>"
```

## 4. Record

Record it yourself: splitting the story from the recording was slower and judged worse.

Read `references/shot-list.md` first. Keep the shot list at `/tmp/feature-video-$(id -u)/<branch>/shots.json`; set its `format` and `gifMaxSeconds` from the argument or config. Run the recorder from the repo root (`cd <repo> && node "$SKILL_DIR/scripts/record.mjs" …`) so it can check the dev server is this checkout's.

1. Write the shot list. Setup goes before `mark`; an `expect` on something only this branch renders catches a stale build; an `expect` on each step the story depends on catches a wrong state. On an unfamiliar page, a short `--rehearse --shots` run is the cheapest way to learn it.
2. `--rehearse` until it reports zero misses. Each miss names candidate selectors or the element covering the target; fix them all before re-running. Rehearsal performs real actions, so reset any data it changed.
3. Check framing (labels, zooms, sticky headers) with `--rehearse --shots` rather than several `--until N` runs.
4. One take, without `--rehearse`. Never re-run a failed take unchanged; read its `failureShot` and `hint`, fix, rehearse, then take again.
5. Look at `sheet` (12 frames: one inside every spotlight, then step starts) and `endFrame` (inside a closing spotlight). Check that every claim has its beat and label, the cursor is visible at each step, each proof is on screen and legible, and nothing shows a stale build, an error, a spinner, a blank frame, or a secret. Read `warnings`. A crop that clips an effect gets `"crop": "off"`.

A take that passes this check ships. Re-take only for something wrong, missing, or unreadable, never to polish. In `mode:pipeline`, a failed take gets one fix and one more take; a second failure is `video skipped: <what the sheet showed>`.

For a guided MP4, a single read-only reviewer may help: give it the sheet, the end frame, and the one question "does this clip show each of <claims>, and is anything in it wrong or unreadable?".

## 5. Review and post

Interactive: if config sets `review_dir`, copy the `post` file there; print its path, open it if the platform can (`open` / `xdg-open`), and ask the user to post it, re-record, or keep it local.

When config sets `auto_post: false`, stop here: print the `post.sh` command below and the local paths. Otherwise read `references/posting.md` and run `post.sh` with `RESULT.post` from the repo root, passing `--pr <N>` when you know it. Report the format and why, the URL, and the local paths.
