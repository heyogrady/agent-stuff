#!/usr/bin/env bash
# Deterministic checks for record-feature-video's recorder (record.mjs).
#
# Runs the real recorder, headless, against the fixture app in fixtures/app,
# served from a scratch copy on a free port. Every exit path must print a
# `RESULT {json}` last line, write <name>.result.json, and leave no frames
# behind. Needs node, ffmpeg, python3, jq, and the recorder's Playwright
# (scripts/setup.sh); exits 2 with nothing run without them.
#
# Usage: evals/record-feature-video/check-recorder.sh [check-id ...]
#   KEEP=1 keeps the scratch dir (outputs, stdout, stderr per check).
# Exit status: number of failed checks (0 = all pass). About two minutes.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPTS="$REPO/skills/record-feature-video/scripts"
REC="$SCRIPTS/record.mjs"
for tool in node ffmpeg python3 jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "check-recorder: needs $tool" >&2; exit 2; }
done
node -e 'import(process.argv[1]).then(m=>m.loadPlaywright("setup.sh"))' "$SCRIPTS/lib/env.mjs" 2>/dev/null \
  || { echo "check-recorder: Playwright missing; run: bash $SCRIPTS/setup.sh" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/feature-recorder-eval-XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
SERVER_PID=""; BROWSER_PIDS=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  for p in $BROWSER_PIDS; do kill "$p" 2>/dev/null; done
  if [ "${KEEP:-0}" = 1 ]; then echo "scratch: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

ONLY=" $* "
PASSED=0; FAILED=0
want() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }
report() {  # report <id> <pass|fail> <contract> [detail]
  if [ "$2" = pass ]; then PASSED=$((PASSED + 1)); printf 'PASS  %-4s %s\n' "$1" "$3"
  else FAILED=$((FAILED + 1)); printf 'FAIL  %-4s %s\n      -> %s\n' "$1" "$3" "${4:-}"; fi
}
check() {  # check <id> <contract> <detail> <test command...>
  local id="$1" contract="$2" detail="$3"; shift 3
  if "$@"; then report "$id" pass "$contract"; else report "$id" fail "$contract" "$detail"; fi
}

# --- fixture app, served from outside the repo -----------------------------

