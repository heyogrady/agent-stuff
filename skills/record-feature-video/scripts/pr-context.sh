#!/usr/bin/env bash
# pr-context.sh -- one compact digest of what a feature video would film, and
# whether there is anything to film at all.
#
# Usage: pr-context.sh [PR]
#
#   PR       a PR number; default: the PR for the current branch. With no PR,
#            the current branch is diffed against the default branch
#            (git diff --name-only <base>...HEAD).
#
# Config: the feature_video: block in agent-stuff.local.md, else in
# agent-stuff.md, at the repo root (a feature_video: block in the local file
# replaces the tracked one whole). A worktree with neither file reads the main
# checkout's, named on a CONFIG: line.
#
# Prints: the PR (number, title, head, base, state, URL) or the branch and base;
# the ticket key from the branch name; CONFIG: when the main checkout's config
# is used; FEATURE_VIDEO: the file the block came from and the knobs it sets
# (format, gif_max_seconds, auto_post, review_dir); WARNING: when that file
# (or the cookies_file / storage_state it names) holds credentials and is not
# git-ignored; DEV_SERVER: the localhost ports served by processes running from
# this worktree (below 32768: a sandbox's proxy on an ephemeral port runs from
# the worktree too), and a localhost BASE_URL moved onto that port when exactly
# one is served and it differs from config (per-worktree ports); the changed
# files by kind (ui, backend, tests, docs, config, other); VERDICT: FILM or
# VERDICT: SKIP (<reason>), SKIP when no UI-facing file changed or
# feature_video.enabled is false; up to 15 UI files, markup and components
# first (tsx, jsx, vue, svelte, erb, html, ..., and anything under app/views or
# app/components), then stylesheets, then the rest (logic, fixtures); when no
# markup or component file changed, "hint: no component changed; find the
# screen that renders <module basenames>"; the PR body (BODY:) up to its first
# image, video, or <details>, at most 40 lines of 300 characters, with HTML
# comments dropped, so the claims list arrives without another gh call.
#
# It takes no base URL: BASE_URL is feature_video.base_url from config, or
# "not configured (pass a base URL)", meaning the caller's argument decides.
#
# UI-facing: views and templates (erb, haml, slim, html, liquid, hbs, ejs),
# components and pages (jsx, tsx, vue, svelte, astro), stylesheets (css, scss,
# sass, less), app/views, app/components, app/assets, JS/TS under
# app/javascript, src, frontend, web, client, ui, components, pages, routes,
# or app (except under api/ or server/), and Windmill-style app folders: every
# file in a <name>.raw_app/ folder except its backend/ runnables and package
# manifests, and every file in a low-code <name>.app/ folder. Tests (*_test.*,
# *.test.*, *.spec.*, *_spec.*, test_*.py, spec/, test/, tests/, __tests__/,
# e2e/, cypress/) and docs (*.md, *.mdx, *.rst, docs/) are never UI.
#
# Read-only. Exits 0, SKIP included; 2 only for a bad argument.
# Flatten-safe: every interior statement ends in ';' or a connector, with no
# heredocs, backslash continuations, or comments below this header.
set -uo pipefail;

PR_ARG='';
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) echo 'usage: pr-context.sh [PR]'; exit 0 ;;
    -*) echo "pr-context: unknown flag: $1" >&2; exit 2 ;;
    *) PR_ARG="${1#\#}"; shift ;;
  esac;
done;
case "$PR_ARG" in *[!0-9]*) echo "pr-context: PR must be a number, got: $PR_ARG" >&2; exit 2 ;; esac;

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || TOP='';
if [ -z "$TOP" ]; then echo 'VERDICT: SKIP (not a git repository)'; exit 0; fi;
cd "$TOP" || exit 0;

fm_get() {
  [ -f "$1" ] || return 0;
  PF_KEY="$2" PF_SUB="${3:-}" awk '
  function clean(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v); if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2); return v; }
  NR == 1 { if ($0 !~ /^---[ \t]*$/) exit; next; }
  /^---[ \t]*$/ { exit; }
  { sub(/\r$/, ""); }
  ENVIRON["PF_SUB"] == "" { if (index($0, ENVIRON["PF_KEY"] ":") == 1) { v = clean(substr($0, length(ENVIRON["PF_KEY"]) + 2)); if (v != "") { print v; exit; } } next; }
  /^[^ \t#]/ { inside = (index($0, ENVIRON["PF_KEY"] ":") == 1); next; }
  inside { t = $0; sub(/^[ \t]+/, "", t); if (index(t, ENVIRON["PF_SUB"] ":") == 1) { v = clean(substr(t, length(ENVIRON["PF_SUB"]) + 2)); if (v != "") { print v; exit; } } }
  ' "$1";
};

