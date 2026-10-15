# The shot list (`record.mjs` contract)

One JSON file. This page is the whole option set; do not read `record.mjs` to discover more. Paths in it (`file`, `cookiesFile`, `storageState`, `filePicker`) resolve against the shot list's own folder.

```json
{
  "baseUrl": "http://localhost:5177",
  "frames": { "app": "iframe#app" },
  "actions": [
    { "type": "goto", "url": "/runs" },
    { "type": "waitFor", "frame": "app", "selector": "[data-testid=runs-table]" },
    { "type": "mark" },
    { "type": "wait", "ms": 900 },
    { "type": "click", "frame": "app", "selector": "button", "hasText": "New run",
      "expect": { "frame": "app", "selector": "form#new-run" } },
    { "type": "type", "frame": "app", "selector": "input[name=title]", "text": "Q3 renewal" },
    { "type": "click", "frame": "app", "selector": "button[type=submit]" },
    { "type": "spotlight", "frame": "app", "selector": ".flash", "label": "Run queued" }
  ],
  "output": { "name": "pr-812-new-run" }
}
```

## Setup, the take, and the mouse rule

`mark` starts the capture, and the take opens on the page at rest for `leadInMs` (900) before the first action (a leading `wait` or spotlight counts toward it). Everything before `mark` is setup and never appears: sign-in, routing to the start page, seeding data, `eval` tweaks, `css` to hide dev toolbars. Without a `mark`, the take starts at the first step that is not `goto`, `hash`, `eval`, `waitFor`, `expect`, or `css`.

From `mark` on, the cursor does everything. `goto`, `hash`, and `eval` during the take are rejected (exit 3), and the message names the action that replaces each one:

| The script was… | Use |
|---|---|
| navigating (`goto`, `hash`, `location`, `pushState`) | `click` the link a user would use |
| dispatching drag/drop events | `drop` |
| dispatching paste | `paste` |
| setting `.value` | `type` with `clear: true`, or `select` |
| calling `.click()` | `click` |
| scrolling | `scroll` or `scrollTo` |
| restyling | `css` |

When no user path reaches a state (a deep link from an email), use `cut`: a short fade to a new scene. `"allowNoCursor": "<why>"` on a step is the last resort.

## Actions

Every cursor action moves a visible cursor along an eased arc (`ms`, default 900), checks that the point really reaches the target (not covered by a sticky header, overlay, or the parent page), then acts. Any action accepts `frame`, `selector`, `hasText`, `nth`, `timeout`, `after` (ms to hold afterwards), `note`, `force` (skip the reachability check), and `expect`. Pointing actions (`click`, `type`, `hover`, `move`) also take `xFrac`/`yFrac` (0–1 across the box) or `offsetX`/`offsetY` (px from its top-left): aim off-centre so the cursor does not sit on text the clip must show.

`selector` is any Playwright selector: CSS (`#orders:focus` for focus), `role=button[name="Save"]`, `text=Export`, `:has-text("All")`, `xpath=..`, and chains (`role=navigation[name="Report"] >> role=button[name="Orders"]`). After a `role=` selector, step down with ` >> ` (`role=row[name=/Q3/] >> td`), never a space: lint rejects the space form (exit 3). With `hasText` it keeps the matches containing that text; `nth` picks one (default the first).

The recorder moves the cursor off a spotlight's target, and off the changed region before the closing hold, onto empty page where it can, so it never covers the proof or rests on a label. A click on a target wrapped by its own control (an icon inside a link or button) counts as reaching it.

