#!/usr/bin/env bash
# Deterministic checks for record-feature-video's helper scripts.
#
# Runs the real scripts/post.sh and scripts/pr-context.sh against the fake gh
# in fake-gh/ (no network, no uploads) and throwaway git repos. The fake gh
# rewrites attached paths the way gh v2.102.0 does (see the fake's header).
# The scripts run under BASH_UNDER_TEST (default /bin/bash, which is 3.2 on
# macOS) to pin bash 3.2 portability.
#
# Usage: evals/record-feature-video/check-helpers.sh [check-id ...]
#   KEEP=1 keeps the scratch dir (each check's body, stdout, stderr, argv log).
# Exit status: number of failed checks (0 = all pass).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPTS="$REPO/skills/record-feature-video/scripts"
POST="$SCRIPTS/post.sh"
CTX="$SCRIPTS/pr-context.sh"
FAKE="$HERE/fake-gh"
BASH_UT="${BASH_UNDER_TEST:-/bin/bash}"
[ -x "$BASH_UT" ] || BASH_UT="$(command -v bash)"
for tool in jq python3 git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "check-helpers: needs $tool" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/feature-video-eval-XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
if [ "${KEEP:-0}" = 1 ]; then echo "scratch: $WORK"; else trap 'rm -rf "$WORK"' EXIT; fi

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

# --- post.sh harness -------------------------------------------------------

# post_case <id> <body> [VAR=value ...] -- [post.sh args ...]
# Runs post.sh from the check dir with the fake gh serving PR 42 from $BODYF.
# Leaves $D, $BODYF, $ARGV, $OUT, $ERR, $EXIT for the assertions. The dir holds
# demo-take.gif, take.mp4, "screen shot.png", and notes.txt.
post_case() {
  local id="$1" body="$2"; shift 2
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  D="$WORK/$id"; mkdir -p "$D"
  BODYF="$D/body.md"; ARGV="$D/argv.log"; OUT="$D/stdout"; ERR="$D/stderr"
  printf '%s' "$body" > "$BODYF"
  printf 'GIF89a' > "$D/demo-take.gif"; printf 'mp4' > "$D/take.mp4"
  printf 'png' > "$D/screen shot.png"; printf 'txt' > "$D/notes.txt"
  (cd "$D" && env PATH="$FAKE:$PATH" FAKE_GH_PR=42 FAKE_GH_BODY="$BODYF" \
    FAKE_GH_ARGV_LOG="$ARGV" ${envs[@]+"${envs[@]}"} "$BASH_UT" "$POST" "$@") > "$OUT" 2> "$ERR"
  EXIT=$?
}

posted() { tail -n 1 "$OUT" | sed -n 's/^POSTED //p' | jq -e "$1" >/dev/null 2>&1; }
edited() { grep -q '^gh pr edit .*--body-file' "$ARGV" 2>/dev/null; }
line_no() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }   # line_no <file> <fixed text>
count() { grep -cF -- "$2" "$1"; }                               # count <file> <fixed text>
nth() { sed -n "${2}p" "$1"; }                                    # nth <file> <n>
MARK='<!-- feature-video -->'
ASSET='https://github.com/user-attachments/assets/'
why() { printf 'exit %s; %s; last: %s' "$EXIT" "$(tail -n 1 "$ERR" 2>/dev/null)" "$(tail -n 1 "$OUT" 2>/dev/null)"; }

# --- P1-P3: refuse early, with a reason ------------------------------------

if want P1; then
  post_case P1 $'Summary.\n' FAKE_GH_VERSION=2.98.0 -- demo-take.gif
  check P1 "gh older than 2.99 exits 5 with an upgrade command and never edits" "$(why)" \
    eval '[ "$EXIT" = 5 ] && grep -q "gh 2.98.0 lacks --attach; run: " "$ERR" && posted ".ok==false and .exit==5" && ! edited'
fi

if want P2; then
  post_case P2 $'Summary.\n' FAKE_GH_NO_ATTACH=1 -- demo-take.gif
  check P2 "a gh whose pr edit has no --attach exits 5 whatever its version" "$(why)" \
    eval '[ "$EXIT" = 5 ] && grep -q "lacks --attach" "$ERR" && posted ".ok==false" && ! edited'
fi

if want P3; then
  post_case P3 $'Summary.\n' FAKE_GH_PR= -- demo-take.gif
  check P3 "no PR for the branch exits 6 with gh's reason and the --pr N way out" "$(why)" \
    eval '[ "$EXIT" = 6 ] && grep -qi "no PR" "$ERR" && grep -qF "(gh: no pull requests found for branch" "$ERR" && grep -qF "pass --pr N" "$ERR" && posted ".ok==false and .exit==6 and (.error|test(\"no PR\"))" && ! edited'
fi

# --- P4-P8: where the embed lands -----------------------------------------

