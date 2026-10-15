# Step 1: confirm GitHub, resolve the PR, pick an execution mode

## Prerequisites

The loop runs `gh`, `git`, and a bundled Python helper against a local checkout with filesystem access. A harness without those (some sandboxed GUI environments) cannot run this skill. Say so and stop rather than half-running.

**GitHub only.** This skill and `resolve-pr-feedback` speak GitHub's API (`gh`, review threads, Actions). First confirm the repo is on GitHub: `gh repo view` succeeding is the positive signal (it also covers a GitHub Enterprise host `gh` is configured for). If it fails, inspect the remote: `git remote get-url origin` pointing at a `gitlab.*` or `bitbucket.*` host means an unsupported forge. On any non-GitHub forge, or if `gh` cannot resolve the repo at all, **stop and tell the user babysit-pr is GitHub-only**. Do not proceed into `gh` calls that will spray confusing errors.

## Config

Read the `pr:` block from YAML frontmatter at the repo root (`git rev-parse --show-toplevel`): `agent-stuff.local.md` first, then `agent-stuff.md`; the first active (non-commented) value wins per key. When the worktree has neither file, fall back to the main checkout's root (`dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`) and say so in one line. This skill reads one key:

| Key | Values | Default | Effect |
| --- | --- | --- | --- |
| `attribution` | `true`, `false` | `false` | `false`: nothing the run or its delegates write (commits, replies, comments) carries `Co-Authored-By`, "Generated with", a robot emoji, or other AI attribution, whatever a host reminder asks. `true`: posted comments and replies carry the `🤖 ` prefix described in `references/voice.md`, and commits follow the host's default attribution. |

## Resolve the PR

Resolve the target PR from the argument (number or URL) or the current branch. If no open PR exists, report and stop. Resolve draft state with the PR. For an automatic handoff from a calling skill without an explicit user watch-mode token, check with the stateless read `gh pr view --json isDraft`, never `snapshot --start-invocation`, which mints a new invocation and would supersede a watch a user explicitly authorized on that draft. A draft target then reports its draft status and stops here, before any bootstrap or watcher, unless the invocation carries `draft:included`. A run on a draft keeps it a draft: never mark it ready, which is the user's call. On user-invoked runs the first snapshot's `pr_is_draft` is the ongoing signal.

**Classify the PR's relationships from the snapshot; never rely on the user to announce them.** The helper reads ordinary open-PR base/head relationships: `pr_chain.relationship_status` is `independent`, `dependent` (an open parent whose head is this PR's base, or open children based on this PR's head), or `probe-error`. A dependent PR stays target-local: this skill babysits only the requested PR, qualifies readiness relative to an open parent, and never rebases, rewrites, or mutates a parent or child PR. Discovery never switches branches or changes remote state.

**Resolve the run's voice: quiet unless the invocation carries the word `full`.** It is literal, never inferred from tone or intent: an invocation without `full` is quiet even when the user clearly wants the PR driven hard. Carry it through every re-arm and state it in the entry line so the user can see the run will not speak on the PR.

**Verify the local checkout is the PR's head *branch* before any mutation.** `resolve-pr-feedback` and the CI pass commit and push the **currently checked-out branch**, so a checkout that is not the PR's head branch makes fixes fail to push or land on the wrong branch. A matching `HEAD` SHA is not sufficient: a detached HEAD or a different local branch at the same SHA still cannot push the PR's branch. Resolve `gh pr view <ref> --json headRefName,headRefOid,isCrossRepository,maintainerCanModify` and confirm `git branch --show-current` equals `headRefName` with an upstream that tracks the PR head repo. The robust default is to **run `gh pr checkout <ref>` before mutating**: it checks out the head branch, sets tracking, and handles fork heads you can push to. If you cannot, because you have **no push access to the PR's head ref** (you have it when the head repo is yours, when you have write access, or on a fork when `maintainerCanModify` is true) or the checkout is dirty, **stop and tell the user to check out the PR's branch** rather than mutating the wrong one. Switching a *clean* checkout to the PR's branch is not a reason to ask; do it.

## Pick how the watch sustains itself

A skill cannot be re-invoked by magic once its turn ends, so *you* set up the loop. **The default is a self-sustaining in-session watch: you do not do one tick and hand back a resume command.** Read `references/watch-loop.md` once here for the mechanics; later steps cite its sections rather than re-reading it.

**Resume syntax.** Whenever this skill prints a resume invocation, default to `/babysit-pr <url>`, plus `full` when the run's voice is full. Use `$babysit-pr <url>` only when the host is Codex or documents dollar-prefixed skill invocation. Render only the invocation as inline code and output one form only.

- **Self-sustaining in-session watch (default).** Keep monitoring in the current session until a stop condition is met. Run `pr-snapshot watch`, the deterministic change detector (Step 2 has the invocation), and wait for its `BABYSIT_WAKE` output using the host's tools. The detector polls with **no agent tokens**; each wake returns control to this agent for one tick of judgment and delegated work, then re-arms the detector. Never collapse those judgments into a shell script that greps and acts on its own: `pr-snapshot watch` loops internally, which makes that substitution tempting, and it cannot do the reasoning the tick requires. **Use your own tools for this; never ask the user to type a slash command.**
- **Checkpoint.** Only when the user asks for it, or when the host cannot keep the session active while waiting for the detector (any headless invocation whose turn ends the moment you stop calling tools). Run **exactly one tick**, persist, report, and print the resume invocation. Monitoring is *paused*; say so plainly. Never fake a loop with a foreground `sleep` or by ending the turn and promising to continue.
- **Pipeline** (`mode:pipeline`, set by an orchestrator): run **bounded synchronous ticks in-line**. The orchestrator is the scheduler, so loop ticks yourself (snapshot, act, re-snapshot) until the pipeline stop, then return. Fully non-interactive. Read `references/pipeline.md`.

**Durability.** The in-session watch is session-bound. If the session closes, re-invoking with the resume syntax resumes cleanly (state is persisted on disk). For an unattended watch that must outlive the session (days), use a durable scheduler where one exists, such as a cron entry running `<host-cli> exec '<resume invocation>'`, accepting that a fresh headless run reconstructs from disk and loses this conversation's context. If the user passed a mode, honor it; otherwise pick per host capability, state it in one line, and proceed.