| type | fields (default) | |
|---|---|---|
| `click` | `xFrac`/`yFrac` or `offsetX`/`offsetY`, `pause` (220), `after` (600) | warns when the control is disabled |
| `type` | `text`, `clear`, `delay` (55 ms/char) | clicks into the field, then types; without `clear: true` it appends to what the field holds |
| `paste` | `text`, `clear` | a real `paste` event first; text is inserted only if the app ignores it |
| `select` | `option` or `label` (visible text), or `value` | native `<select>` |
| `upload` | `file` or `files`, `via` | `selector` is the file input (hidden is fine); the cursor goes to `via`, else its `<label>` or the enclosing dropzone |
| `drop` | `file`/`files` or `text`, `leave`, `hold` (900) | drags a badge onto the target, firing dragenter/dragover/drop; `leave: true` ends in dragleave (a refusal) |
| `hover` | `hold` (800) | |
| `move` | `selector`, or `x` and `y` | |
| `down` / `up` | | with `move` between them: a drag |
| `press` | `key` (`Enter`, `Escape`, `Tab`) | |
| `scroll` | `to` (a selector, `"top"`, `"bottom"`), `block` (`center`/`start`/`end`), `offset` (CSS px; positive lands the target that much lower), `container`; or `y`/`x` px with `selector` as the pane | the cursor moves into the pane, wheels, then a smooth correction. `block` is measured below the pane's `scroll-padding-top`, else below a sticky or fixed header at its top, so `start` never lands under it |
| `scrollTo` | `scrollMs` | scrolls only if the element is off screen (clicks do this already, as a smooth page scroll with the cursor still: when the viewer should see the scroll, put a `scroll` before the click); to align an on-screen element, use `scroll` with `to` and `block` |
| `spotlight` | `label`, `ms` (2800), `delay` (700), `position` (`auto` picks the side with room; `top`/`bottom`/`left`/`right`), `padding` (10) | dims everything else. `selector` may be a list (`["#row-3", "#row-9"]`): the box around all of them is lit, the first match of each, with no `hasText` or `nth`. Warns when the target is taller than the viewport or its top edge is hidden (under a sticky header). The label is sized to read at GitHub's ~900 px player, so keep it to one sentence; it fades out in 150 ms, before the next step starts |
| `zoom` | `ms` (2500) or `stay: true`, `scale` (auto-fit, max 2.5), `padding` (40), `ease` (700) | a camera move in post; a second zoom pans straight there |
| `zoomOut` | `ease` | ends a `stay` zoom |
| `cut` | `url`, `hash`, or `script`; `label`; `fade` (350), `color` | a deliberate scene change behind a title card: `label` says where we are going ("A run with no orders"); without one it reads as a glitch |
| `wait` | `ms` | |
| `waitFor` | `state` (`visible`), `settle` (300) | waits on the app, not the clock |
| `expect` | `selector` and/or `text`, `state` (`visible` `hidden` `attached` `detached` `enabled` `disabled` `checked`), `count` | `text` narrows the matches; `state` is checked on the first match, `count` counts the visible ones (a hidden copy is not counted). Fails the run (8 s) when the build or data is not what the shot list assumes |
| `css` | `css`, `id`; or `remove: "<id>"` | allowed during the take |
| `mark` | | |
| setup: `goto` `url` `waitUntil` `settle` (1200), `hash` `value`, `eval` `script` | | |

`frame: "<name>"` resolves inside the iframe that `frames.<name>` names; boxes map to the page, so the cursor lines up. An `expect` field on any action checks right after it; use it on each step whose result the story depends on.

## Top-level options

| key | default | |
|---|---|---|
| `baseUrl` | | an origin, required when a `goto`/`cut` url is relative; put a query or hash (`/?fake=1#/runs`) in the first `goto` |
| `viewport` | 1440×900 | an uncropped take has its aspect; lint warns outside 1.5–1.9:1 |
| `deviceScaleFactor` | 2 | capture resolution |
| `format` | `auto` | GIF when the take is ≤ `gifMaxSeconds` (12) with no zoom and no spotlight; otherwise MP4. A GIF that will not fit 9.5 MB at 720 px falls back to MP4. `gif`/`mp4` force it. Set from the `format:` argument, else `feature_video.format` and `gif_max_seconds` |
| `crop` | `auto` | crops to everything the take touched (spotlight labels included) plus everything the app changed (canvas redraws and content pushed by an insert included) when that is ≤ `cropMaxShare` (0.7) of the frame and nothing navigated, scrolled, cut, or zoomed. `off`, or `{x, y, width, height}` in CSS px; any crop keeps at least 360×220 and an aspect no wider than about 2.5:1 |
| `cropPadding` | 48 | |
| `output` | `{name: "feature-demo", width: 1920, crf: 20}` | written to `<shots dir>/out/` unless `--out` or `output.dir` |
| `cookies`, `cookiesFile`, `storageState` | | auth before the first step |
| `devServer` | | `{command, cwd, port, ready, timeoutMs}`: start this worktree's server for the run and stop it afterwards; a running server from this repo is reused |
| `allowForeignServer` | false | accept a localhost server running from another checkout |
| `filePicker` | | answers any file chooser |
| `styleTag` | | CSS injected after every `goto` |
| `launchArgs` | | e.g. `--use-gl=swiftshader` for WebGL maps headless; ignored with `cdp`, and inside nono only the SwiftShader flags count |
| `cdp` | | drive a running browser instead of launching one: a port or URL (also `--cdp P`, `FEATURE_VIDEO_CDP`). Inside nono the recorder gets one from the session's launcher by itself (`context.md`) |
| `timezoneId`, `locale`, `proxy` | | `proxy: false` ignores `HTTPS_PROXY` |
| `maxSeconds` | 300 | watchdog for the whole run |
| `rehearseTimeout` | 4000 | per-step wait in rehearsal; a step's own `timeout` wins |
| `tailMs` | 1600, or 500 after a closing spotlight | hold on the end state; a plain take is held until it lasts `gifMinSeconds` (5) |
| `leadInMs` | 900 | the page at rest at the start of the take; `0` turns it off |
| `headless` | true | |