# post_again [post.sh args ...]: run post.sh again in the same check dir, on the
# body the last run left (the fake gh keeps its asset counter). Updates $EXIT.
post_again() {
  (cd "$D" && env PATH="$FAKE:$PATH" FAKE_GH_PR=42 FAKE_GH_BODY="$BODYF" FAKE_GH_ARGV_LOG="$ARGV" \
    "$BASH_UT" "$POST" "$@") > "$OUT" 2> "$ERR"
  EXIT=$?
}
ENDM='<!-- /feature-video -->'
body() { tr '\n' '|' < "$BODYF"; }

if want P4; then
  post_case P4 $'Adds a filter bar to orders.\nIt remembers the last filter.\n\n## Changes\n\n- a\n' -- demo-take.gif
  check P4 "a GIF goes in after the summary as one marked block: marker, image (filename alt), end marker" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(sed -n 3,10p "$BODYF" | tr "\n" "|")" = "|$MARK||![demo take](${ASSET}fake-1)||$ENDM||## Changes|" ] && posted ".ok==true and .pr==42 and .format==\"gif\" and .url==\"${ASSET}fake-1\" and .placement==\"after-summary\" and .kept_unmarked==0" && grep -qF -- "--attach $D/demo-take.gif#demo\\ take" "$ARGV" && grep -q "after the summary paragraph (line 4)" "$ERR"'
fi

if want P5; then
  post_case P5 $'Adds a filter bar.\n\nResolves PROJ-123\n\n## Changes\n' -- demo-take.gif
  check P5 "a ticket line after the summary keeps its place; the embed goes after it (after-ticket)" "body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(line_no "$BODYF" "$MARK")" = 5 ] && [ "$(nth "$BODYF" 3)" = "Resolves PROJ-123" ] && posted ".placement==\"after-ticket\""'
fi

if want P5b; then
  post_case P5b $'Adds a filter bar.\n\nhttps://linear.app/acme/issue/PROJ-123/filter-bar\n\nMore prose.\n' -- demo-take.gif
  check P5b "a bare Linear link counts as the ticket line" "body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(line_no "$BODYF" "$MARK")" = 5 ] && [ "$(line_no "$BODYF" "More prose.")" = 11 ] && posted ".placement==\"after-ticket\""'
fi

if want P6; then
  post_case P6 $'Summary.\n\n<!-- feature-video -->\n![old take](https://github.com/user-attachments/assets/old-1)\n\n## Changes\n' -- demo-take.gif
  check P6 "an older marker with no end marker is replaced through its embed, never duplicated" "body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(count "$BODYF" "$MARK")" = 1 ] && [ "$(count "$BODYF" "$ENDM")" = 1 ] && [ "$(count "$BODYF" "$ASSET")" = 1 ] && ! grep -q old-1 "$BODYF" && [ "$(line_no "$BODYF" "$MARK")" = 3 ] && posted ".placement==\"marker\"" && grep -q "replacing the earlier take at the marker (line 3)" "$ERR"'
fi

if want P6c; then
  post_case P6c $'Summary.\n\n<!-- pog-feature-video -->\n\n![old take](https://github.com/user-attachments/assets/old-1)\n\nOld caption.\n\n<!-- /pog-feature-video -->\n\n## Changes\n' -- demo-take.gif
  check P6c "a block under the older pog-feature-video marker pair is replaced whole and rewritten with the new markers" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && ! grep -q "pog-feature-video" "$BODYF" && ! grep -q "old-1" "$BODYF" && ! grep -q "Old caption." "$BODYF" && [ "$(count "$BODYF" "$MARK")" = 1 ] && [ "$(count "$BODYF" "$ENDM")" = 1 ] && [ "$(line_no "$BODYF" "$MARK")" = 3 ] && [ "$(tail -n 1 "$BODYF")" = "## Changes" ] && posted ".placement==\"marker\" and .kept_unmarked==0"'
fi

if want P6b; then
  post_case P6b $'Summary.\n\n## Changes\n' -- demo-take.gif
  post_again take.mp4
  check P6b "a second take (GIF then MP4) replaces the whole marked block" "body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(count "$BODYF" "$MARK")" = 1 ] && [ "$(count "$BODYF" "$ENDM")" = 1 ] && [ "$(count "$BODYF" "$ASSET")" = 1 ] && ! grep -q fake-1 "$BODYF" && grep -qx "${ASSET}fake-2" "$BODYF" && [ "$(tail -n 1 "$BODYF")" = "## Changes" ] && posted ".placement==\"marker\""'
fi

