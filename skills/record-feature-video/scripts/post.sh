#!/usr/bin/env bash
# post.sh -- embed one feature-video take in a PR body and upload it with gh --attach.
#
# Usage: post.sh <file> [--pr N] [--alt "text"] [--caption "text"]
#                [--replace-unmarked] [--dry-run]
#
#   <file>              a .gif, .png, .jpg, .mp4, .webm, or .mov; resolved to an
#                       absolute path.
#   --pr N              the PR to edit; default: the PR for the current branch.
#                       Works from any directory inside the repo, a detached
#                       checkout included (gh needs the repo, not the branch).
#   --alt T             image alt text; default: the filename, words split on
#                       - _ and dots. A video has no alt text (gh refuses one),
#                       so --alt is ignored for it, with a note on stderr.
#   --caption T         one short line under the take ("Fake-mode data.",
#                       "Simulated timing."). It lives inside the marked block,
#                       so a re-run replaces it, and a re-run without --caption
#                       removes it.
#   --replace-unmarked  with no marked block, replace the body's one bare
#                       user-attachments URL line (an earlier video nobody
#                       marked). Off by default: an unmarked visual is usually
#                       the author's own and is never touched without this.
#   --dry-run           print a diff of the body, save the new body beside the take
#                       (<take>.pr-body.md), and print the gh argv; upload and edit nothing.
#
# The take is one marked block, replaced as a unit by a re-run:
#
#   <!-- feature-video -->
#   (blank)
#   ![alt](/abs/take.gif)       a video: ![](/abs/take.mp4), alone in its paragraph
#   (blank)
#   Caption line.               only with --caption
#   (blank)
#   <!-- /feature-video -->
#
# A block between the older <!-- pog-feature-video --> marker pair is also
# recognized as ours and replaced; only the new pair is ever written.
#
# Placement (the POSTED "placement" value):
#   marker             a marked block exists; it is replaced. A start marker with
#                      no end marker (an older take) is replaced through its
#                      embed line.
#   replaced-unmarked  --replace-unmarked and exactly one bare asset URL line.
#   after-ticket       after the ticket line (Resolves/Fixes/Closes/Part of/Refs,
#                      or a bare Linear or ticket link) that follows the summary.
#   after-summary      after the opening summary paragraph (leading headings
#                      other than Demo, and template comments, are skipped).
#   above-visual       the body opens with a visual; the take goes above it.
#   before-demo        the body opens with a Demo heading; the take goes above it.
#   top / end          an empty body / a body with no paragraph to follow.
# The take never lands under a "## Demo" heading. Every unmarked visual is kept,
# and stderr says so in one line: "kept your existing video at line N; added
# this take above it", or for several, the count and the first.
#
# Everything else in the body is kept byte for byte, its trailing blank lines
# included.
#
# gh (2.99+) uploads the file and rewrites its path. Verified against gh
# v2.102.0 internal/attachments: gh only rewrites markdown references, never a
# bare path line. An image reference keeps its alt text and gets the asset URL;
# a video written as ![](/abs/x.mp4) alone in its paragraph becomes the bare
# asset URL (the player form); a video embed sharing a paragraph degrades to a
# link; an unreferenced file is appended at the end of the body. gh rejects alt
# text on a video, so the --attach value carries "#alt" for images only.
#
# The body is read back afterwards: no attached path, file:// URL, or local
# absolute path may survive, and the first line in the marked block must be the
# rewritten embed (a video: the bare URL alone in its paragraph).
#
# The last stdout line is always: POSTED {json}
#   success: {"ok":true,"pr":N,"file":"/abs","format":"gif","placement":"after-summary",
#             "kept_unmarked":0,"url":"https://..."}
#   dry run: the same with "dry_run":true and "url":null
#   failure: {"ok":false,"exit":N,"error":"..."}
#
# Exit: 0 posted or dry run; 2 usage or bad file; 4 a gh read failed;
#       5 gh missing or lacks --attach; 6 no PR; 7 readback found a local path
#       or an unrewritten embed; 8 gh pr edit failed.
#
# Flatten-safe: every interior statement ends in ';' or a connector, with no
# heredocs, backslash continuations, or comments below this header.
set -euo pipefail;

