# Context: what to film, where, and as whom

## The digest

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
bash "$SKILL_DIR/scripts/pr-context.sh" [PR]
```

With no PR number it uses the current branch's PR, or, with no PR yet, the branch and its base. One call prints the PR, the ticket key from the branch name, `CONFIG:` when the worktree has no config file and the main checkout's is used, `FEATURE_VIDEO:` (the file the block came from and the knobs it sets), any `WARNING:` about credentials, `DEV_SERVER` (the localhost ports served from this worktree), `BASE_URL` (`feature_video.base_url`, moved onto this worktree's port when it serves exactly one other than config's, or `not configured (pass a base URL)`: the script takes no base URL, so your argument decides), the changed files by kind, the UI files, the PR body (`BODY:`) up to its first image, video, or `<details>` (40 lines at most, so the claims list needs no separate `gh pr view`), and a verdict:

- `VERDICT: SKIP (<reason>)`: no UI-facing file changed, or `feature_video.enabled` is false. Stop with `video skipped: <reason>`, unless the files were the reason and the PR body or ticket says the point of the change is visible in the app (a backend fix that changes what a page shows); then film that page.
- `VERDICT: FILM`: continue. A `hint:` line means no component changed (only logic or fixtures); find the screen that renders the named modules before writing the shot list.

Read only what the shot list needs: the ticket's acceptance criteria and the 3–5 UI files that render the routes and controls you will touch. The demo should show each change the PR claims, visibly met, not tour the app.

## Config

The `feature_video:` block in the YAML frontmatter of `agent-stuff.local.md` (personal, git-ignored) at the repo root, else of `agent-stuff.md` (tracked, team defaults). A `feature_video:` block in the local file replaces the tracked one whole. A worktree with neither file reads the main checkout's and the digest says so on a `CONFIG:` line; inside nono the main checkout is out of reach, so the worktree needs its own copy (a link does not work there).

```yaml
feature_video:
  enabled: true                                   # false: skip with a one-line reason
  base_url: http://localhost:3750
  dev_server: { command: "bin/dev", port: 3750 }  # optional: becomes the shot list's devServer
  format: auto                                    # auto | gif | mp4: the shot list's format
  gif_max_seconds: 12                             # auto picks a GIF up to this length: gifMaxSeconds
  auto_post: true                                 # false: leave the file and print the post command
  review_dir: tmp/feature-videos                  # optional: copy the take here for review; default: print its path
  viewport: { width: 1440, height: 900 }
  username: admin@example.test                    # for sign-in steps before `mark`
  password: <dev-only password>
  cookies_file: tmp/staging-cookies.json          # optional: a Playwright cookie array
  storage_state: tmp/auth-state.json              # optional: Playwright storageState
```

**Credentials.** The digest runs `git check-ignore -q` on the file that supplies `password`, `cookies_file`, or `storage_state`, and on the cookie and state files themselves, and prints a `WARNING:` line for each one that is not ignored; pass it on before using those values, because that file could be committed.

The base URL is the argument, else the digest's `BASE_URL`, else ask (in `mode:pipeline`: `video skipped: no base URL`). Worktree tools that give each worktree its own port need no config change: `BASE_URL` follows the port this worktree serves. On `DEV_SERVER: none running from this worktree`, start its server with the project's usual command in the background, let that command pick the port, and run the digest again.

**The dev server must serve this branch.** The recorder refuses a localhost server running from another checkout (exit 4), because a take of a stale build looks clean. If another worktree holds the usual port, start this worktree's server on a free port, or put `devServer` in the shot list so the recorder starts it and stops it afterwards. Before the take, an `expect` on something only this branch renders is the cheapest stale-build check.

**Sign-in**, in order of preference:
1. `storageState`, or `cookiesFile` pointing at a file named in config.
2. Sign-in steps before `mark`, so they stay out of the video.
3. Ask. In `mode:pipeline`: `video skipped: sign-in required, no credentials configured`.

Never write credentials, cookies, or tokens into the repo, the PR, or any note you leave. Keep shot lists under `/tmp/feature-video-$(id -u)/`. Keep secrets off the screen: no settings pages that show tokens, no unredacted customer data.

## In a nono sandbox

Without nono, skip this section: the recorder launches its own browser.

When `NONO_CAP_FILE` is set the session runs inside [nono](https://github.com/nolabs-ai/nono), where Chromium cannot start. The agent's sandbox stays as it is; each take's browser runs beside it, in a sandbox of its own, and the recorder handles that by itself:

- **Once per machine**, the user runs `bash "$SKILL_DIR/scripts/nono-setup.sh"` outside the sandbox, right after installing or updating the skill. It installs a launcher, Playwright and Chromium into `~/.local/share/feature-recorder` (readable from the sandbox, never writable), and adds session hooks to `~/.config/nono/profiles/personal.json`, nono's per-user profile, that start a launcher with each session and stop it after. An existing `personal.json` keeps whatever profile it extends (the one the user's nono wrapper uses); a new one extends `--extends <profile>`, default `claude-code`.
- **Each take**, the recorder asks this session's launcher for a browser of the shot list's size, records, and hands it back. That browser reads only its install folder and reaches only the localhost ports and hosts the agent's sandbox reaches. It takes no Chromium flags: of `launchArgs`, only the SwiftShader ones (software WebGL) count, and the rest are dropped with a warning.
- **When it fails**, the recorder prints what to do: run `nono-setup.sh` (exit 1), or start a new session through the nono wrapper, or run the launcher by hand (exit 2). Pass that to the user. In `mode:pipeline`: `video skipped: <that line>`.
- **Ports and hosts.** The launcher reads the same allow-lists a nono wrapper script typically passes to `nono run` (`--open-port`, `--allow-domain`): `.nono-ports` and `.nono-domains` in the worktree, and `~/.config/nono/extra-ports` and `extra-domains`. `nono-setup.sh` adds the launcher's ports (47810-47829) to `extra-ports`, so the wrapper must open the ports in that file. Both read the lists once at start: a new dev-server port or staging host means a new session.
- The dev-server ownership check falls back to a warning when the sandbox hides other processes.