if want P7; then
  post_case P7 $'Adds run history.\n\nResolves PROJ-123\n\nWalkthrough: opening a past run and comparing it.\n\nhttps://github.com/user-attachments/assets/0f3c9a2e-human\n\n## Changes\n' -- demo-take.gif
  VLINE="$(line_no "$BODYF" "0f3c9a2e-human")"
  check P7 "an unmarked video (the author's own) is kept by default; the take goes above it and stderr says so" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && grep -qx "https://github.com/user-attachments/assets/0f3c9a2e-human" "$BODYF" && grep -q "^Walkthrough: opening a past run" "$BODYF" && [ "$(line_no "$BODYF" "$MARK")" = 5 ] && [ "$(line_no "$BODYF" "$MARK")" -lt "$VLINE" ] && grep -q "kept your existing video at line $VLINE; added this take above it" "$ERR" && posted ".placement==\"after-ticket\" and .kept_unmarked==1"'
fi

if want P7r; then
  post_case P7r $'Summary.\n\nhttps://github.com/user-attachments/assets/0f3c9a2e-legacy\n\n## Changes\n' -- demo-take.gif --replace-unmarked
  check P7r "--replace-unmarked replaces the one bare asset URL line with the marked block" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && ! grep -q 0f3c9a2e-legacy "$BODYF" && [ "$(line_no "$BODYF" "$MARK")" = 3 ] && [ "$(count "$BODYF" "$ASSET")" = 1 ] && posted ".placement==\"replaced-unmarked\" and .kept_unmarked==0" && grep -q "replacing the unmarked video at line 3 (--replace-unmarked)" "$ERR"'
fi

if want P7b; then
  post_case P7b $'Summary.\n\n## Before\n\nhttps://github.com/user-attachments/assets/aaa\n\n## After\n\nhttps://github.com/user-attachments/assets/bbb\n' -- demo-take.gif --replace-unmarked
  check P7b "--replace-unmarked with two bare asset URLs replaces neither and says why" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && grep -q assets/aaa "$BODYF" && grep -q assets/bbb "$BODYF" && [ "$(line_no "$BODYF" "$MARK")" = 3 ] && posted ".placement==\"after-summary\" and .kept_unmarked==2" && grep -q "found 2 bare video URL lines, not exactly one; replaced none" "$ERR"'
fi

if want P7c; then
  post_case P7c $'Summary.\n\n<!-- feature-video -->\n\n![old](https://github.com/user-attachments/assets/old-1)\n\n<!-- /feature-video -->\n\nhttps://github.com/user-attachments/assets/human-1\n' -- take.mp4
  check P7c "replacing a marked take leaves an unmarked video below it alone" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && ! grep -q old-1 "$BODYF" && grep -qx "${ASSET}human-1" "$BODYF" && grep -qx "${ASSET}fake-1" "$BODYF" && posted ".placement==\"marker\" and .kept_unmarked==1"'
fi

if want P8; then
  post_case P8 $'Summary.\n\n## Changes\n' -- take.mp4 --dry-run
  check P8 "an MP4 is written as ![](/abs) alone in its own paragraph inside the block" "stdout: $(tr '\n' '|' < "$OUT")" \
    eval '[ "$EXIT" = 0 ] && [ "$(sed -n 3,9p "$D/take.pr-body.md" | tr "\n" "|")" = "$MARK||![]($D/take.mp4)||$ENDM||## Changes|" ]'
fi

if want P8b; then
  post_case P8b $'Summary.\n\n## Changes\n' -- take.mp4 --alt "ignored for video"
  check P8b "a posted MP4 reads back as the bare asset URL alone (a player), attached with no #alt; --alt on it is noted as having no effect" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && grep -q "^post: --alt has no effect on a video (mp4)" "$ERR" && grep -qx "${ASSET}fake-1" "$BODYF" && [ "$(nth "$BODYF" "$(( $(line_no "$BODYF" "${ASSET}fake-1") + 1 ))")" = "" ] && grep -qE -- "--attach $D/take\\.mp4\$" "$ARGV" && posted ".format==\"mp4\" and .url==\"${ASSET}fake-1\""'
fi

if want P8c; then
  post_case P8c $'Summary.\n' -- "screen shot.png" --alt "Filter bar, open"
  check P8c "a path with a space is wrapped in <> and still rewritten; --alt sets the alt text" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && grep -qxF "![Filter bar, open](${ASSET}fake-1)" "$BODYF" && posted ".format==\"png\""'
fi

if want P8d; then
  post_case P8d $'## Demo\n\nOld demo prose.\n' -- demo-take.gif
  post_case P8d2 $'Summary.\n\n## Demo\n\nOld demo prose.\n' -- demo-take.gif
  check P8d "the embed never lands under a ## Demo heading" "body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(line_no "$BODYF" "$MARK")" -lt "$(line_no "$BODYF" "## Demo")" ] && [ "$(line_no "$WORK/P8d/body.md" "$MARK")" = 1 ] && [ "$(line_no "$WORK/P8d/body.md" "$MARK")" -lt "$(line_no "$WORK/P8d/body.md" "## Demo")" ]'
fi

