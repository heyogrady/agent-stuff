# Posting the take to the PR

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
bash "$SKILL_DIR/scripts/post.sh" "<RESULT.post>" [--pr N] [--alt "<what the clip shows>"] [--caption "<one line>"] [--dry-run]
```

`post.sh` writes the take into the PR body and uploads it in one `gh pr edit --attach` call, then reads the body back to prove the upload replaced the local path. Post only `RESULT.post`; the other format stays local.

- **Placement.** The take sits in a marked block, `<!-- feature-video -->` … `<!-- /feature-video -->`, directly below the opening summary (and the ticket line, if there is one), never under a `## Demo` heading. A re-run replaces the whole block, caption included, instead of adding a second; a block under the older `pog-feature-video` marker pair counts as ours and is rewritten with the new one.
- **Someone else's visual is never touched.** A video or image already in the body without the marker stays where it is; the take goes above it, and one stderr line says what was kept (for several: the count and the first). The rest of the body, trailing blank lines included, is kept byte for byte. Pass `--replace-unmarked` only when the user says that video is an earlier take of ours; in `mode:pipeline`, keep both and report the kept one.
- **Form.** A GIF becomes an image with alt text (`--alt`, default from the file name: say what the clip shows in a few words). `--alt` has no effect on an MP4 (stderr says so); use `--caption`. An MP4 is written as `![](/abs/take.mp4)` alone in its paragraph; `gh` turns that into the bare asset URL, which GitHub renders as a player, and the readback checks it. Never move an MP4 into a table cell, a link, or beside other text: it stops playing.
- **Caption.** `--caption` adds a line under the take inside the block. Use it when the take shows fake data or simulated timing, and to name the claims no frame could show, in at most two sentences ("Fake-mode data. The full title also shows on hover."), so the video never contradicts the PR's claims. Never add text beside the block by hand: a re-run would not replace it.

The last line is `POSTED {json}`: `ok`, `pr`, `format`, `url`, `placement`, `kept_unmarked` on success; `ok: false`, `exit`, `error` otherwise.

| exit | meaning | next |
|---|---|---|
| 0 | posted (or `--dry-run` printed a diff and saved the new body as `<take>.pr-body.md`) | |
| 2 | bad file or argument | |
| 4 | a `gh` read failed | check `gh auth status`; outside the repo, run from any directory inside it |
| 5 | `gh` is older than 2.99 (no `--attach`) | run the upgrade command it prints, then retry once |
| 6 | no PR found for the branch (gh's reason is in the message; a detached checkout has no branch) | pass `--pr N` if the PR exists (it works from any directory in the repo); else report the local paths, the PR skill posts later |
| 7 | the readback still shows a local path | retry once; then report the local paths |
| 8 | `gh pr edit` failed | report the error and the local paths |

No remote or no PR yet is not a failure: report the local `mp4`/`gif` paths and stop. The caller, or `open-pr` later, posts them.

## Report

Say which format was posted and why ("GIF: 9 s, plain clicks, cropped to the filter bar" or "MP4: 28 s, zoom on the totals table"), give the URL, list the local paths, and when `kept_unmarked` is above zero, say the PR now holds an older walkthrough below the new one, so the user can remove it. In `mode:pipeline`, return the same to the caller.