MARKER='<!-- feature-video -->';
END_MARKER='<!-- /feature-video -->';
OLD_MARKER='<!-- pog-feature-video -->';
OLD_END_MARKER='<!-- /pog-feature-video -->';
USAGE='usage: post.sh <file> [--pr N] [--alt "text"] [--caption "text"] [--replace-unmarked] [--dry-run]';
POSTED_DONE=0;
TMPD='';

json_str() {
  local s="$1";
  s="${s//\\/\\\\}";
  s="${s//\"/\\\"}";
  s="${s//$'\n'/\\n}";
  s="${s//$'\r'/\\r}";
  s="${s//$'\t'/\\t}";
  printf '"%s"' "$s";
};

fail() {
  local code="$1" msg="$2";
  printf 'post: %s\n' "$msg" >&2;
  POSTED_DONE=1;
  printf 'POSTED {"ok":false,"exit":%s,"error":%s}\n' "$code" "$(json_str "$msg")";
  exit "$code";
};

on_exit() {
  local rc=$?;
  if [ -n "$TMPD" ] && [ -d "$TMPD" ]; then rm -rf "$TMPD"; fi;
  if [ "$POSTED_DONE" = 0 ]; then printf 'POSTED {"ok":false,"exit":%s,"error":"unexpected failure"}\n' "$rc"; fi;
};
trap on_exit EXIT;

upgrade_hint() {
  if command -v brew >/dev/null 2>&1; then printf 'brew upgrade gh';
  elif command -v apt-get >/dev/null 2>&1; then printf 'sudo apt-get update && sudo apt-get install --only-upgrade gh';
  elif command -v dnf >/dev/null 2>&1; then printf 'sudo dnf upgrade gh';
  elif command -v winget >/dev/null 2>&1; then printf 'winget upgrade --id GitHub.cli';
  else printf 'install gh 2.99 or later from https://github.com/cli/cli#installation';
  fi;
};

one_line() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//';
};

FILE=''; PR=''; ALT=''; ALT_GIVEN=0; CAPTION=''; REPLACE_UNMARKED=0; DRY=0;
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) [ $# -ge 2 ] || fail 2 "--pr needs a PR number"; PR="$2"; shift 2 ;;
    --pr=*) PR="${1#--pr=}"; shift ;;
    --alt) [ $# -ge 2 ] || fail 2 "--alt needs text"; ALT="$2"; ALT_GIVEN=1; shift 2 ;;
    --alt=*) ALT="${1#--alt=}"; ALT_GIVEN=1; shift ;;
    --caption) [ $# -ge 2 ] || fail 2 "--caption needs text"; CAPTION="$2"; shift 2 ;;
    --caption=*) CAPTION="${1#--caption=}"; shift ;;
    --replace-unmarked) REPLACE_UNMARKED=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) printf '%s\n' "$USAGE" >&2; fail 2 "usage only; nothing posted" ;;
    -*) fail 2 "unknown flag: $1" ;;
    *) [ -z "$FILE" ] || fail 2 "one file only (got $FILE and $1)"; FILE="$1"; shift ;;
  esac;
done;

[ -n "$FILE" ] || fail 2 "$USAGE";
[ -f "$FILE" ] || fail 2 "no such file: $FILE";
ABS="$(cd "$(dirname "$FILE")" && pwd -P)/$(basename "$FILE")";
case "$ABS" in *'<'*|*'>'*|*$'\n'*) fail 2 "rename the file: its path holds < > or a newline, which no markdown link can carry: $ABS" ;; esac;

EXT="$(printf '%s' "${ABS##*.}" | tr '[:upper:]' '[:lower:]')";
case "$EXT" in
  gif) FORMAT=gif; KIND=image ;;
  png) FORMAT=png; KIND=image ;;
  jpg|jpeg) FORMAT=jpg; KIND=image ;;
  mp4) FORMAT=mp4; KIND=video ;;
  webm) FORMAT=webm; KIND=video ;;
  mov) FORMAT=mov; KIND=video ;;
  *) fail 2 "unsupported type .$EXT (want gif, png, jpg, mp4, webm, or mov)" ;;
esac;
if [ "$KIND" = video ] && [ "$ALT_GIVEN" = 1 ]; then printf 'post: --alt has no effect on a video (%s): GitHub shows it with no alt text; put what it shows in --caption if it needs saying\n' "$FORMAT" >&2; fi;