if want P8e; then
  post_case P8e $'<!-- template: describe the change -->\n## Summary\n\nDoes the thing.\n\n## Changes\n' -- demo-take.gif
  check P8e "a leading template comment and ## Summary heading are skipped to the summary paragraph" "body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(line_no "$BODYF" "$MARK")" = 6 ] && [ "$(nth "$BODYF" 4)" = "Does the thing." ]'
fi

if want P8f; then
  post_case P8f $'Summary.\r\n\r\n## Changes\r\n' -- demo-take.gif
  check P8f "a CRLF body is handled and the embed lands after the summary" "body: $(tr '\n\r' '|~' < "$BODYF")" \
    eval '[ "$EXIT" = 0 ] && [ "$(line_no "$BODYF" "$MARK")" = 3 ] && ! grep -q $'"'"'\r'"'"' "$BODYF"'
fi

if want P8g; then
  post_case P8g '' -- demo-take.gif
  check P8g "an empty body gets exactly one block (placement top)" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(nth "$BODYF" 1)" = "$MARK" ] && [ "$(count "$BODYF" "$MARK")" = 1 ] && [ "$(count "$BODYF" "$ASSET")" = 1 ] && posted ".placement==\"top\""'
fi

if want P8h; then
  post_case P8h $'https://github.com/user-attachments/assets/human-1\n\nSummary after the video.\n' -- demo-take.gif
  check P8h "a body that opens with a video gets the take above it, video kept" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(nth "$BODYF" 1)" = "$MARK" ] && grep -qx "${ASSET}human-1" "$BODYF" && posted ".placement==\"above-visual\" and .kept_unmarked==1"'
fi

if want P8i; then
  post_case P8i $'Summary.\n\n![shot](https://example.com/a.png)\n\n<details>\n<summary>More</summary>\n\n![b](https://github.com/user-attachments/assets/b)\n\n<img src="https://example.com/c.png">\n\n</details>\n' -- demo-take.gif
  check P8i "several unmarked visuals (some inside <details>) are kept and summarized in one stderr line" "$(why); stderr: $(tr '\n' '|' < "$ERR")" \
    eval '[ "$EXIT" = 0 ] && [ "$(grep -c "kept" "$ERR")" = 1 ] && grep -q "^post: kept 3 existing visuals untouched (first: the image at line 9, with this take above it)$" "$ERR" && posted ".kept_unmarked==3"'
fi

if want P8j; then
  post_case P8j $'Summary.\n\n## Changes\n\n- a\n\n\n' -- demo-take.gif --dry-run
  DRYD="$D"
  post_case P8j2 $'Summary.\n\n## Changes\n\n- a\n\n\n' -- demo-take.gif
  check P8j "the body's trailing blank lines survive byte for byte (dry-run diff, saved body, and the edit)" "diff: $(grep -E '^[-+]' "$DRYD/stdout" | tr '\n' '|'); body: $(body)" \
    eval '[ "$(grep -cE "^-([^-]|$)" "$DRYD/stdout")" = 0 ] && python3 -c "import sys; a, b = (open(f).read() for f in sys.argv[1:]); sys.exit(not (a.endswith(\"- a\n\n\n\") and b.endswith(\"- a\n\n\n\")))" "$DRYD/demo-take.pr-body.md" "$BODYF"'
fi

# --- P12: captions ----------------------------------------------------------

if want P12; then
  post_case P12 $'Summary.\n\n## Changes\n' -- take.mp4 --caption "Fake-mode data."
  check P12 "--caption adds one line under the take inside the block; the video stays alone in its paragraph" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && [ "$(sed -n 3,11p "$BODYF" | tr "\n" "|")" = "$MARK||${ASSET}fake-1||Fake-mode data.||$ENDM||## Changes|" ] && posted ".url==\"${ASSET}fake-1\""'
fi

if want P12b; then
  post_case P12b $'Summary.\n\n## Changes\n' -- demo-take.gif --caption "Fake-mode data."
  post_again demo-take.gif --caption "Simulated timing."
  check P12b "a re-run with a new --caption replaces the old caption with the take" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && ! grep -q "Fake-mode data." "$BODYF" && [ "$(count "$BODYF" "Simulated timing.")" = 1 ] && [ "$(count "$BODYF" "$ASSET")" = 1 ] && [ "$(line_no "$BODYF" "Simulated timing.")" -lt "$(line_no "$BODYF" "$ENDM")" ]'
fi

if want P12c; then
  post_case P12c $'Summary.\n\n## Changes\n' -- take.mp4 --caption "Fake-mode data."
  post_again take.mp4
  check P12c "a re-run without --caption removes the old caption" "$(why); body: $(body)" \
    eval '[ "$EXIT" = 0 ] && ! grep -q "Fake-mode data." "$BODYF" && [ "$(sed -n 3,9p "$BODYF" | tr "\n" "|")" = "$MARK||${ASSET}fake-2||$ENDM||## Changes|" ]'
fi

# --- P9-P10: readback and dry run ------------------------------------------