cp -R "$HERE/fixtures/app" "$WORK/app"
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
DEAD="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
(cd "$WORK/app" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER_PID=$!
for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:$PORT/plain.html" >/dev/null 2>&1 && break; sleep 0.1; done
mkdir -p "$WORK/shots"
for f in "$HERE"/fixtures/shots/*.json; do
  jq --arg u "http://127.0.0.1:$PORT" '.baseUrl = $u' "$f" > "$WORK/shots/$(basename "$f")"
done

# rec <id> <shot-list> [record.mjs args ...] — leaves $OUT, $ERR, $EXIT, $DIR,
# $RES (the RESULT json, or "{}").
rec() {
  local id="$1" shots="$2"; shift 2
  DIR="$WORK/$id"; mkdir -p "$DIR"; OUT="$DIR/stdout"; ERR="$DIR/stderr"
  node "$REC" --actions "$shots" --out "$DIR" --repo "$WORK" "$@" > "$OUT" 2> "$ERR"
  EXIT=$?
  RES="$(tail -n 1 "$OUT" | sed -n 's/^RESULT //p')"; [ -n "$RES" ] || RES="{}"
}
res() { printf '%s' "$RES" | jq -e "$1" >/dev/null 2>&1; }
no_frames() { ! ls -d "$DIR"/_frames-* >/dev/null 2>&1; }
has_result_file() { ls "$DIR"/*.result.json >/dev/null 2>&1; }
why() { printf 'exit %s; stderr: %s; RESULT: %.300s' "$EXIT" "$(tail -n 2 "$ERR" 2>/dev/null | tr '\n' ' ')" "$RES"; }
shot() {  # shot <name> <json> — writes a shot list into the scratch dir
  printf '%s' "$2" | jq --arg u "http://127.0.0.1:$PORT" '.baseUrl //= $u' > "$WORK/shots/$1.json"
  printf '%s' "$WORK/shots/$1.json"
}

# --- L: lint, before any browser -------------------------------------------

if want L1; then
  f="$(shot l1 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"click","selector":"#inc"},{"type":"eval","script":"document.querySelector(\"#name\").value=\"x\""}],"output":{"name":"l1"}}')"
  rec L1 "$f"
  check L1 "a take-time eval is rejected (exit 3) with the action that replaces it" "$(why)" \
    eval '[ "$EXIT" = 3 ] && res ".stage == \"lint\"" && res "any(.errors[]; test(\"type. with .clear: true\"))" && has_result_file'
fi

if want L2; then
  f="$(shot l2 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"goto","url":"/plain.html#x"},{"type":"click","selector":"#inc"}],"output":{"name":"l2"}}')"
  rec L2 "$f"
  check L2 "a jump right after mark says to move mark below it" "$(why)" \
    eval '[ "$EXIT" = 3 ] && res "any(.errors[]; test(\"move .mark. below this step\"))"'
fi

if want L3; then
  f="$WORK/shots/l3.json"
  printf '%s' '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"click","selector":"#inc","label":"x"}],"output":{"name":"l3"}}' > "$f"
  rec L3 "$f"
  check L3 "a relative url with no baseUrl is rejected; an unknown field is a warning naming the alternative" "$(why)" \
    eval '[ "$EXIT" = 3 ] && res "any(.errors[]; test(\"baseUrl\"))" && res "any(.warnings[]; test(\"use .note.\"))"'
fi

if want L5; then
  out="$(node --input-type=module -e '
    const { parseLsofCwd } = await import(process.argv[1]);
    console.log(JSON.stringify([parseLsofCwd("p1\nfcwd\nn/home/x/app\n"), parseLsofCwd("p1\nfcwd\nncwd|rtd info error: Operation not permitted\n")]));' "$SCRIPTS/lib/env.mjs")"
  check L5 "the dev-server cwd check reads a real path and fails soft on a sandbox error line" "$out" \
    [ "$out" = '["/home/x/app",null]' ]
fi

if want L6; then
  out="$(node --input-type=module -e '
    const { lint } = await import(process.argv[1]);
    console.log(JSON.stringify(lint({ viewport: { width: 1440, height: 1000 }, actions: [{ type: "mark" },
      { type: "click", selector: "role=row[name=/Q3 renewal/] td" }, { type: "click", selector: ["#a", "#b"] },
      { type: "spotlight", selector: ["#a", "#b"] }] })));' "$SCRIPTS/lib/lint.mjs")"
  q='(.errors|length) == 2 and any(.errors[]; contains("`role=row[name=/Q3 renewal/] >> td`"))
    and any(.errors[]; startswith("step 3") and contains("`spotlight` only")) and any(.warnings[]; contains("1.44:1"))'
  check L6 "lint: a space after role= is rejected naming the >> chain; a selector list is spotlight-only; an odd viewport aspect warns" "$out" \
    eval 'printf "%s" "$out" | jq -e "$q" >/dev/null'
fi

if want L7; then
  out="$(node --input-type=module -e '
    const { sheetTimes, endFrameTime } = await import(process.argv[1]);
    const spot = { type: "spotlight", t: 6, on: 6.7, off: 9.8, fade: 320, ms: 2800, out: 150 };
    const steps = [0.9, 2.6, 3.05, 4.9, 6.0];
    const t = sheetTimes({ take: [spot], steps, duration: 10.6 });
    const near = (x) => t.some((y) => Math.abs(y - x) < 0.25);
    const end = endFrameTime({ take: [spot], steps, duration: 10.6 });
    console.log(JSON.stringify({ n: t.length, spot: near(8.41), steps: steps.every((s) => near(s + 0.15)),
      end: end > 7.02 && end < 9.8, after: endFrameTime({ take: [spot], steps: [...steps, 10.2], duration: 10.6 }) }));' "$SCRIPTS/lib/finish.mjs")"
  check L7 "the contact sheet keeps 12 frames: inside every spotlight, then every step start (a 0.45 s beat included); the end frame sits inside a closing spotlight" "$out" \
    [ "$out" = '{"n":12,"spot":true,"steps":true,"end":true,"after":null}' ]
fi

# --- E: environment exits ---------------------------------------------------

if want E1; then
  f="$(shot e1 "$(jq --arg u "http://127.0.0.1:$DEAD" '.baseUrl=$u | .output.name="e1"' "$WORK/shots/gif-crop.json")")"
  rec E1 "$f"
  check E1 "nothing listening exits 4 before a browser starts" "$(why)" \
    eval '[ "$EXIT" = 4 ] && res ".stage == \"server\"" && res ".error | test(\"nothing is listening\")"'
fi

if want E2; then
  f="$(shot e2 "$(jq '.output.name="e2"' "$WORK/shots/gif-crop.json")")"
  DIR="$WORK/E2"; mkdir -p "$DIR"; OUT="$DIR/stdout"; ERR="$DIR/stderr"
  node "$REC" --actions "$f" --out "$DIR" --repo "$REPO" > "$OUT" 2> "$ERR"; EXIT=$?
  RES="$(tail -n 1 "$OUT" | sed -n 's/^RESULT //p')"; [ -n "$RES" ] || RES="{}"
  check E2 "a server running from another checkout exits 4 naming its directory" "$(why)" \
    eval '[ "$EXIT" = 4 ] && res ".error | test(\"not this repo\")"'
fi

if want E3; then
  node "$REC" > "$WORK/e3.out" 2>&1; EXIT=$?
  check E3 "no shot list exits 1 with usage" "exit $EXIT" \
    eval '[ "$EXIT" = 1 ] && grep -q usage "$WORK/e3.out"'
fi

# --- R: rehearsal -----------------------------------------------------------

if want R1; then
  rec R1 "$WORK/shots/misses.json" --rehearse
  check R1 "rehearsal continues past misses, diagnoses each with candidates or the covering element" "$(why)" \
    eval '[ "$EXIT" = 2 ] && res ".rehearse and (.misses|length) == 3" \
      && res "any(.misses[]; (.candidates // []) | index(\"#inc\"))" \
      && res "any(.misses[]; .why | test(\"covered by\"))" && no_frames'
fi

if want R2; then
  rec R2 "$WORK/shots/iframe-flow.json" --rehearse
  check R2 "iframe flow rehearses clean: drop file, refused text drop, hidden upload, paste, scrolls" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".ok and (.misses|length) == 0"'
fi

if want R3; then
  rec R3 "$WORK/shots/guided.json" --until 5
  check R3 "--until N stops after step N and screenshots it" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".steps == 5 and (.shots|length) == 1" && [ -s "$(printf "%s" "$RES" | jq -r ".shots[0]")" ]'
fi

if want R4; then
  f="$(shot r4 '{"actions":[{"type":"goto","url":"/app.html"},{"type":"mark"},
    {"type":"expect","selector":".row","count":60,"note":"3 hidden copies are not counted"},
    {"type":"click","selector":"role=button[name=\"Confirm\"]","note":"exists, display:none"},
    {"type":"click","selector":"#locked","expect":{"selector":"#count","text":"99"}},
    {"type":"spotlight","selector":["#row-3","#row-6"],"label":"Two rows apart","ms":400},
    {"type":"scroll","to":"#widget","block":"start","offset":-20},
    {"type":"spotlight","selector":"#widget","scrollIntoView":false,"ms":400},
    {"type":"spotlight","selector":"#shell","ms":400},
    {"type":"click","selector":"#nav-runs-label","note":"the wrapping link takes the hit"}],"output":{"name":"r4"}}')"
  rec R4 "$f" --rehearse --shots
  check R4 "rehearsal: a failed inline expect is the miss (not the now-disabled button); count skips hidden copies; a hidden role match says hidden; a spotlight list and a click through its wrapping link resolve; tall and half-covered spotlights warn; output is r4.rehearse.json and rehearse/*.png" "$(why)" \
    eval '[ "$EXIT" = 2 ] && res "(.misses|length) == 2 and (.misses|map(.step)) == [4,5]" \
      && res "any(.misses[]; .step == 4 and (.why|test(\"1 match exists but is hidden\")))" \
      && res "any(.misses[]; .step == 5 and (.why|test(\"^expect failed: #count .99. visible .saw 0 visible of 0 matches; #count reads .0.\")))" \
      && res "all(.misses[]; .why|test(\"disabled\")|not)" \
      && res "any(.warnings[]; test(\"step 9: spotlight target is .*taller than\"))" \
      && res "any(.warnings[]; test(\"step 8: spotlight top edge of #widget is hidden .covered by\"))" \
      && [ -f "$DIR/r4.rehearse.json" ] && [ ! -e "$DIR/r4.result.json" ] && [ "$(ls "$DIR"/rehearse/r4-step-*.png | wc -l | tr -d " ")" = 10 ]'
fi

# --- T: takes ---------------------------------------------------------------

if want T1; then
  rec T1 "$WORK/shots/gif-crop.json"
  check T1 "a short click-only take posts a cropped GIF under 10 MB, held to 5 s, an input value checked, frames cleaned" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".format == \"gif\" and .crop != null and .gifMB < 10 and .duration >= 4.9" \
      && [ -s "$(printf "%s" "$RES" | jq -r .post)" ] && no_frames'
fi

if want T2; then
  rec T2 "$WORK/shots/guided.json"
  check T2 "zoom + spotlight takes stay MP4, uncropped, with no pacing warnings" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".format == \"mp4\" and .zooms == 2 and .spotlights == 1 and .crop == null and (.warnings|length) == 0" \
      && [ -s "$(printf "%s" "$RES" | jq -r .sheet)" ] && [ -s "$(printf "%s" "$RES" | jq -r .endFrame)" ] && no_frames'
fi

if want T3; then
  rec T3 "$WORK/shots/canvas-crop.json"
  check T3 "a canvas redraw (invisible to the DOM) still drives the crop" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".crop != null"'
fi

if want T4; then
  rec T4 "$WORK/shots/iframe-flow.json"
  check T4 "the iframe flow take completes as an MP4 (navigation, so uncropped)" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".format == \"mp4\" and .crop == null" && no_frames'
fi

if want T5; then
  f="$(shot t5 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"click","selector":"#inc"},{"type":"click","selector":"#does-not-exist","timeout":1500}],"output":{"name":"t5"}}')"
  rec T5 "$f"
  check T5 "a failed take exits 2 with a failure screenshot and the rehearse hint, frames cleaned" "$(why)" \
    eval '[ "$EXIT" = 2 ] && res ".stage == \"take\" and .step == 4 and (.hint|test(\"rehearse\"))" \
      && [ -s "$(printf "%s" "$RES" | jq -r .failureShot)" ] && no_frames && has_result_file'
fi

if want T6; then
  f="$(shot t6 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"click","selector":"#inc"},{"type":"wait","ms":30000}],"output":{"name":"t6"}}')"
  rec T6 "$f" --max-seconds 6
  check T6 "the watchdog ends a stuck take with RESULT and no frames left" "$(why)" \
    eval '[ "$EXIT" = 2 ] && res ".stage == \"watchdog\"" && no_frames && has_result_file'
fi

if want T8; then
  f="$(shot t8 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"click","selector":"#inc"},{"type":"cut","url":"/app.html#runs","label":"Meanwhile, on the Runs page"},{"type":"click","selector":"#inc"}],"output":{"name":"t8"}}')"
  rec T8 "$f" --keep-frames
  check T8 "a labelled cut plays a title card, stays uncropped, and raises no lint warning" "$(why)" \
    eval '[ "$EXIT" = 0 ] && res ".crop == null and (.warnings | map(select(test(\"cut\"))) | length) == 0"'
  f="$(shot t8b '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"cut","url":"/app.html"}],"output":{"name":"t8b"}}')"
  rec T8b "$f" --rehearse
  check T8b "a cut with no label is warned about" "$(why)" eval 'res "any(.warnings[]; test(\"no .label.\"))"'
fi

if want T9; then
  f="$(shot t9 '{"actions":[{"type":"goto","url":"/app.html"},{"type":"mark"},{"type":"scroll","to":"#row-40","expect":{"selector":"#row-40","state":"visible"}},{"type":"scroll","container":"#main","to":"top"},{"type":"click","selector":"#inc"}],"output":{"name":"t9"}}')"
  rec T9 "$f"
  check T9 "scroll works on a top-level page with no iframe" "$(why)" eval '[ "$EXIT" = 0 ]'
fi

if want T10; then
  f="$(shot t10 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"move","x":300,"y":200,"ms":700},
    {"type":"click","selector":"#inc"},{"type":"spotlight","selector":"#widget","label":"Counted","ms":3400}],"output":{"name":"t10"}}')"
  rec T10 "$f"
  at() { grep -E "^\[$1/" "$OUT" | sed -E 's/.*t\+([0-9.]+)s.*/\1/'; }
  yavg() { ffmpeg -hide_banner -i "$1" -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null - 2>&1 | sed -n 's/.*YAVG=//p' | head -n 1; }
  END="$(printf "%s" "$RES" | jq -r .endFrame)"; LAST="$DIR/last.png"
  ffmpeg -v error -y -sseof -0.2 -i "$(printf "%s" "$RES" | jq -r .mp4)" -frames:v 1 -update 1 "$LAST" 2>/dev/null
  M3="$(at 3)"; M4="$(at 4)"; YE="$(yavg "$END")"; YL="$(yavg "$LAST")"
  check T10 "the take opens at rest (~0.9 s lead-in), a 700 ms move takes 700 ms, a long spotlight warns on its on-screen time, and the end frame is inside the closing spotlight" "move at t+$M3, click at t+$M4, end-frame luma $YE vs last $YL; $(why)" \
    eval '[ "$EXIT" = 0 ] && awk -v a="$M3" -v b="$M4" -v e="$YE" -v l="$YL" "BEGIN { exit !(a >= 0.8 && b - a >= 0.65 && e < l - 20) }" \
      && res "any(.warnings[]; test(\"is on screen 3.[89]s .fades included\"))"'
fi

if want T7; then
  f="$(shot t7 '{"actions":[{"type":"goto","url":"/plain.html"},{"type":"mark"},{"type":"click","selector":"#inc"},{"type":"wait","ms":30000}],"output":{"name":"t7"}}')"
  DIR="$WORK/T7"; mkdir -p "$DIR"; OUT="$DIR/stdout"; ERR="$DIR/stderr"
  node "$REC" --actions "$f" --out "$DIR" --repo "$WORK" > "$OUT" 2> "$ERR" &
  pid=$!
  for _ in $(seq 1 100); do grep -q 't+' "$OUT" 2>/dev/null && break; sleep 0.2; done
  sleep 1; kill -TERM "$pid"; wait "$pid"; EXIT=$?
  RES="$(tail -n 1 "$OUT" | sed -n 's/^RESULT //p')"; [ -n "$RES" ] || RES="{}"
  check T7 "SIGTERM mid-take exits 143 with RESULT, closes the browser, cleans frames" "$(why)" \
    eval '[ "$EXIT" = 143 ] && res ".stage == \"interrupted\"" && no_frames'
fi

# --- X: inside nono, the session's browser launcher (run here without nono) -

# An install folder like nono-setup.sh's, using the recorder's own Playwright,
# and a git repo whose git dir receives the launcher's token file.
NH="$WORK/nono-home"; XR="$WORK/xrepo"
mkdir -p "$NH" "$XR"
cp "$SCRIPTS"/nono/* "$NH/"
printf '%s\n' "${FEATURE_RECORDER_HOME:-$HOME/.cache/feature-recorder}" > "$NH/playwright-dir"
node -p 'process.execPath' > "$NH/node-path"
git -c init.templateDir= init -q "$XR"
TOKF="$XR/.git/feature-recorder.json"
# launcher_up: start one for $XR with --no-jail, wait for its token file.
launcher_up() {
  node "$NH/launcher.mjs" --workdir "$XR" --session eval --no-jail >> "$WORK/launcher.log" 2>&1 &
  BROWSER_PIDS="$BROWSER_PIDS $!"
  for _ in $(seq 1 50); do [ -s "$TOKF" ] && return 0; sleep 0.1; done
  return 1
}
lcall() {  # lcall <method> <route> [json] [token]: prints "<status> <body>"
  local t="${4:-$(jq -r .token "$TOKF")}"
  curl -s -o "$WORK/lcall.body" -w '%{http_code}' -X "$1" -H "x-recorder-token: $t" -H 'content-type: application/json' \
    ${3:+--data "$3"} "http://127.0.0.1:$(jq -r .port "$TOKF")$2"
  printf ' %s' "$(cat "$WORK/lcall.body")"
}
xrec() {  # xrec <id> <shot-list> [record.mjs args ...]: as rec, but "inside nono"
  local id="$1" shots="$2"; shift 2
  DIR="$WORK/$id"; mkdir -p "$DIR"; OUT="$DIR/stdout"; ERR="$DIR/stderr"
  NONO_CAP_FILE=x FEATURE_RECORDER_NONO_HOME="$NH" node "$REC" --actions "$shots" --out "$DIR" --repo "$XR" "$@" > "$OUT" 2> "$ERR"
  EXIT=$?
  RES="$(tail -n 1 "$OUT" | sed -n 's/^RESULT //p')"; [ -n "$RES" ] || RES="{}"
}
jq '.allowForeignServer = true' "$WORK/shots/guided.json" > "$WORK/shots/x-guided.json"
jq '.allowForeignServer = true | .launchArgs = ["--no-sandbox", "--use-angle=swiftshader"]' "$WORK/shots/guided.json" > "$WORK/shots/x-args.json"

if want X1 || want X2 || want X3; then launcher_up || echo "launcher did not start: $(tail -n 3 "$WORK/launcher.log")"; fi

if want X1; then
  xrec X1 "$WORK/shots/x-args.json"
  AFTER="$(lcall GET /health)"
  check X1 "inside nono the recorder gets a browser of the shot list's size from the launcher, drops non-SwiftShader launchArgs with a warning, and hands the browser back" "health after: $AFTER; $(why)" \
    eval '[ "$EXIT" = 0 ] && res ".size == \"1920x1200\" and any(.warnings[]; test(\"ignored --no-sandbox$\"))" && [[ "$AFTER" == *"\"browser\":null"* ]] && no_frames'
fi

if want X2; then
  A="$(lcall POST /browser '{"width":1440,"height":900,"dsf":1}' "nottheToken0000000000000000000000000000000000000")"
  B="$(lcall POST /browser '{"width":1440,"height":900,"dsf":2,"args":["--renderer-cmd-prefix=/bin/sh"]}')"
  C="$(lcall POST /browser '{"width":1440,"height":900,"dsf":1.5}')"
  D="$(lcall POST /browser '{"width":"1440","height":900,"dsf":2}')"
  E="$(lcall POST /browser '{"width":1440,"height":900,"dsf":2,"gl":"--x"}')"
  check X2 "the launcher refuses a wrong token, any field but width/height/dsf/gl, and non-numeric or out-of-range values" "$A | $B | $C | $D | $E" \
    eval '[[ "$A" == 403* ]] && [[ "$B" == "400 "*"unknown field(s): args"* ]] && [[ "$C" == 400* ]] && [[ "$D" == 400* ]] && [[ "$E" == 400* ]]'
fi

if want X3; then
  CDP="$(lcall POST /browser '{"width":1440,"height":900,"dsf":2}' | sed -n 's/^200 .*"cdp":"\([^"]*\)".*/\1/p')"
  jq '.deviceScaleFactor = 1' "$WORK/shots/guided.json" > "$WORK/shots/x3.json"
  rec X3 "$WORK/shots/x3.json" --cdp "$CDP"
  lcall DELETE /browser >/dev/null
  check X3 "a running browser whose frame size differs from the shot list is refused, naming the size it needs" "cdp $CDP; $(why)" \
    eval '[ -n "$CDP" ] && [ "$EXIT" = 2 ] && res ".stage == \"launch\"" && grep -q "renders 2880x1800" "$OUT" "$ERR" && grep -q -- "--force-device-scale-factor=1" "$OUT" "$ERR"'
fi

if want X4; then
  for p in $BROWSER_PIDS; do kill "$p" 2>/dev/null; done; BROWSER_PIDS=""; sleep 0.5
  xrec X4a "$WORK/shots/x-guided.json"; A_EXIT="$EXIT"; A="$(cat "$ERR")"
  NH_REAL="$NH"; NH="$WORK/not-installed"; xrec X4b "$WORK/shots/x-guided.json"; NH="$NH_REAL"
  check X4 "inside nono with no launcher, it exits 2 and says how to start one; with nothing installed, it exits 1 naming nono-setup.sh" "installed: $A_EXIT $(printf '%s' "$A" | head -c 160); not: $EXIT $(head -c 160 "$ERR")" \
    eval '[ "$A_EXIT" = 2 ] && grep -q "launcher.mjs --workdir $XR" <<<"$A" && [ "$EXIT" = 1 ] && grep -q "nono-setup.sh" "$ERR"'
fi

if want X5; then
  rm -f "$TOKF"
  (cd "$XR" && NONO_SESSION_ID=evalhook bash "$NH/hook-before.sh"); HB=$?
  for _ in $(seq 1 50); do [ -s "$TOKF" ] && break; sleep 0.1; done
  UP="$( [ -s "$TOKF" ] && [ -s "$NH/sessions/evalhook.pid" ] && echo yes || echo no)"
  LPID="$(cat "$NH/sessions/evalhook.pid" 2>/dev/null)"
  (cd "$XR" && NONO_SESSION_ID=evalhook bash "$NH/hook-after.sh")
  for _ in $(seq 1 30); do kill -0 "$LPID" 2>/dev/null || break; sleep 0.1; done
  GONE="$(kill -0 "$LPID" 2>/dev/null && echo no || echo yes)"
  check X5 "the session hooks start a launcher for the session's folder and stop it after, removing its token and pid files" "before exit $HB, up $UP, gone $GONE, token left $([ -e "$TOKF" ] && echo yes || echo no)" \
    eval '[ "$HB" = 0 ] && [ "$UP" = yes ] && [ "$GONE" = yes ] && [ ! -e "$TOKF" ] && [ ! -e "$NH/sessions/evalhook.pid" ]'
fi

echo
echo "$PASSED passed, $FAILED failed"
exit "$FAILED"