if [ -z "$ALT" ]; then
  ALT="${ABS##*/}";
  ALT="${ALT%.*}";
  ALT="$(printf '%s' "$ALT" | tr '_.-' '   ')";
fi;
ALT="$(one_line "$(printf '%s' "$ALT" | tr -d '[]')")";
CAPTION="$(one_line "$CAPTION")";
case "$CAPTION" in *'<!--'*|*'-->'*) fail 2 "--caption cannot hold an HTML comment" ;; esac;
CAPTION="$(printf '%s' "$CAPTION" | sed 's/</\&lt;/g; s/>/\&gt;/g')";

command -v gh >/dev/null 2>&1 || fail 5 "gh not found; install gh 2.99 or later: $(upgrade_hint)";
GH_VER="$(gh --version 2>/dev/null | sed -n 's/^gh version \([0-9][0-9.]*\).*/\1/p' | head -n 1)" || GH_VER='';
GH_MAJ="${GH_VER%%.*}";
GH_REST="${GH_VER#*.}";
GH_MIN="${GH_REST%%.*}";
VER_OK=0;
case "$GH_MAJ$GH_MIN" in
  ''|*[!0-9]*) VER_OK=0 ;;
  *) if [ "$GH_MAJ" -gt 2 ] || { [ "$GH_MAJ" -eq 2 ] && [ "$GH_MIN" -ge 99 ]; }; then VER_OK=1; fi ;;
esac;
HELP="$(gh pr edit --help 2>&1)" || HELP='';
case "$HELP" in *--attach*) ;; *) VER_OK=0 ;; esac;
[ "$VER_OK" = 1 ] || fail 5 "gh ${GH_VER:-unknown} lacks --attach; run: $(upgrade_hint)";

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/feature-video-XXXXXX")";
PR="${PR#\#}";
if [ -z "$PR" ]; then
  PR="$(gh pr view --json number -q .number 2> "$TMPD/lookup.err")" || PR='';
  if [ -z "$PR" ]; then
    WHY="$(tr '\n' ' ' < "$TMPD/lookup.err" | cut -c 1-200 | sed 's/[[:space:]]*$//')";
    fail 6 "no PR found for this checkout's branch${WHY:+ (gh: $WHY)}; pass --pr N (it works from any directory in the repo, detached or not), or open one first (open-pr)";
  fi;
fi;
case "$PR" in *[!0-9]*) fail 2 "--pr must be a PR number, got: $PR" ;; esac;

CUR="$TMPD/current.md";
NEW="$TMPD/body.md";
BACK="$TMPD/readback.md";
ERR="$TMPD/gh.err";
PLACED="$TMPD/placed";

if ! gh pr view "$PR" --json body -q .body > "$CUR" 2> "$ERR"; then
  WHERE='';
  if grep -qi 'git repo' "$ERR"; then WHERE='; run post.sh from any directory inside the repo, or set GH_REPO=owner/name'; fi;
  fail 4 "could not read the body of PR #$PR: $(tr '\n' ' ' < "$ERR" | cut -c 1-300)$WHERE";
fi;

DEST="$ABS";
case "$ABS" in *[[:space:]\(\)]*) DEST="<$ABS>" ;; esac;
if [ "$KIND" = image ]; then
  EMBED="![$ALT]($DEST)";
  ATTACH="$ABS#$ALT";
else
  EMBED="![]($DEST)";
  ATTACH="$ABS";
fi;