if want P9; then
  post_case P9 $'Summary.\n' FAKE_GH_REWRITE=fail -- demo-take.gif
  check P9 "a local path surviving the edit fails the readback with exit 7" "$(why)" \
    eval '[ "$EXIT" = 7 ] && grep -q "local path survived" "$ERR" && posted ".ok==false and .exit==7"'
fi

if want P9b; then
  post_case P9b $'Summary.\n\nSee ![old](/home/someone/old.png) too.\n' -- demo-take.gif
  check P9b "any other local absolute path in the body also fails the readback" "$(why)" \
    eval '[ "$EXIT" = 7 ] && grep -q "local absolute path" "$ERR" && posted ".exit==7"'
fi

if want P10; then
  post_case P10 $'Summary.\n' -- demo-take.gif --dry-run
  check P10 "--dry-run prints a body diff and gh argv, saves the new body beside the take, and edits nothing" "$(why)" \
    eval '[ "$EXIT" = 0 ] && ! edited && [ "$(cat "$BODYF")" = "Summary." ] && grep -qxF "+![demo take]($D/demo-take.gif)" "$OUT" && grep -qxF "![demo take]($D/demo-take.gif)" "$D/demo-take.pr-body.md" && grep -qF -- "--body-file $D/demo-take.pr-body.md" "$OUT" && posted ".ok==true and .dry_run==true and .url==null"'
fi

if want P10b; then
  post_case P10b $'Summary.\n' -- demo-take.gif --dry-run --caption "Named report_<Client>_<Region>.csv"
  check P10b "a caption's angle brackets are escaped so GitHub does not strip them as tags" "$(why)" \
    eval 'grep -qxF "Named report_&lt;Client&gt;_&lt;Region&gt;.csv" "$D/demo-take.pr-body.md"'
fi

if want P11; then
  post_case P11a $'Summary.\n' -- missing.gif
  post_case P11b $'Summary.\n' -- notes.txt
  post_case P11c $'Summary.\n' FAKE_GH_EDIT_EXIT=1 -- demo-take.gif
  E11c=$EXIT
  post_case P11d $'Summary.\n' -- --pr 7 demo-take.gif
  E11d=$EXIT
  bad=''
  for o in "$WORK"/P*/stdout; do
    tail -n 1 "$o" | sed -n 's/^POSTED //p' | jq -e 'has("ok")' >/dev/null 2>&1 || bad="$bad ${o#$WORK/}"
  done
  check P11 "every run ends with a parseable POSTED line (missing file 2, .txt 2, failed edit 8, unknown PR 4)" "no POSTED line:$bad; exits $(cat "$WORK/P11a/stdout" | tail -n 1) / P11c=$E11c P11d=$E11d" \
    eval '[ -z "$bad" ] && grep -q "\"exit\":2" "$WORK/P11a/stdout" && grep -q "\"exit\":2" "$WORK/P11b/stdout" && [ "$E11c" = 8 ] && [ "$E11d" = 4 ]'
fi

# --- C1-C12: pr-context.sh -------------------------------------------------

# mkrepo <id> <branch> <path ...>: a repo whose main has README.md, and whose
# <branch> adds or edits each path. Leaves $R.
mkrepo() {
  local id="$1" branch="$2"; shift 2
  R="$WORK/$id/repo"; mkdir -p "$R"
  git -c init.templateDir= init -q -b main "$R"
  git -C "$R" config user.email eval@example.test; git -C "$R" config user.name eval
  git -C "$R" config core.excludesFile /dev/null
  printf '# app\n' > "$R/README.md"; git -C "$R" add -A; git -C "$R" commit -q -m init
  git -C "$R" checkout -q -b "$branch"
  local f
  for f in "$@"; do mkdir -p "$R/$(dirname "$f")"; printf 'changed\n' >> "$R/$f"; done
  git -C "$R" add -A; git -C "$R" commit -q -m change
}

# ctx <id> [VAR=value ...] -- [pr-context args ...]: run in $R. Leaves $OUT, $EXIT.
ctx() {
  local id="$1"; shift
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  OUT="$WORK/$id/ctx.out"; ERR="$WORK/$id/ctx.err"
  (cd "$R" && env PATH="$FAKE:$PATH" FAKE_GH_PR= ${envs[@]+"${envs[@]}"} "$BASH_UT" "$CTX" "$@") > "$OUT" 2> "$ERR"
  EXIT=$?
}
has() { grep -qE -e "$1" "$OUT"; }
cwhy() { printf 'exit %s; %s' "$EXIT" "$(tr '\n' '|' < "$OUT" | cut -c 1-400)"; }

if want C1; then
  mkrepo C1 feat/orders-filter app/views/orders/index.html.erb app/models/order.rb app/javascript/controllers/filter_controller.js f/apps/dashboard.raw_app/App.tsx
  ctx C1 --
  check C1 "UI files (erb view, Stimulus JS, Windmill-style raw-app App.tsx) give VERDICT: FILM and are listed" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^VERDICT: FILM$" && has "^  app/views/orders/index.html.erb$" && has "^  app/javascript/controllers/filter_controller.js$" && has "^  f/apps/dashboard.raw_app/App.tsx$" && ! has "^  app/models/order.rb$" && has "backend \\(1\\): app/models/order.rb"'
