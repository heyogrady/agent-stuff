# record-feature-video evals

Checks for `skills/record-feature-video`. They live outside the skill so an agent under test cannot read them.

| File | What it checks | Needs |
|---|---|---|
| `check-helpers.sh` | `post.sh` (where the take lands in a PR body, markers old and new, captions, readback, exits) and `pr-context.sh` (file kinds, verdicts, config lookup and fallback, credential warnings, port following), against the stub `gh` in `fake-gh/` and throwaway git repos | bash, git, jq, python3 |
| `check-recorder.sh` | `record.mjs` end to end against the fixture app in `fixtures/app`: lint, environment exits, rehearsal, takes (GIF, MP4, crop, cut, watchdog, SIGTERM), and the nono browser launcher run with `--no-jail` | node, ffmpeg, python3, jq, curl, and the recorder's Playwright |
| `skill-pack.md` | A hand-run behavioral comparison of two skill versions on real PRs | a project with a UI and a dev server |

Nothing here touches the network, uploads a file, edits a real PR, or changes a nono install: the launcher checks use a scratch install folder and a scratch git repo.

## Run

From the repo root:

```bash
/bin/bash evals/record-feature-video/check-helpers.sh        # ~20 s
bash skills/record-feature-video/scripts/setup.sh             # once: Playwright into ~/.cache/feature-recorder
bash evals/record-feature-video/check-recorder.sh             # ~2 min
```

`check-helpers.sh` runs the scripts under `BASH_UNDER_TEST` (default `/bin/bash`, which is bash 3.2 on macOS) to keep them portable. Pass check ids to run a subset (`check-helpers.sh P6c C19`); `KEEP=1` keeps the scratch folder for inspection. Each script's exit status is its number of failed checks.
