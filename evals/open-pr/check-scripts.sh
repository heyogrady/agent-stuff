#!/usr/bin/env bash
# Deterministic checks for open-pr.
#
# L: lint-body.py against fixtures/: each bad fixture breaks exactly one rule
#    and the linter reports that rule and no other; each good one is clean.
# X: the worked examples in skills/open-pr/references/pr-description-examples.md,
#    extracted at run time, pass the same linter (the skill's examples follow
#    the skill's own rules).
# C: scripts/pr-config.py against throwaway git repos: defaults, local over
#    team, comments, invalid values, booleans, branch_naming as a whole map,
#    flow maps, the main-checkout fallback, and outside a repo.
#
# Usage: evals/open-pr/check-scripts.sh [check ids...]   KEEP=1 keeps scratch.
# Exit status: number of failed checks (0 = all pass).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
LINT="$HERE/lint-body.py"
CONFIG="$REPO/skills/open-pr/scripts/pr-config.py"
EXAMPLES="$REPO/skills/open-pr/references/pr-description-examples.md"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/open-pr-eval-XXXXXX")" && pwd -P)"
if [ "${KEEP:-0}" = 1 ]; then echo "scratch: $WORK"; else trap 'rm -r "$WORK"' EXIT; fi
FAILS=0
ONLY=" $* "

want() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }

lint() {
  local body="$1" title="${1%.md}.title"
  if [ -f "$title" ]; then
    python3 "$LINT" "$body" --title-style outcome --title "$(cat "$title")"
  else
    python3 "$LINT" "$body"
  fi
}

# --- L: the linter against fixtures ------------------------------------------