fi

if want C2; then
  mkrepo C2 fix/order-totals app/models/order.rb db/migrate/20261001_add_total.rb f/apps/tools.raw_app/backend/list_items.yaml
  ctx C2 --
  check C2 "backend-only changes (incl. a raw app's backend/) give SKIP and exit 0" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^VERDICT: SKIP \\(no UI-facing files changed: backend 3\\)$" && ! has "^UI_FILES"'
fi

if want C3; then
  mkrepo C3 docs/readme README.md docs/guide.md app/views/README.md
  ctx C3 --
  check C3 "docs-only changes give SKIP, even a .md under app/views" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^VERDICT: SKIP \\(no UI-facing files changed: docs 3\\)$"'
fi

if want C4; then
  mkrepo C4 test/orders spec/system/orders_spec.rb src/components/Button.test.tsx app/javascript/__tests__/filter.js test/models/order_test.rb
  ctx C4 --
  check C4 "tests-only changes give SKIP, even a .test.tsx under src/components" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^VERDICT: SKIP \\(no UI-facing files changed: tests 4\\)$"'
fi

if want C5; then
  mkrepo C5 dev/proj-123-orders-filter app/views/orders/index.html.erb
  ctx C5 --
  T1="$(grep '^TICKET:' "$OUT")"
  mkrepo C5b feat/APP-774-x app/views/a.html.erb
  ctx C5b --
  T2="$(grep '^TICKET:' "$OUT")"
  mkrepo C5c feat/feature-video-gif-and-cursor app/views/a.html.erb
  ctx C5c --
  T3="$(grep '^TICKET:' "$OUT")"
  check C5 "the ticket key comes from the branch (PROJ-123, APP-774, none)" "$T1 / $T2 / $T3" \
    eval '[ "$T1" = "TICKET: PROJ-123" ] && [ "$T2" = "TICKET: APP-774" ] && [ "$T3" = "TICKET: none in branch name" ]'
fi

if want C9; then
  mkrepo C9 feat/orders-filter app/views/a.html.erb
  ctx C9 --
  check C9 "with no PR, it diffs the branch against the default branch and says so" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^PR: none for feat/orders-filter; using git$" && has "branch=feat/orders-filter  base=main" && has "^FILES: 1 changed$"'
fi

if want C10; then
  mkrepo C10 dev/proj-123-orders-filter README.md
  printf 'Adds a filter bar to the orders page so ops can find stuck orders.\nIt remembers the last filter.\n\n<!-- template note -->\n## Claims\n\n- Saved filters\n\n![take](https://github.com/user-attachments/assets/x)\n\nAfter the visual.\n' > "$WORK/C10/body.md"
  ctx C10 FAKE_GH_PR=42 FAKE_GH_BODY="$WORK/C10/body.md" FAKE_GH_TITLE="Filter orders" FAKE_GH_HEAD=dev/proj-123-orders-filter FAKE_GH_FILES=$'app/javascript/controllers/filter_controller.js\napp/models/order.rb' --
  check C10 "with a PR, it prints number, title, head, state, URL, the PR's files, and the body up to its first visual" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^PR: #42 Filter orders$" && has "OPEN  head=dev/proj-123-orders-filter  base=main  https://github.com/acme/app/pull/42" && has "^VERDICT: FILM$" && [ "$(sed -n "/^BODY:/,\$p" "$OUT" | tr "\n" "|")" = "BODY: (to the first image, video, or <details>; 40 lines at most)|  Adds a filter bar to the orders page so ops can find stuck orders.|  It remembers the last filter.||  ## Claims||  - Saved filters|" ] && has "^FILES: 2 changed$"'
fi

if want C11; then
  mkrepo C11 feat/orders app/views/a.html.erb
  printf -- '---\nfeature_video:\n  base_url: http://localhost:3000 # dev server\n---\n' > "$R/agent-stuff.md"
  ctx C11 --
  A="$(grep '^BASE_URL:' "$OUT")"
  printf -- '---\nreview_agents: []\nfeature_video:\n  base_url: "https://staging.example.com"\n---\n' > "$R/agent-stuff.local.md"
  ctx C11 --
  B="$(grep '^BASE_URL:' "$OUT")"
  printf -- '---\nfeature_video:\n  format: mp4\n---\n' > "$R/agent-stuff.local.md"
  ctx C11 --
  D="$(grep '^BASE_URL:' "$OUT")"
  rm "$R/agent-stuff.md" "$R/agent-stuff.local.md"; ctx C11 --
  C="$(grep '^BASE_URL:' "$OUT")"
  check C11 "feature_video.base_url comes from agent-stuff.local.md, then agent-stuff.md; a local block replaces the tracked one whole; unset, it says to pass a base URL" "$A / $B / $D / $C" \
    eval '[ "$A" = "BASE_URL: http://localhost:3000  (feature_video.base_url in agent-stuff.md)" ] && [ "$B" = "BASE_URL: https://staging.example.com  (feature_video.base_url in agent-stuff.local.md)" ] && [ "$D" = "BASE_URL: feature_video.base_url not configured (pass a base URL)" ] && [ "$C" = "BASE_URL: feature_video.base_url not configured (pass a base URL)" ]'