fm_has() {
  [ -f "$1" ] || return 1;
  PF_KEY="$2" awk '
  NR == 1 { if ($0 !~ /^---[ \t]*$/) exit 1; next; }
  /^---[ \t]*$/ { exit 1; }
  { sub(/\r$/, ""); if (index($0, ENVIRON["PF_KEY"] ":") == 1) { found = 1; exit; } }
  END { exit !found; }
  ' "$1";
};

not_ignored() {
  git -C "$1" check-ignore -q -- "$2" 2>/dev/null;
  [ $? = 1 ];
};

CFG_DIR="$TOP"; LOCAL_CFG='agent-stuff.local.md'; TEAM_CFG='agent-stuff.md';
MAIN_TOP="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || MAIN_TOP='';
[ -z "$MAIN_TOP" ] || MAIN_TOP="$(dirname "$MAIN_TOP")";
if [ ! -f "$LOCAL_CFG" ] && [ ! -f "$TEAM_CFG" ] && [ -n "$MAIN_TOP" ] && [ "$MAIN_TOP" != "$TOP" ] && { [ -f "$MAIN_TOP/$LOCAL_CFG" ] || [ -f "$MAIN_TOP/$TEAM_CFG" ]; }; then
  CFG_DIR="$MAIN_TOP"; LOCAL_CFG="$MAIN_TOP/agent-stuff.local.md"; TEAM_CFG="$MAIN_TOP/agent-stuff.md";
  echo "CONFIG: this worktree has no agent-stuff.local.md or agent-stuff.md; using the main checkout's ($MAIN_TOP)";
fi;
FV_CFG='';
for cfg in "$LOCAL_CFG" "$TEAM_CFG"; do
  if fm_has "$cfg" feature_video; then FV_CFG="$cfg"; break; fi;
done;