PF_MARKER="$MARKER" PF_END="$END_MARKER" PF_OLD="$OLD_MARKER" PF_OLD_END="$OLD_END_MARKER" PF_EMBED="$EMBED" PF_CAPTION="$CAPTION" PF_REPLACE="$REPLACE_UNMARKED" PF_PLACED="$PLACED" awk '
function blank(s) { return s ~ /^[ \t]*$/; }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s; }
function heading(s) { return s ~ /^ ? ? ?#+([ \t]|$)/; }
function demo(s) { return heading(s) && tolower(s) ~ /^ ? ? ?#+[ \t]+demo/; }
function embedish(s) { s = trim(s); return s ~ /^!?\[/ || s ~ /^<(img|video|picture|a)[ >]/ || s ~ /^(https?|file):\/\// || s ~ /^\// || s ~ /^<\//; }
function asset_line(s) { return trim(s) ~ /^https:\/\/[^ ]*\/user-attachments\/assets\/[A-Za-z0-9-]+$/; }
function visual(s,  t) {
  t = trim(s);
  if (asset_line(s) || t ~ /<video[ >]/) return "video";
  if (t ~ /\/user-attachments\/assets\// || t ~ /<img[ >]/ || t ~ /!\[.*\]\(https?:\/\//) return "image";
  return "";
};
function ours(s) { s = trim(s); return s == marker || s == oldm; };
function ours_end(s) { s = trim(s); return s == endm || s == oldend; };
function ticket(s,  t) {
  t = trim(s); gsub(/^[*_>-]+[ \t]*/, "", t); gsub(/[*_]+/, "", t); t = tolower(t);
  if (t ~ /^(resolves|resolved|fixes|fixed|closes|closed|part of|refs|ref|relates to|related to|ticket|linear|jira|issue)[ :]/) return 1;
  if (t ~ /^https?:\/\/linear\.app\/[^ ]+$/) return 1;
  if (t ~ /^https?:\/\/[^ ]*(atlassian\.net\/browse|\/issues\/)[^ ]*$/) return 1;
  if (t ~ /^\[[a-z][a-z0-9]*-[0-9]+\]\(https?:\/\/[^)]+\)$/) return 1;
  if (t ~ /^[a-z][a-z0-9]*-[0-9]+$/) return 1;
  return 0;
};
function para_end(i) { while (i + 1 <= n && !blank(L[i + 1]) && !heading(L[i + 1])) i++; return i; };
function emit(s) { out[++no] = s; };
function emit_line(s) { if (pad && !blank(s)) emit(""); pad = 0; emit(s); };
function emit_block(  b) { if (no > 0 && !blank(out[no])) emit(""); blockpos = no + 1; for (b = 1; b <= nb; b++) emit(B[b]); pad = 1; };
{ sub(/\r$/, ""); L[++n] = $0; }
END {
  marker = ENVIRON["PF_MARKER"]; endm = ENVIRON["PF_END"]; caption = ENVIRON["PF_CAPTION"];
  oldm = ENVIRON["PF_OLD"]; oldend = ENVIRON["PF_OLD_END"];
  nb = 0; no = 0; pad = 0; s = 0; e = 0; ins = -1; blockpos = 0; nn = 0;
  B[++nb] = marker; B[++nb] = ""; B[++nb] = ENVIRON["PF_EMBED"];
  if (caption != "") { B[++nb] = ""; B[++nb] = caption; }
  B[++nb] = ""; B[++nb] = endm;
  nbk = 0; lnb = 0; for (i = 1; i <= n; i++) { if (!blank(L[i])) { nbk++; lnb = i; } } if (!nbk) n = 0;
  for (i = 1; i <= n; i++) { if (ours(L[i])) { s = i; break; } }
  if (s) {
    mode = "marker";
    for (j = s + 1; j <= n; j++) { if (ours_end(L[j])) { e = j; break; } }
    if (!e) { e = s; j = s + 1; while (j <= n && blank(L[j])) j++; if (j <= n && embedish(L[j])) e = j; }
  } else if (ENVIRON["PF_REPLACE"] == "1") {
    c = 0;
    for (i = 1; i <= n; i++) { if (asset_line(L[i])) { c++; li = i; } }
    if (c == 1) { mode = "replaced-unmarked"; s = li; e = li; }
    else note[++nn] = "--replace-unmarked: found " c " bare video URL lines, not exactly one; replaced none";
  }
  if (!s) {
    i = 1;
    while (i <= n) {
      if (blank(L[i]) || ours_end(L[i])) { i++; continue; }
      if (heading(L[i]) && !demo(L[i])) { i++; continue; }
      if (L[i] ~ /^[ \t]*<!--/) { while (i <= n && L[i] !~ /-->/) i++; i++; continue; }
      break;
    }
    if (n == 0) { mode = "top"; ins = 0; }
    else if (i > n) { mode = "end"; ins = n; }
    else if (demo(L[i])) { mode = "before-demo"; ins = i - 1; }
    else if (visual(L[i]) != "") { mode = "above-visual"; ins = i - 1; }
    else {
      mode = "after-summary"; ins = para_end(i); j = ins + 1;
      while (j <= n && blank(L[j])) j++;
      if (j <= n && ticket(L[j]) && visual(L[j]) == "") { mode = "after-ticket"; ins = para_end(j); }
    }
  }
  if (s == 0 && ins == 0) emit_block();
  for (i = 1; i <= n; i++) {
    if (s && i == s) { emit_block(); i = e; continue; }
    if (ours_end(L[i])) continue;
    emit_line(L[i]); pos[i] = no;
    if (s == 0 && i == ins) emit_block();
  }
  while (no > 0 && blank(out[no])) no--;
  for (i = lnb + 1; i <= n; i++) out[++no] = L[i];
  for (i = 1; i <= no; i++) print out[i];
  kept = 0;
  for (i = 1; i <= n; i++) {
    if (s && i >= s && i <= e) continue;
    k = visual(L[i]);
    if (k == "" || !(i in pos)) continue;
    if (!kept) { k1 = k; p1 = pos[i]; r1 = (pos[i] > blockpos ? "above" : "below"); }
    kept++;
  }
  if (kept == 1) note[++nn] = "kept your existing " k1 " at line " p1 "; added this take " r1 " it";
  if (kept > 1) note[++nn] = "kept " kept " existing visuals untouched (first: the " k1 " at line " p1 ", with this take " r1 " it)";
  print mode > ENVIRON["PF_PLACED"];
  print blockpos > ENVIRON["PF_PLACED"];
  print kept > ENVIRON["PF_PLACED"];
  for (i = 1; i <= nn; i++) print note[i] > ENVIRON["PF_PLACED"];
}' "$CUR" > "$NEW";

MODE="$(sed -n '1p' "$PLACED" 2>/dev/null)" || MODE='';
AT="$(sed -n '2p' "$PLACED" 2>/dev/null)" || AT='';
KEPT="$(sed -n '3p' "$PLACED" 2>/dev/null)" || KEPT='';
case "$KEPT" in ''|*[!0-9]*) KEPT=0 ;; esac;
case "$MODE" in
  marker) SAY="replacing the earlier take at the marker (line $AT)" ;;
  replaced-unmarked) SAY="replacing the unmarked video at line $AT (--replace-unmarked)" ;;
  after-ticket) SAY="adding this take after the ticket line (line $AT)" ;;
  after-summary) SAY="adding this take after the summary paragraph (line $AT)" ;;
  above-visual) SAY="adding this take above the visual the body opens with (line $AT)" ;;
  before-demo) SAY="adding this take above the Demo heading (line $AT)" ;;
  top) SAY="adding this take to the empty body" ;;
  end) SAY="adding this take at the end of the body; it has no summary paragraph (line $AT)" ;;
  *) fail 2 "could not place the embed in the body of PR #$PR" ;;