fi

if want C12; then
  files=(); i=1
  while [ "$i" -le 40 ]; do files+=("app/views/orders/v$i.html.erb" "app/models/m$i.rb"); i=$((i + 1)); done
  mkrepo C12 feat/big "${files[@]}"
  printf "Summary $(printf 'word %.0s' $(seq 1 150))\n" > "$WORK/C12/body.md"
  ctx C12 FAKE_GH_PR=9 FAKE_GH_BODY="$WORK/C12/body.md" FAKE_GH_HEAD=feat/big --
  LINES="$(wc -l < "$OUT" | tr -d ' ')"
  check C12 "80 changed files still fit the digest: under 60 lines, 15 UI files, a long body line cut at 300 chars" "$LINES lines; $(cwhy)" \
    eval '[ "$EXIT" = 0 ] && [ "$LINES" -lt 60 ] && has "^  \\+25 more$" && has "ui \\(40\\): .*, \\+36 more$" && [ "$(grep "^  Summary word" "$OUT" | wc -c | tr -d " ")" -le 310 ]'
fi

if want C16; then
  mkrepo C16 feat/orders app/views/a.html.erb
  printf -- '---\nfeature_video:\n  base_url: http://localhost:3000\n---\n' > "$R/agent-stuff.local.md"
  git -C "$R" worktree add -q "$WORK/C16/wt" -b feat/wt 2>/dev/null
  MAIN="$R"; R="$WORK/C16/wt"; ctx C16 --
  A="$(grep -E '^(CONFIG|BASE_URL):' "$OUT" | tr '\n' '|')"
  printf -- '---\nfeature_video:\n  base_url: http://localhost:3400\n---\n' > "$R/agent-stuff.local.md"; ctx C16 --
  B="$(grep -E '^(CONFIG|BASE_URL):' "$OUT" | tr '\n' '|')"
  check C16 "a worktree with no config file reads the main checkout's and says so; its own copy wins" "$A / $B" \
    eval '[ "$A" = "CONFIG: this worktree has no agent-stuff.local.md or agent-stuff.md; using the main checkout'"'"'s ($MAIN)|BASE_URL: http://localhost:3000  (feature_video.base_url in $MAIN/agent-stuff.local.md)|" ] && [ "$B" = "BASE_URL: http://localhost:3400  (feature_video.base_url in agent-stuff.local.md)|" ]'
fi

if want C18; then
  mkrepo C18 feat/orders app/views/a.html.erb
  printf -- '---\nfeature_video:\n  enabled: false\n  base_url: http://localhost:3000\n---\n' > "$R/agent-stuff.md"
  ctx C18 --
  check C18 "feature_video.enabled: false skips with a one-line reason before any PR lookup" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && [ "$(cat "$OUT")" = "VERDICT: SKIP (feature_video.enabled is false in agent-stuff.md)" ]'
fi

if want C19; then
  mkrepo C19 feat/orders app/views/a.html.erb
  printf -- '---\nfeature_video:\n  base_url: http://localhost:3000\n  username: admin@example.test\n  password: <dev-only>\n  cookies_file: tmp/cookies.json\n---\n' > "$R/agent-stuff.local.md"
  mkdir -p "$R/tmp"; printf '[]' > "$R/tmp/cookies.json"
  ctx C19 --
  A="$(grep '^WARNING:' "$OUT" | tr '\n' '|')"
  printf 'agent-stuff.local.md\ntmp/\n' > "$R/.gitignore"
  ctx C19 --
  B="$(grep -c '^WARNING:' "$OUT")"
  check C19 "credentials in a config file that is not git-ignored (and a cookies file that is not) each get a WARNING; none once both are ignored" "$A / $B" \
    eval '[ "$A" = "WARNING: agent-stuff.local.md sets feature_video password, cookies_file but is not git-ignored, so it could be committed; move credentials to an ignored agent-stuff.local.md|WARNING: feature_video.cookies_file (tmp/cookies.json) is not git-ignored, so it could be committed|" ] && [ "$B" = 0 ]'
fi