if [ -n "$FV_CFG" ]; then
  case "$(fm_get "$FV_CFG" feature_video enabled | tr '[:upper:]' '[:lower:]')" in
    false|no|off|0) echo "VERDICT: SKIP (feature_video.enabled is false in $FV_CFG)"; exit 0 ;;
  esac;
  KNOBS='';
  for k in format gif_max_seconds auto_post review_dir; do
    v="$(fm_get "$FV_CFG" feature_video "$k")";
    [ -z "$v" ] || KNOBS="$KNOBS $k=$v";
  done;
  echo "FEATURE_VIDEO: from $FV_CFG${KNOBS:+;$KNOBS}";
  CREDS='';
  for k in password cookies_file storage_state; do
    [ -z "$(fm_get "$FV_CFG" feature_video "$k")" ] || CREDS="$CREDS, $k";
  done;
  if [ -n "$CREDS" ] && not_ignored "$CFG_DIR" "$FV_CFG"; then
    echo "WARNING: $FV_CFG sets feature_video ${CREDS#, } but is not git-ignored, so it could be committed; move credentials to an ignored agent-stuff.local.md";
  fi;
  for k in cookies_file storage_state; do
    v="$(fm_get "$FV_CFG" feature_video "$k")";
    case "$v" in ''|/*|'~'*) continue ;; esac;
    if [ -e "$CFG_DIR/$v" ] && not_ignored "$CFG_DIR" "$v"; then echo "WARNING: feature_video.$k ($v) is not git-ignored, so it could be committed"; fi;
  done;
fi;

BRANCH="$(git symbolic-ref -q --short HEAD 2>/dev/null)" || BRANCH='';

HAVE_PR=0; NUM=''; TITLE=''; HEAD=''; BASE_REF=''; STATE=''; URL=''; FILES=''; BODY='';
if command -v gh >/dev/null 2>&1; then
  META="$(gh pr view ${PR_ARG:+"$PR_ARG"} --json number,title,headRefName,baseRefName,state,url,files --jq '.number, .title, .headRefName, .baseRefName, .state, .url, (.files[]?.path)' 2>/dev/null)" || META='';
  NUM="$(printf '%s\n' "$META" | sed -n '1p')";
  case "$NUM" in ''|*[!0-9]*) NUM='' ;; *) HAVE_PR=1 ;; esac;
fi;

if [ "$HAVE_PR" = 1 ]; then
  TITLE="$(printf '%s\n' "$META" | sed -n '2p')";
  HEAD="$(printf '%s\n' "$META" | sed -n '3p')";
  BASE_REF="$(printf '%s\n' "$META" | sed -n '4p')";
  STATE="$(printf '%s\n' "$META" | sed -n '5p')";
  URL="$(printf '%s\n' "$META" | sed -n '6p')";
  FILES="$(printf '%s\n' "$META" | sed -n '7,$p')";
  BODY="$(gh pr view "$NUM" --json body --jq .body 2>/dev/null)" || BODY='';
  echo "PR: #$NUM $TITLE";
  echo "    $STATE  head=$HEAD  base=$BASE_REF  $URL";
  if [ -z "$FILES" ]; then
    for c in "origin/$BASE_REF" "$BASE_REF"; do
      if git rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1; then FILES="$(git diff --name-only "$c...HEAD" 2>/dev/null)" || FILES=''; break; fi;
    done;
  fi;
else
  BASE_REF="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" || BASE_REF='';
  for c in origin/main origin/master main master; do
    [ -z "$BASE_REF" ] || break;
    if git rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1; then BASE_REF="$c"; fi;
  done;
  if [ -n "$PR_ARG" ]; then echo "PR: #$PR_ARG not found (gh missing, unauthenticated, or no such PR); using git"; else echo "PR: none for ${BRANCH:-detached HEAD}; using git"; fi;
  echo "    branch=${BRANCH:-detached}  base=${BASE_REF:-unknown}";
  if [ -n "$BASE_REF" ]; then FILES="$(git diff --name-only "$BASE_REF...HEAD" 2>/dev/null)" || FILES=''; fi;
fi;

TBRANCH="${HEAD:-$BRANCH}";
TICKET="$(printf '%s' "$TBRANCH" | awk '{ n = split($0, w, /[\/_-]/); for (i = 1; i < n; i++) { if (w[i] ~ /^[A-Za-z][A-Za-z0-9]?[A-Za-z0-9]?[A-Za-z0-9]?[A-Za-z0-9]?[A-Za-z0-9]?$/ && length(w[i]) >= 2 && w[i] !~ /^[0-9]+$/ && tolower(w[i]) !~ /^(feat|fix|bug|bugfix|hotfix|chore|release|wip|docs|test|tests|refactor|bump|pr|issue|issues|v)$/ && w[i + 1] ~ /^[0-9]+$/) { print toupper(w[i]) "-" w[i + 1]; exit; } } }')";
if [ -n "$TICKET" ]; then echo "TICKET: $TICKET"; else echo "TICKET: none in branch name"; fi;

BASE_URL=''; BASE_URL_SRC='';
if [ -n "$FV_CFG" ]; then
  BASE_URL="$(fm_get "$FV_CFG" feature_video base_url)";
  BASE_URL_SRC="$FV_CFG";
fi;

DEV_PORTS=''; CFG_PORT=''; CFG_OWNER='';
case "$BASE_URL" in
  http://localhost*|http://127.0.0.1*|https://localhost*|https://127.0.0.1*)
    CFG_PORT="$(printf '%s' "$BASE_URL" | sed -n 's#^[a-z]*://[^/:]*:\([0-9][0-9]*\).*#\1#p')";
    [ -n "$CFG_PORT" ] || case "$BASE_URL" in https*) CFG_PORT=443 ;; *) CFG_PORT=80 ;; esac ;;
esac;
if command -v lsof >/dev/null 2>&1; then
  LISTEN="$(lsof -nP -iTCP -sTCP:LISTEN -Fpn 2>/dev/null | awk '/^p/ { pid = substr($0, 2) } /^n/ { n = $0; sub(/.*:/, "", n); if (n + 0 < 32768) print pid, n }' | sort -u)";
  PIDS="$(printf '%s\n' "$LISTEN" | awk 'NF { print $1 }' | sort -u | paste -sd, -)";
  if [ -n "$PIDS" ]; then
    CWDS="$(lsof -a -p "$PIDS" -d cwd -Fpn 2>/dev/null | awk '/^p/ { pid = substr($0, 2) } /^n\// { print pid, substr($0, 2) }')";
    DEV_PORTS="$(printf '%s\n' "$CWDS" | awk -v top="$TOP/" '{ d = substr($0, index($0, " ") + 1) "/"; if (index(d, top) == 1) print $1 }' | while read -r pid; do printf '%s\n' "$LISTEN" | awk -v p="$pid" '$1 == p { print $2 }'; done | sort -un | paste -sd' ' -)";
    if [ -n "$CFG_PORT" ]; then
      CFG_OWNER="$(printf '%s\n' "$LISTEN" | awk -v port="$CFG_PORT" '$2 == port { print $1 }' | while read -r pid; do printf '%s\n' "$CWDS" | awk -v p="$pid" '$1 == p { print substr($0, index($0, " ") + 1) }'; done | sort -u | head -1)";
    fi;
  fi;
fi;
case " $DEV_PORTS " in
  "  ") if [ -n "$CFG_OWNER" ]; then echo "DEV_SERVER: none running from this worktree (:$CFG_PORT is served from $CFG_OWNER); start this worktree's own and let its command pick the port"; else echo "DEV_SERVER: none running from this worktree"; fi ;;
  *) echo "DEV_SERVER: :$(printf '%s' "$DEV_PORTS" | sed 's/ /, :/g') served from this worktree" ;;
esac;
MOVE=0;
case " $DEV_PORTS " in "  "|*" $CFG_PORT "*|*" "*" "*" "*) ;; *) [ -n "$CFG_PORT" ] && MOVE=1 ;; esac;
if [ "$MOVE" = 1 ]; then
  NEW_URL="$(printf '%s' "$BASE_URL" | sed "s#^\([a-z]*://[^/:]*\)\(:[0-9]*\)\{0,1\}#\1:$DEV_PORTS#")";
  echo "BASE_URL: $NEW_URL  (feature_video.base_url in $BASE_URL_SRC, on this worktree's dev-server port; config says :$CFG_PORT)";
elif [ -n "$BASE_URL" ]; then echo "BASE_URL: $BASE_URL  (feature_video.base_url in $BASE_URL_SRC)";
else echo "BASE_URL: feature_video.base_url not configured (pass a base URL)"; fi;

kind_of() {
  local f="$1" b="${1##*/}";
  case "$f" in
    *_test.*|*.test.*|*.spec.*|*_spec.*|test_*.py|*/test_*.py|spec/*|*/spec/*|test/*|*/test/*|tests/*|*/tests/*|__tests__/*|*/__tests__/*|e2e/*|*/e2e/*|cypress/*|*/cypress/*) echo tests; return ;;
    *.md|*.mdx|*.markdown|*.rst|docs/*|*/docs/*) echo docs; return ;;
    *.raw_app/backend/*) echo backend; return ;;
    *.raw_app/package.json|*.raw_app/package-lock.json|*.raw_app/.gitignore) echo config; return ;;
    *.raw_app/*|*.app/*) echo ui; return ;;
  esac;
  case "$b" in
    package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb|Gemfile|Gemfile.lock|Dockerfile|*.dockerfile|Makefile|Procfile|*.config.js|*.config.cjs|*.config.mjs|*.config.ts|tsconfig*.json|.env*|*.toml|*.ini|*.lock|requirements*.txt|go.mod|go.sum|.gitignore|.tool-versions|.ruby-version|.node-version|.nvmrc|.editorconfig|.eslintrc*|.prettierrc*) echo config; return ;;
  esac;
  case "$f" in
    .github/*|.circleci/*|config/*|*/config/*|helm/*|deploy/*|infra/*|terraform/*|*.yml|*.yaml) echo config; return ;;
    app/views/*|*/app/views/*|app/components/*|*/app/components/*|app/assets/*|*/app/assets/*) echo ui; return ;;
    *.erb|*.haml|*.slim|*.html|*.htm|*.liquid|*.hbs|*.ejs|*.jsx|*.tsx|*.vue|*.svelte|*.astro|*.css|*.scss|*.sass|*.less) echo ui; return ;;
    api/*|*/api/*|server/*|*/server/*) echo backend; return ;;
  esac;
  case "$f" in
    *.js|*.mjs|*.cjs|*.ts|*.mts)
      case "$f" in
        app/javascript/*|*/app/javascript/*|src/*|*/src/*|frontend/*|*/frontend/*|web/*|*/web/*|client/*|*/client/*|ui/*|*/ui/*|components/*|*/components/*|pages/*|*/pages/*|routes/*|*/routes/*|app/*|*/app/*) echo ui; return ;;
      esac ;;
  esac;
  case "$f" in
    *.rb|*.py|*.go|*.rs|*.java|*.kt|*.scala|*.ex|*.exs|*.php|*.cs|*.sql|*.sh|*.js|*.mjs|*.cjs|*.ts|*.mts|*.rake|db/*|*/db/*|lib/*|*/lib/*|bin/*|migrations/*|*/migrations/*) echo backend; return ;;
  esac;
  echo other;
};

N_ALL=0; N_UI=0; N_BE=0; N_TS=0; N_DOC=0; N_CFG=0; N_OTH=0;
L_UI=''; L_BE=''; L_TS=''; L_DOC=''; L_CFG=''; L_OTH='';
L_MARKUP=''; L_STYLE=''; L_LOGIC=''; N_MARKUP=0;
while IFS= read -r f; do
  [ -n "$f" ] || continue;
  N_ALL=$((N_ALL + 1));
  case "$(kind_of "$f")" in
    ui) N_UI=$((N_UI + 1));
      case "$f" in
        *.tsx|*.jsx|*.vue|*.svelte|*.astro|*.erb|*.haml|*.slim|*.html|*.htm|*.liquid|*.hbs|*.ejs|app/views/*|*/app/views/*|app/components/*|*/app/components/*) N_MARKUP=$((N_MARKUP + 1)); L_MARKUP="$L_MARKUP$f"$'\n' ;;
        *.css|*.scss|*.sass|*.less) L_STYLE="$L_STYLE$f"$'\n' ;;
        *) L_LOGIC="$L_LOGIC$f"$'\n' ;;
      esac ;;
    backend) N_BE=$((N_BE + 1)); L_BE="$L_BE$f"$'\n' ;;
    tests) N_TS=$((N_TS + 1)); L_TS="$L_TS$f"$'\n' ;;
    docs) N_DOC=$((N_DOC + 1)); L_DOC="$L_DOC$f"$'\n' ;;
    config) N_CFG=$((N_CFG + 1)); L_CFG="$L_CFG$f"$'\n' ;;
    *) N_OTH=$((N_OTH + 1)); L_OTH="$L_OTH$f"$'\n' ;;
  esac;
done <<< "$FILES";
L_UI="$L_MARKUP$L_STYLE$L_LOGIC";

group() {
  [ "$2" -gt 0 ] || return 0;
  local shown more;
  shown="$(printf '%s' "$3" | head -n 4 | tr '\n' ',' | sed 's/,$//; s/,/, /g')";
  more=$(($2 - 4));
  if [ "$more" -gt 0 ]; then echo "  $1 ($2): $shown, +$more more"; else echo "  $1 ($2): $shown"; fi;
};

echo "FILES: $N_ALL changed";
group ui "$N_UI" "$L_UI";
group backend "$N_BE" "$L_BE";
group tests "$N_TS" "$L_TS";
group docs "$N_DOC" "$L_DOC";
group config "$N_CFG" "$L_CFG";
group other "$N_OTH" "$L_OTH";

if [ "$N_ALL" = 0 ]; then
  echo "VERDICT: SKIP (no changed files against ${BASE_REF:-the base})";
elif [ "$N_UI" = 0 ]; then
  WHAT='';
  [ "$N_BE" = 0 ] || WHAT="$WHAT, backend $N_BE";
  [ "$N_TS" = 0 ] || WHAT="$WHAT, tests $N_TS";
  [ "$N_DOC" = 0 ] || WHAT="$WHAT, docs $N_DOC";
  [ "$N_CFG" = 0 ] || WHAT="$WHAT, config $N_CFG";
  [ "$N_OTH" = 0 ] || WHAT="$WHAT, other $N_OTH";
  echo "VERDICT: SKIP (no UI-facing files changed: ${WHAT#, })";
else
  echo "VERDICT: FILM";
  echo "UI_FILES:";
  printf '%s' "$L_UI" | head -n 15 | sed 's/^/  /';
  [ "$N_UI" -le 15 ] || echo "  +$((N_UI - 15)) more";
  if [ "$N_MARKUP" = 0 ]; then
    MODS="$(printf '%s' "$L_STYLE$L_LOGIC" | head -n 5 | sed 's|.*/||' | tr '\n' ',' | sed 's/,$//; s/,/, /g')";
    echo "hint: no component changed; find the screen that renders $MODS";
  fi;
fi;

if [ -n "$BODY" ]; then
  echo "BODY: (to the first image, video, or <details>; 40 lines at most)";
  printf '%s\n' "$BODY" | awk '
  { sub(/\r$/, ""); }
  incomment { if ($0 ~ /-->/) incomment = 0; next; }
  /^[ \t]*<!--/ { if ($0 !~ /-->/) incomment = 1; next; }
  /<details|<img[ >]|<video[ >]|!\[.*\]\(|\/user-attachments\/assets\// { exit; }
  /^[ \t]*$/ { if (shown) gap = 1; next; }
  { if (shown >= 40) { more = 1; exit; } if (gap) { print ""; gap = 0; } t = $0; if (length(t) > 300) t = substr(t, 1, 300) "..."; print "  " t; shown++; }
  END { if (more) print "  ..."; if (!shown) print "  <empty>"; }';
fi;
exit 0;