esac;
printf 'post: %s %s\n' "$FORMAT" "$SAY" >&2;
sed -n '4,$p' "$PLACED" | sed 's/^/post: /' >&2;

SEND="$TMPD/send.md";
SENT="$(cat "$NEW"; printf x)";
SENT="${SENT%x}";
printf '%s' "${SENT%$'\n'}" > "$SEND";

if [ "$DRY" = 1 ]; then
  KEEP_BODY="${ABS%.*}.pr-body.md";
  cp "$SEND" "$KEEP_BODY";
  diff -u --label "PR #$PR body now" --label "PR #$PR body after posting" "$CUR" "$NEW" || true;
  printf '\nfull new body: %s\n' "$KEEP_BODY";
  printf '\n--- gh argv (dry run: nothing uploaded or edited) ---\n';
  printf 'gh pr edit %q --body-file %q --attach %q\n' "$PR" "$KEEP_BODY" "$ATTACH";
  POSTED_DONE=1;
  printf 'POSTED {"ok":true,"dry_run":true,"pr":%s,"file":%s,"format":"%s","placement":"%s","kept_unmarked":%s,"url":null}\n' "$PR" "$(json_str "$ABS")" "$FORMAT" "$MODE" "$KEPT";
  exit 0;
fi;

gh pr edit "$PR" --body-file "$SEND" --attach "$ATTACH" > "$TMPD/edit.out" 2> "$ERR" || fail 8 "gh pr edit #$PR failed: $(tr '\n' ' ' < "$ERR" | cut -c 1-400)";