if want C20; then
  mkrepo C20 feat/orders app/views/a.html.erb
  printf -- '---\nfeature_video:\n  format: gif\n  gif_max_seconds: 8 # short\n  auto_post: false\n  # review_dir: tmp/videos\n---\n' > "$R/agent-stuff.md"
  ctx C20 --
  check C20 "FEATURE_VIDEO names the config file and the active knobs it sets (commented keys ignored)" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^FEATURE_VIDEO: from agent-stuff.md; format=gif gif_max_seconds=8 auto_post=false$" && has "^VERDICT: FILM$"'
fi

if want C17 && command -v lsof >/dev/null 2>&1; then
  mkrepo C17 feat/orders app/views/a.html.erb
  printf -- '---\nfeature_video:\n  base_url: http://localhost:3000/app?fake=1\n---\n' > "$R/agent-stuff.local.md"
  P=''; for c in 23417 24719 26113 27329 28541; do lsof -nP -iTCP:"$c" -sTCP:LISTEN >/dev/null 2>&1 || { P="$c"; break; }; done
  (cd "$R" && exec python3 -m http.server "$P" --bind 127.0.0.1 >/dev/null 2>&1) & SRV=$!
  for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:$P/" >/dev/null 2>&1 && break; sleep 0.1; done
  ctx C17 --; kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
  check C17 "a localhost BASE_URL follows the one port this worktree serves, keeping its path" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^DEV_SERVER: :$P served from this worktree$" && has "^BASE_URL: http://localhost:$P/app\\?fake=1  \\(feature_video.base_url in agent-stuff.local.md, on this worktree.s dev-server port; config says :3000\\)$"'
fi

if want C13; then
  mkdir -p "$WORK/C13/norepo"; R="$WORK/C13/norepo"
  ctx C13 --
  check C13 "outside a git repo it prints SKIP and exits 0" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^VERDICT: SKIP \\(not a git repository\\)$"'
fi

if want C14; then
  mkrepo C14 feat/run-history src/runs/fixtures.ts src/runs/history.ts src/runs/history.css src/runs/RunHistoryScreen.tsx app/views/runs/show.html.erb
  ctx C14 --
  ORDER="$(sed -n '/^UI_FILES:/,/^[A-Z]/p' "$OUT" | grep '^  ' | sed 's/^  //' | tr '\n' ' ')"
  check C14 "UI files list markup and components first, then styles, then logic and fixtures; no hint" "$ORDER" \
    eval '[ "$ORDER" = "app/views/runs/show.html.erb src/runs/RunHistoryScreen.tsx src/runs/history.css src/runs/fixtures.ts src/runs/history.ts " ] && ! has "^hint:"'
fi

if want C15; then
  mkrepo C15 feat/run-history src/runs/fixtures.ts src/runs/history.ts app/models/run.rb
  ctx C15 --
  check C15 "with no component changed, a hint names the changed UI modules to trace to a screen" "$(cwhy)" \
    eval '[ "$EXIT" = 0 ] && has "^VERDICT: FILM$" && has "^hint: no component changed; find the screen that renders fixtures.ts, history.ts$"'
fi

# --- F1-F2: the scripts survive a host flattening them to one line ----------

flatten() { grep -vE '^[[:space:]]*#' "$1" | tr '\n' ' ' > "$2"; }

if want F1; then
  flatten "$POST" "$WORK/post.flat.sh"; flatten "$CTX" "$WORK/ctx.flat.sh"
  check F1 "both scripts still parse with comments dropped and every newline turned into a space" "$("$BASH_UT" -n "$WORK/post.flat.sh" 2>&1; "$BASH_UT" -n "$WORK/ctx.flat.sh" 2>&1)" \
    eval '"$BASH_UT" -n "$WORK/post.flat.sh" 2>/dev/null && "$BASH_UT" -n "$WORK/ctx.flat.sh" 2>/dev/null'
fi

if want F2; then
  flatten "$POST" "$WORK/post.flat.sh"; flatten "$CTX" "$WORK/ctx.flat.sh"
  POST_REAL="$POST"; POST="$WORK/post.flat.sh"
  post_case F2 $'Summary.\n\nResolves PROJ-1\n\n## Changes\n' -- take.mp4
  POST="$POST_REAL"
  mkrepo F2c dev/proj-123-x app/views/a.html.erb app/models/b.rb
  CTX_REAL="$CTX"; CTX="$WORK/ctx.flat.sh"; ctx F2c --; FLAT="$(cat "$OUT")"
  CTX="$CTX_REAL"; ctx F2c --; REAL="$(cat "$OUT")"
  check F2 "the flattened scripts behave the same (MP4 post, pr-context digest)" "$(why); digest differs: $([ "$FLAT" = "$REAL" ] && echo no || echo yes)" \
    eval '[ "$EXIT" = 0 ] && grep -qx "${ASSET}fake-1" "$BODYF" && [ "$(line_no "$BODYF" "$MARK")" = 5 ] && [ "$FLAT" = "$REAL" ] && [ -n "$REAL" ]'
fi

echo
echo "$PASSED passed, $FAILED failed"
exit "$FAILED"
