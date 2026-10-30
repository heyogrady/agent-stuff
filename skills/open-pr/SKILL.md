---
name: open-pr
description: "Commit a dirty or clean tree, push, and open a draft PR with a reader-first description, or refresh an existing PR's description. Adds a Linear or GitHub ticket line and visuals for UI changes."
argument-hint: "[PR#|URL] [describe-only] [ready] [quick] [options] [exclude:<paths>] [mode:pipeline]"
disable-model-invocation: true
---

# Open a PR

Ship the work on this branch to a pull request whose description a teammate who did not watch the work can read: commit what is uncommitted, push, then open a new PR or refresh the existing one's description.

```bash
SKILL_DIR="<absolute path of the directory containing this SKILL.md>"
```

**Asking the user:** use the host's blocking question tool when one is in the current tool list (match by capability, not by a host-specific name); otherwise ask in chat. Never silently skip a question.

## Arguments

| Argument | Effect |
|---|---|
| `PR#` or URL | Refresh that PR's description (preview, confirm, apply). No commit or push. |
| `describe-only` | Compose and print the title and body; apply nothing. With a PR ref, describes that PR. |
| `ready` | Open the new PR ready for review instead of as a draft. |
| `quick` | Short body: lede, ticket line, and visuals for a frontend change. |
| `options` | Compose three title-and-body options and let the user pick before applying. |
| `exclude:<paths>` | Never stage or commit these paths; report them as left out. |
| `mode:pipeline` | Non-interactive run for a caller that invoked this skill explicitly. |

Plain-language requests map the same way: "write a PR description" is `describe-only`; "rewrite the description of #123" is a refresh.

## Modes

- **Describe-only**: Step 1 (config and PR ref only), Step 3, then print. It works on a PR in any state (open, closed, or merged), since nothing is applied. Apply only if the user then asks, and only to an open PR.
- **Refresh**: resolve the PR. An exit-0 `[]` or a closed PR means there is nothing to refresh: report and stop. A non-zero exit means **unknown**: resolve auth or connectivity, then stop until it is known. With an open PR, run Step 3 on it, then Step 4's refresh path.
- **Full workflow** (default): Steps 1-4.

**`mode:pipeline`** suppresses every question and takes the conservative default for each: no rewrite of an existing PR's description, the current branch kept, an unresolvable base or branch choice stopping with a report rather than a guess, a refresh applied without preview (the invocation is the apply intent), and `options` ignored. A refresh in this mode never commits or pushes. Visuals come only from files the caller passed, captures already made in the run, or `record-feature-video` run unattended; a frontend change with none ships flagged.

## Three rules for every run

1. **Every `git` and `gh` probe is its own argv-form call** (no `;`, `&&`, pipes, `$(...)`, or redirects), and its exit status is control flow. `references/context.md` gives the reason.
2. **Probe output is a snapshot.** Re-verify branch, remote, and PR state right before each consequential action: the push in Step 2 and the create in Step 4.
3. **Only an exit-0 `[]` from a query against the base repo means "no open PR."** A non-zero exit is **unknown**, never "none". On a fork, target the base repo and pass the branch name only. With several results, match head owner and branch; never take index 0 blindly.

## Step 1: Config and context

**Read `references/context.md`.** It runs `scripts/pr-config.py` (keys and defaults in `references/config.md`), lists the context commands, and resolves the default branch, the branch path, the existing PR, and the commit convention. Never ask whether to branch: a detached HEAD, or the default branch with work on it, gets a new branch; the default branch with no work reports and stops.

## Step 2: Commit and push

**Read `references/commit-and-push.md`** (it points to `references/branch-creation.md` when on the default branch). Never `git add -A` or `git add .`; name files in both `add` and `commit`. Honor `exclude:<paths>`. With `attribution=false` (the default), no commit carries `Co-Authored-By` or any AI attribution. A project's pre-push requirements gate the push.

## Step 3: Compose the title and body

**Read `references/compose.md`, then `references/pr-description-writing.md` in full**, with the matching example from `references/pr-description-examples.md`. Before writing: decide the ticket line (Linear MCP, then `linctl`, then the plain ID from the branch; GitHub `Fixes #N` when it fully resolves an issue), read any plan for the why, and decide visuals. A defect fix takes the writing reference's Bug fix shape, fed by a caller's follow-ups list and any production-verification facts. Compose in `noslop`'s author mode. Step E of the writing reference is the audit before anything is shown or applied.

Read the full diff, never just the commit messages. Never invent the why: when the prompt, ticket, plan, and conversation do not carry it, ask (in `mode:pipeline`, state what changed and leave the motivation out).

## Step 4: Apply and report

**Read `references/apply.md`.** Before `gh pr create`, re-check PR presence: a matching PR takes the existing-PR path, exit-0 `[]` creates, non-zero blocks. Pass the body via `--body-file <path>`, never stdin; `gh` can exit 0 with an empty body. A new PR is a draft unless `ready` or `draft=false`. Read the body back after applying. Report the URL, draft or ready, the ticket line, excluded paths, and the visuals result.
