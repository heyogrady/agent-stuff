# Step 3: compose the PR title and body

Read when entering Step 3. It runs the gates that come before writing (ticket line, plan context, visuals) and hands off to `references/pr-description-writing.md`.

**Read `references/pr-description-writing.md` in full.** Its core principle governs every step, and its shape (a spine every PR shares, plus one of five type sections) is the target for every body. Read the matching example in `references/pr-description-examples.md` once Step A of the writing reference has picked the type. Pass it the PR ref when there is one (a ref on the invocation, or the existing PR Step 1 matched), so PR mode fetches the existing body and keeps its `Related:` / `Fixes` references.

## Prose register

Load `noslop` (resolve the name against the host's available-skills list; it may appear namespaced, such as `agent-stuff:noslop`) and hold it in **author** mode while composing: every sentence of the title and body passes its tests, on top of the writing reference's own rules. If `noslop` is not available, read `noslop`'s `references/patterns.md` when it is readable and apply that catalog; otherwise proceed under the writing reference alone and say so in one line of the report.

## Ticket line

Gather the ticket ID before composing:

1. **Find it.** Look in the branch name, the commit messages, and the user's prompt. Match `[A-Za-z]{2,10}-[0-9]+` case-insensitively and upper-case it (`proj-123` becomes `PROJ-123`). Skip conventional type words that happen to match (`feat-2`, `fix-12`, `release-3`). No match means no Linear-style ticket.
2. **Look it up**, first source that works:
   - **Linear MCP.** A tool from a Linear MCP server that fetches one issue (named like `get_issue`; match by capability). Read the URL, the parent, and the sub-issues.
   - **`linctl` CLI**, when it is on `PATH`: `linctl issue get <ID> --json`.
   - **Neither:** use the plain ID with no link. Use a match that appeared only in lowercase only when the branch-naming pattern carries `{ticket}`; otherwise leave the line out rather than guess.
3. **Pick the verb.**
   - Standalone issue (no parent, no children): `Resolves`.
   - Sub-issue with other open siblings: `Resolves`. The **last open sub-issue** under a parent: `Part of`, because closing it would close the parent too; tell the user.
   - Parent with open sub-issues: `Part of`.
   - Unknown hierarchy (plain-ID fallback): `Resolves`.
   - The user's explicit wording ("this is part of PROJ-12", "this resolves it") overrides detection.

Render `Resolves [PROJ-123](url)` or `Part of [PROJ-123](url)` on its own line directly after the lede. Never block on the tracker.

**GitHub issues** follow Step B1 of the writing reference: an issue number in the branch (`123-fix-login`, `issue-123`), the commits, or the prompt is a candidate. Use `Fixes #123` only when the PR targets the default branch and fully resolves it; otherwise `Related: #123`. A repo can carry both a Linear line and a GitHub reference.

## Plan context

A plan or spec path the caller passed is the plan. Otherwise look for one in the repo whose name matches the branch's ticket or slug (for example under `docs/plans/` or `docs/specs/`). Read what you find for the why, the decisions, and any pivots. It is a private source: the body states its content and never cites it.

## Shape and options

- **Body.** `full` (default) is the writing reference's full shape. `quick` (argument, or `body: quick`) is the lede, the ticket line, and visuals for a frontend change, whatever the change size. The Step E audit still runs on what remains.
- **Title style.** `title_style` picks the title rule in Step B: `repo` (default) follows the repo's existing PR titles or instructions when they clearly set a convention, else the outcome style; `outcome` and `conventional` force that style.
- **Options.** By default compose one title and body. Under `options`, compose three complete title-and-body options, each meeting every rule. They differ in the title and in what the lede leads with, never in accuracy.

## Visuals

Visuals apply when the diff touches frontend surfaces: views and templates, components, stylesheets, or UI JavaScript. Behavior by `visuals`:

- **`off`**: add none. A rewrite still keeps the visuals the existing body has.
- **`optional`** (default): try, in order, and stop at the first that works:
  1. **Existing captures.** Screenshots or recordings already produced in this session, or files the user names. Splice each into the body by absolute path and collect it for `--attach` (writing reference, **Attaching local files**).
  2. **`record-feature-video`**, when the host's skill list has it (it may appear namespaced). It films the change and posts it into the PR, so it runs in Step 4 after the PR exists. Note that here and compose the body without a visual.
  3. **A browser tool** in the current tool list, against a dev server that is already running: take before and after screenshots of the changed pages and splice them as in (1). Do not start servers or install tools for this.
  4. **None of these:** ship without visuals and say "frontend change shipped without visuals" in the report.
- **`required`**: as `optional`, but at step 4 ask the user for files or for an explicit go-ahead without them. In `mode:pipeline` never ask: ship and flag it.

Visuals never block an unattended run. For a non-frontend diff, include evidence only when it changes a reviewer's confidence (benchmarks, migration runs, API captures), per the writing reference.

## Compose and audit

Run Steps Pre-A through E of the writing reference. Step E is the pre-apply audit, mechanical pass first (local-source leaks, attribution, legacy headings, bold glossary), then the judgment pass. It runs before the body goes anywhere: before a preview, a printed description, or an apply.
