# Repository context, branch, and PR state

Gather this in Step 1, and re-verify branch, remote, and PR state immediately before each consequential step (the push in Step 2, `gh pr create` in Step 4).

## Config

```bash
python3 "$SKILL_DIR/scripts/pr-config.py"
```

It prints one `key=value` line per `pr:` key with the file it came from (`default` when unset), then any `note=` lines (an invalid value it skipped, or a fallback to the main checkout's config). Print the fallback note to the user in one line. Keys and meanings: `references/config.md`. An invocation argument beats config for the run: `ready` beats `draft: true`, `quick` beats `body: full`.

## Commands

Run each command below as its **own** shell tool call: a single argv-style invocation (the program and its arguments). Do **not** join them with `;`, `&&`, `||`, pipes, `$(...)`, or redirects like `2>/dev/null`: that syntax parses only under POSIX shells and aborts under Windows PowerShell. Read each exit status directly. A non-zero exit is a normal state to interpret (no PR yet, no `origin/HEAD`, detached HEAD), not a failure to suppress.

Run them in order; the PR check needs the branch name:

| Command | Purpose | Non-zero exit / empty output means |
| --- | --- | --- |
| `git rev-parse --show-toplevel` | Repo root | Not a git repository: report and stop |
| `git status` | Working-tree state | (fails only outside a repo) |
| `git diff HEAD` | Uncommitted changes | Unborn repo with no commits yet |
| `git branch --show-current` | Current branch (`<branch>`) | Empty output = detached HEAD |
| `git log --oneline -10` | Recent commit and title style | Unborn repo, no history yet |
| `git rev-parse --abbrev-ref origin/HEAD` | Remote default branch | No `origin/HEAD` set; resolve below |
| `gh pr list --head <branch> --state open --json number,url,title,body,state,isDraft,headRefName,headRepositoryOwner` | Open PR for this branch (only once `<branch>` is non-empty) | Exit 0 with `[]` = no open PR. Non-zero = `gh` missing, unauthenticated, or offline: PR state is **unknown**, not "none" |

Pass the branch **name only**. Two traps:

- **Detached HEAD:** skip the PR check. `gh pr list` with an empty `--head` drops the filter and lists unrelated PRs. Check again after a branch exists.
- **Fork checkout:** never pass `<owner>:<branch>`. `gh pr list --head` does not accept it and silently returns `[]`, which reads as "no PR" and opens a duplicate. The PR lives on the base repo: rely on `gh`'s default-repo resolution, or pass `-R <base-owner>/<repo>` when the default is the fork.

Everything gathered here is a snapshot. Treat it as a hint, not ground truth.

## Default branch

Strip `origin/` from the `origin/HEAD` result. If that exited non-zero or returned bare `HEAD`, try `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`. If both fail, use `main`.

## Branch path

- **Detached HEAD**: create a feature branch from `HEAD` (`git checkout -b <name>`), re-read `git branch --show-current`, and use it from here on. Do not ask; running this skill is the confirmation. On a name collision pick a free suffix.
- **Default branch with work** (uncommitted, unpushed, or no upstream): create a feature branch in Step 2 via `references/branch-creation.md`. Pushing the default branch is not supported. Do not ask whether to branch.
- **Default branch with no work**: report that there is nothing to ship and stop.
- **Feature branch**: continue.

**Naming a new branch.** Derive a kebab-case summary of the change. When `branch_naming.pattern` is set, the name must follow it: substitute `{slug}` with that summary and `{ticket}` with the ticket ID from context (prompt, commits, plan, tracker), rendered lowercase (`PROJ-123` becomes `proj-123`). When the pattern needs `{ticket}` and none is known, use `branch_naming.pattern_no_ticket` if set, else ask (in `mode:pipeline`, fall back to the plain summary and say so). Unset means no constraint.

## Matching an existing PR

With a non-empty result, do **not** take index 0. `--head` filters by branch name only, so another fork's PR can share it. Pick the entry whose `headRepositoryOwner` and `headRefName` match the head this run pushes. Several candidates and none confirmable: stop and show them. Note the matched URL and body: Step 4 uses the URL to choose create versus edit, and Step 3 uses the body as context to preserve.

## Commit convention

Match the repo: project instructions in context, then the style of recent commits. With neither, use the default: a Title Case imperative subject of at most 50 characters, leading with the outcome or user-visible why when the change has one ("Speed Up Login With A Session Cache") and the plain what otherwise ("Bump Rails To 7.2"); a blank line; then a body of `- ` bullets, imperative and terse, backticks around identifiers. A trivial single-purpose change may omit the body.

When the repo uses conventional commits, prefer `fix:` over `feat:` when ambiguous: code that remedies broken or missing behavior is `fix:`. Reserve `feat:` for something the user could not do before. PR titles follow their own rules (Step B of `references/pr-description-writing.md`).