gh pr view "$PR" --json body -q .body > "$BACK" 2> "$ERR" || fail 4 "posted, but could not read PR #$PR back to verify: $(tr '\n' ' ' < "$ERR" | cut -c 1-300)";

if grep -qF -- "$ABS" "$BACK"; then fail 7 "the local path survived in PR #$PR (gh did not rewrite it): $ABS"; fi;
if grep -qi 'file://' "$BACK"; then fail 7 "a file:// reference is in the body of PR #$PR"; fi;
LOCAL="$(grep -nE '\]\(<?/(Users|home|private|tmp|var|Volumes|mnt|opt|root)/' "$BACK" | head -n 1)" || LOCAL='';
[ -z "$LOCAL" ] || fail 7 "a local absolute path is in the body of PR #$PR: $LOCAL";
LOCAL="$(grep -nE '^[[:space:]]*/(Users|home|private|tmp|var|Volumes|mnt|opt|root)/[^[:space:]]*\.(gif|png|jpe?g|mp4|webm|mov)[[:space:]]*$' "$BACK" | head -n 1)" || LOCAL='';
[ -z "$LOCAL" ] || fail 7 "a local media path is in the body of PR #$PR: $LOCAL";

FOUND="$(PF_MARKER="$MARKER" PF_END="$END_MARKER" awk '
function blank(s) { return s ~ /^[ \t]*$/; };
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s; };
{ sub(/\r$/, ""); L[++n] = $0; }
END {
  for (i = 1; i <= n; i++) { if (trim(L[i]) == ENVIRON["PF_MARKER"]) { m++; if (!s) s = i; } }
  if (!s) { print "NOMARKER"; exit; }
  j = s + 1; while (j <= n && blank(L[j])) j++;
  alone = (j <= n && (j + 1 > n || blank(L[j + 1]) || trim(L[j + 1]) == ENVIRON["PF_END"]) && (j - 1 == s || blank(L[j - 1]))) ? "alone" : "joined";
  print (m > 1 ? "DUP" : "ONE") " " alone " " (j <= n ? L[j] : "");
}' "$BACK")" || FOUND='';

case "$FOUND" in
  NOMARKER*|'') fail 7 "the $MARKER marker is missing from PR #$PR after the edit" ;;
  DUP*) fail 7 "PR #$PR carries more than one $MARKER marker" ;;
esac;
ALONE="$(printf '%s' "$FOUND" | cut -d ' ' -f 2)";
LINE="$(printf '%s' "$FOUND" | cut -d ' ' -f 3-)";
LINE="$(printf '%s' "$LINE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')";
URL_RE='https://[^ )<>]*/user-attachments/assets/[A-Za-z0-9-]+';
URL='';
if [ "$KIND" = image ]; then
  IMG_RE="^!\[[^]]*\]\(($URL_RE)\)$";
  if [[ "$LINE" =~ $IMG_RE ]]; then URL="${BASH_REMATCH[1]}"; fi;
else
  BARE_RE="^($URL_RE)$";
  if [[ "$LINE" =~ $BARE_RE ]] && [ "$ALONE" = alone ]; then URL="${BASH_REMATCH[1]}";
  elif [[ "$LINE" =~ $URL_RE ]]; then fail 7 "the video in PR #$PR is not a bare URL alone in its paragraph, so it will not play: $LINE";
  fi;
fi;
[ -n "$URL" ] || fail 7 "the embed under the marker in PR #$PR was not rewritten to a user-attachments URL: ${LINE:-<empty>}";

printf 'post: posted %s to PR #%s: %s\n' "$FORMAT" "$PR" "$URL" >&2;
POSTED_DONE=1;
printf 'POSTED {"ok":true,"pr":%s,"file":%s,"format":"%s","placement":"%s","kept_unmarked":%s,"url":%s}\n' "$PR" "$(json_str "$ABS")" "$FORMAT" "$MODE" "$KEPT" "$(json_str "$URL")";