## Running it

```
node record.mjs <shots.json> --rehearse            # every step fast, no capture; lists every miss
node record.mjs <shots.json> --until 6             # rehearse to step 6, screenshot it (a spotlight step with its label up)
node record.mjs <shots.json> --rehearse --shots    # screenshot after every step, once fades settle
node record.mjs <shots.json>                       # the take
```

Also: `--out DIR`, `--max-seconds N`, `--keep-frames`, `--cdp P`, and `--repo DIR`, the worktree whose dev server the take must film (default: the shot list's repo, else the cwd's; pass it when both are outside the repo).

The last stdout line is always `RESULT {json}`, also saved as `<name>.result.json`; a rehearsal's is `<name>.rehearse.json`, its screenshots under `out/rehearse/`, so nothing it writes is mistaken for the take's.
- A take: `ok`, `post` (the file to post), `format`, `mp4`, `gif`, `sheet` (12 frames: one inside every spotlight, then each step's start, then even fill), `endFrame` (inside the closing spotlight, label up, when the take ends on one; else the last frame), `duration`, `size`, `crop`, `cropWhy`, `zooms`, `spotlights`, `warnings`.
- A rehearsal: `ok`, `misses` (`step`, `action`, `why`, `candidates`), `shots`, `warnings`.
- A failure: `ok: false`, `stage`, `step`, `error`, and for a take `failureShot` and `hint`.

| exit | meaning | next |
|---|---|---|
| 0 | done | |
| 1 | usage, or Playwright missing | run `setup.sh` |
| 2 | a step failed, a rehearsal missed, the watchdog fired, or the browser would not launch | fix every listed miss, rehearse again |
| 3 | lint rejected the shot list | each error names the fix |
| 4 | the dev server is not running or runs from another checkout | start this worktree's server, or add `devServer` |
| 130/143 | interrupted | |

## Pacing

- After `mark`, act within a second. Between actions, the defaults are already paced; add `wait` only where the viewer must read something.
- Wait on state (`waitFor`, `expect`) rather than guessing with `wait`.
- End on the result: a spotlight for an MP4, the `tailMs` hold for a GIF.
- As short as the claims allow: about 5–10 s for a one-claim GIF, about 6–8 s per labelled beat in an MP4. The recorder warns about still stretches over 3 s, a spotlight on screen over 3.5 s (fades included; the default is about 3.3 s), and takes over 45 s.

## Common misses

- **spotlight taller than the viewport** (or its top under a sticky header): spotlight the inner element that holds the proof, not its whole section.
- **covered by `<…>`**: scroll the target clear of the sticky element (`scroll` with `to`; `block: "start"` already clears a sticky header, `offset` adds room), or close the overlay first.
- **N match(es) exist but are hidden**: the element is collapsed, on another tab, or gated behind a form value; add the step that reveals it. (A `role=` selector never matches hidden elements; the diagnosis checks for them anyway.)
- **no match**: take one of the listed `candidates`. Prefer `data-testid`, `name`, `aria-label`, or `hasText` over CSS paths, and stable text over generated IDs (fake data can mint new IDs on every load).
- **expect failed** (`saw N visible of M`, and what the element reads): the build or data differs from what the shot list assumes. Check that the dev server serves this branch before changing the shot list. An expect attached to a step is reported as the miss itself, even when the step's control has since disabled itself.
- **expect selector is invalid**: a Playwright syntax error in the shot list, not the build.
- **Stateful steps** (submit, delete): rehearsal performs them too, so reset the data before the take, or end rehearsal with `--until` before them.