for f in "$HERE"/fixtures/good/*.md; do
  id="L-good-$(basename "$f" .md)"
  want "$id" || continue
  out="$(lint "$f")"
  [ -z "$out" ] && pass "$id" || fail "$id" "$(echo "$out" | head -3)"
done

for f in "$HERE"/fixtures/bad/*.md; do
  rule="$(basename "$f" .md)"
  id="L-bad-$rule"
  want "$id" || continue
  rules="$(lint "$f" | awk 'NF{print $1}' | sort -u | tr '\n' ' ')"
  [ "$rules" = "$rule " ] && pass "$id" || fail "$id" "reported [${rules% }], want [$rule]"
done

# --- X: the skill's own examples ---------------------------------------------

python3 - "$EXAMPLES" "$WORK/examples" <<'EOF'
import os, re, sys
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
text = open(src, encoding="utf-8").read()
pat = r"^## (.+?)\n\n\*\*Title:\*\* `(.+?)`\n\n(`{3,4})markdown\n(.*?)\n\3\n"
for m in re.finditer(pat, text, re.S | re.M):
    name = re.sub(r"\W+", "-", m.group(1).lower()).strip("-")
    open(os.path.join(out, name + ".md"), "w").write(m.group(4) + "\n")
    open(os.path.join(out, name + ".title"), "w").write(m.group(2) + "\n")
EOF
count=0
for f in "$WORK"/examples/*.md; do
  [ -f "$f" ] || continue
  count=$((count + 1))
  id="X-$(basename "$f" .md)"
  want "$id" || continue
  out="$(lint "$f")"
  [ -z "$out" ] && pass "$id" || fail "$id" $'\n'"$(echo "$out" | sed 's/^/       /')"
done
if want X-count; then
  [ "$count" -ge 5 ] && pass X-count || fail X-count "extracted $count examples; the format may have changed"
fi

# --- C: pr-config.py ---------------------------------------------------------

new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir" && git -C "$dir" init -q && git -C "$dir" -c user.email=t@example.test -c user.name=t commit -q --allow-empty -m init
  echo "$dir"
}
cfg() { (cd "$1" && python3 "$CONFIG"); }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
check() {  # id, output, needle...
  local id="$1" out="$2"; shift 2
  want "$id" || return 0
  for needle in "$@"; do
    has "$out" "$needle" || { fail "$id" "missing [$needle] in: $(echo "$out" | tr '\n' '|')"; return; }
  done
  pass "$id"
}

r="$(new_repo defaults)"
check C1-defaults "$(cfg "$r")" "draft=true  # default" "attribution=false  # default" "body=full  # default" \
  "title_style=repo  # default" "visuals=optional  # default" "branch_naming.pattern=  # default"

r="$(new_repo team)"
printf -- '---\npr:\n  draft: false\n---\n' > "$r/agent-stuff.md"
check C2-team "$(cfg "$r")" "draft=false  # $r/agent-stuff.md"

r="$(new_repo local-wins)"
printf -- '---\npr:\n  draft: false\n  body: quick\n---\n' > "$r/agent-stuff.md"
printf -- '---\npr:\n  draft: true\n---\n' > "$r/agent-stuff.local.md"
check C3-local-wins "$(cfg "$r")" "draft=true  # $r/agent-stuff.local.md" "body=quick  # $r/agent-stuff.md"

r="$(new_repo commented)"
printf -- '---\npr:\n  # draft: false\n  visuals: off\n---\n' > "$r/agent-stuff.local.md"
check C4-commented "$(cfg "$r")" "draft=true  # default" "visuals=off"

r="$(new_repo invalid)"
printf -- '---\npr:\n  body: long\n---\n' > "$r/agent-stuff.local.md"
printf -- '---\npr:\n  body: quick\n---\n' > "$r/agent-stuff.md"
check C5-invalid-falls-through "$(cfg "$r")" "body=quick  # $r/agent-stuff.md" "note=ignored invalid pr.body='long'"

r="$(new_repo booleans)"
printf -- '---\npr:\n  attribution: yes\n  draft: off\n---\n' > "$r/agent-stuff.local.md"
check C6-booleans "$(cfg "$r")" "attribution=true" "draft=false"

r="$(new_repo inline-comment)"
printf -- '---\npr:\n  title_style: outcome  # house style\n---\n' > "$r/agent-stuff.local.md"
check C7-inline-comment "$(cfg "$r")" "title_style=outcome  # $r/agent-stuff.local.md"

r="$(new_repo naming-map)"
printf -- '---\npr:\n  branch_naming:\n    pattern: "feature/{ticket}-{slug}"\n    pattern_no_ticket: "feature/{slug}"\n---\n' > "$r/agent-stuff.md"
printf -- '---\npr:\n  branch_naming:\n    pattern: "po/{ticket}-{slug}"\n---\n' > "$r/agent-stuff.local.md"
check C8-naming-whole-map "$(cfg "$r")" "branch_naming.pattern=po/{ticket}-{slug}" \
  "branch_naming.pattern_no_ticket=  # $r/agent-stuff.local.md"

r="$(new_repo flow-map)"
printf -- '---\npr:\n  branch_naming: { pattern: "feature/{ticket}-{slug}", pattern_no_ticket: "feature/{slug}" }\n---\n' > "$r/agent-stuff.md"
check C9-flow-map "$(cfg "$r")" "branch_naming.pattern=feature/{ticket}-{slug}" "branch_naming.pattern_no_ticket=feature/{slug}"

r="$(new_repo quoted-hash)"
printf -- '---\npr:\n  branch_naming:\n    pattern: "fix/#{slug}"  # a comment\n---\n' > "$r/agent-stuff.md"
check C10-quoted-hash "$(cfg "$r")" "branch_naming.pattern=fix/#{slug}"

r="$(new_repo other-block)"
printf -- '---\nfeature_video:\n  draft: false\npr:\n  body: quick\n---\n' > "$r/agent-stuff.md"
check C11-other-block "$(cfg "$r")" "draft=true  # default" "body=quick"

r="$(new_repo no-frontmatter)"
printf 'pr:\n  draft: false\n' > "$r/agent-stuff.md"
check C12-no-frontmatter "$(cfg "$r")" "draft=true  # default"

r="$(new_repo main-checkout)"
printf -- '---\npr:\n  draft: false\n---\n' > "$r/agent-stuff.md"
git -C "$r" worktree add -q "$WORK/linked-worktree" -b eval-wt 2>/dev/null
check C13-main-fallback "$(cfg "$WORK/linked-worktree")" "draft=false  # $r/agent-stuff.md" \
  "note=worktree has no config; using the main checkout's"

if want C14-not-a-repo; then
  mkdir -p "$WORK/plain"
  out="$(cd "$WORK/plain" && GIT_CEILING_DIRECTORIES="$WORK" python3 "$CONFIG")"; code=$?
  [ "$code" = 1 ] && has "$out" "error=not a git repository" && pass C14-not-a-repo \
    || fail C14-not-a-repo "exit $code: $out"
fi

echo "failures: $FAILS"
exit "$FAILS"
