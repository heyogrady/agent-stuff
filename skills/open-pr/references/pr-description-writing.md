# PR Description Writing

## The core principle

The diff is already visible on GitHub. The description exists to explain what the diff cannot show: what a person using the software can do now that they could not before, what was broken and what they see instead, and how the code got there. Cut any sentence a reader could reconstruct from the diff itself.

- Bad: "Adds `retry_queue.rb`, modifies the upload handler to call it, and updates two test files."
- Good: "Uploads that fail mid-transfer now retry automatically instead of silently dropping the file."

If the lead sentence describes what was moved, renamed, or added rather than what's now possible or fixed, rewrite it. This applies to every section, not just the opening.

**The description teaches.** The reader is a teammate who did not watch the work: a reviewer deciding whether to approve, a stakeholder asking what changed, and a future engineer reading the merged PR to learn how a feature works. Write for all three at once by layering: user perspective first, code perspective second, everything else collapsed.

**Two readers, two altitudes.** The user perspective answers "what can I do now, what do I see?" in the product's own vocabulary. The code perspective answers "where does it live, how is it shaped, what is the one decision I would have questioned?" Do not blend them into one paragraph.

---

## The shape

**One rule sizes every description: a reader can stop at any heading and have a complete picture at that altitude.** After the lede, they know what changed for users. After the type section, they know what they would see. After *How it works*, they could review the code. Inside the collapsibles, they can reconstruct every decision and check every claim. There is no word budget. The test is whether each layer is complete on its own, not how long it runs. A tiny change is one layer deep; a large feature is all of them, twice over.

Length must track the change, not the session. A branch that took four sessions and a plan with twelve decisions still gets a description sized to what shipped. The session is source material for the *why*; it is not a table of contents.

### Spine — every PR

| # | Part | What it carries |
|---|---|---|
| 1 | **Lede** | 1–3 sentences. What is different for someone using the software, and why it matters. No heading, no label, no "In this PR,". The string "TL;DR" never appears anywhere in a body. |
| 2 | **Ticket line** | `Resolves …` / `Part of …` / `Related: …` on its own line (`references/compose.md`, then Step B1). Omitted when no ticket exists. |
| 3 | **Visual** | Video, Before/After table, diagram — directly under the ticket line, where a skimmer sees it (Step C). |
| 4 | **Type section** | Differs by PR type — see the table below. |
| 5 | **`## How it works`** | The code view. Where in the codebase, the shape of the change, and the one or two decisions a reviewer would question, each as a bold question with a short answer. Walk-through prose is fine for a multi-step flow. When the change touches a sequence — pipeline stages, numbered steps, a request's path through layers — show the whole sequence, one line per stage, and mark the stages that changed. A reader learning how it works needs the full path, not the three stages the diff touched. |
| 6 | **`## Worth knowing`** | Divergences from what was asked, follow-ups with their ticket numbers, what this PR deliberately does not do. Short bullets. |
| 7 | **Collapsibles** | Four `<details>` blocks at the very end, in this order, each present only with real content: **All decisions** · **In this PR** · **Verification** · **Post-deploy monitoring**. Everything a reviewer needs to approve is above them; everything they would want to check is inside them. |

Parts 5–7 appear only when they have content. A tiny PR is parts 1–2.

### Type sections — judged from the scope map (Step A)

| Type | Section(s) | Shape |
|---|---|---|
| **New feature** | `## What you can do now` | A numbered walk-through from the user's chair, each step with the screenshot that shows it. Then an optional **Background** paragraph glossing the domain in plain words, for a reader new to it. |
| **Large feature** — more than one user-facing capability, or a new subsystem | `## What you can do now` with one `###` per capability · `## How it fits together` replaces *How it works* | Each capability gets its own walk-through and its own screenshots. The code view opens with a component table or diagram showing how the pieces connect and the boundaries that hold the design together, then one `###` per capability (and per cross-cutting concern such as privacy or performance) for the mechanism. The lede names every capability in one breath. The stop-anywhere rule now holds at two levels: after the lede the reader knows the umbrella; after any `###` they know that one capability. |
| **Change to existing behavior** | `## Before / After` | A table (or two short paragraphs): what users used to see, what they see now, row by row where the change has facets. Then one line beginning **What did not change:** — reviewers worry about scope, so say it. Screenshot Before/After tables go first in this section. |
| **Bug fix** — any fix to a defect, error-tracker-driven included | `## What was wrong` · `## Summary` · `## Evidence` · `## Merge Danger` · `## Potential follow-ups` · `## Verify in production` | Shown and proved rather than told, for a reader who never opens the code and barely reads the PR. See *Bug fix sections* below. |
| **Tiny** — config, membership, dependency bump, one-line copy | none | Lede and ticket line. Nothing else. |

A refactor with no user-visible change is a *change to existing behavior* whose Before/After is about the code's shape, or *tiny* when the diff carries it. A performance change is a *change to existing behavior* whose Before/After table holds the measurements.

### Bug fix sections

The lede says what users saw go wrong and what they see now. After the ticket line come these sections, in this order. Write them as short bullets, tables, and visuals, never walls of text, in plain words at about a 10th-grade reading level; identifiers come after the plain words.

1. **`## What was wrong`** — three to five bullets, one line each, no paragraphs:
   - **What:** what broke, as a user saw it.
   - **Where:** the page or endpoint, then the file and line that raised.
   - **Cause:** one short sentence.
   - **Who / how often:** the users or event count and the dates, from the error tracker or the ticket. Omit the bullet when no source gives numbers.
   - **Since:** when the failing line arrived and by which change (`git log -S` or `git blame`), and whether this is a recent regression or latent. Omit the bullet when the history cannot be traced.
2. **`## Summary`** — the smallest visual that shows the bug, with at most one sentence of text; the cause lives in *What was wrong*. It takes the spine's visual slot and replaces *How it works*.
   - **Why this fix.** One sentence naming the obvious alternative and why this fix over it (a rescue over a non-bang save, a guard over a validation), when a reviewer would ask.
   - **A diagram, always.** For a backend or logic fix, a diff sketch, call tree, or Mermaid flow of the path before and after. A diff sketch is pseudocode in diff form: name the function or view, keep only the lines that carry the point, mark changed lines `-` and `+`. A one-line fix needs only a three-line diff sketch.
   - **A value table when the bug depends on input.** One row per input that matters — the values that broke and the nearest ones that did not — with *Before* and *After* columns.
   - **Screenshots for a frontend diff**, and a video when one exists, per the *Evidence and visuals* rule in Step C.
3. **`## Evidence`** — the proof, *Before* then *After*, next to each other. Show the test that reproduces the bug once, as given / when / then pseudocode.
   - **Before:** the failing run — command, failure message, example count. Name the commit where it failed when the history has the test committed before the fix.
   - **After:** the same test passing, with its command and count.

   Only output the run produced or the caller supplied goes here. With no failing run, say so in one line; never write one. Other checks (lint, the wider suite) stay in the *Verification* collapsible.
4. **`## Merge Danger`** — one line each:
   - **Door:** `one-way` or `two-way`, and why. A two-way door reverts cleanly. A migration that rewrites data, a sent email, or any other external write is one-way.
   - **Blast Radius:** one word (`tiny`, `small`, `wide`), then who or what the change touches.

   Add ramifications below only when they are real: records the bug never hit that now behave differently, a caller that relied on the old result.
5. **`## Potential follow-ups`** — what turned up while fixing this that the PR does not do. Take it from a caller's follow-ups list and from deferred work the conversation or plan names. Omit the section when there is none. Open with the line "Found while fixing this. None of it is in this PR." Then one table, most urgent first, every cell one short line:

   | Column | Holds |
   |---|---|
   | **Urgency** | One of the three grades below, and no other word. |
   | **Finding** | A bold headline of at most 8 words, in plain language. |
   | **Where** | The file, or the page. |
   | **Why it matters** | One sentence, no jargon. |
   | **How sure** | `Confirmed in code` or `Suspected`. |
   | **Next step** | A migration, a ticket (its number when one exists), a production count, or a spike. |

   The urgency grades:
   - **Do soon** — the same failure can still happen: the same cause in another place, or bad data still being written.
   - **Plan it** — a related risk that needs a decision, a migration, or a production count first.
   - **Nice to have** — cleanup; no failure expected.

   At most five rows. When there are more, keep the five most urgent and add one line below the table saying how many were left out.
6. **`## Verify in production`** — only when the failure depends on production data the run could not reproduce. One sentence says what could not be reproduced. Numbered steps follow for a person to run after deploy: the error tracker's issue link, the admin or record pages as root-relative links (`/admin/clients/<id>`), what each should show, and, last, watching the issue for new events before resolving it.

The collapsibles follow. In a bug fix, *Merge Danger* owns the rollback, *Verify in production* owns the post-deploy checks, and *Potential follow-ups* replaces *Worth knowing*; a divergence from what was asked goes in *All decisions*. The *Post-deploy monitoring* collapsible holds only what those sections leave out, and is omitted when that is nothing.

### What goes in each collapsible

Each opens with `<details><summary><strong>Name</strong></summary>`, a blank line, then markdown.

- **All decisions** — the long tail: what shipped and why, review findings applied (as what changed, not as a review narrative), findings rejected with the reason, accepted residuals as plain scope statements. When a plan or session settled a decision, the entry states the decision and its reason as self-contained content. Never "Reviewed by eight personas"; never a scorecard; never a count of findings. If a caller hands over an `Unapplied review findings` checkbox list, it lives at the top of this collapsible under a bold label, checkboxes intact, so a later pass can tick them.
- **In this PR** — the diff summary as a terse bullet list, written the way a commit body is: imperative, one bullet per grouped change, backticks around identifiers, no trailing periods, grouped under bold lead-ins when the PR has several areas. Tests ride as a bullet here. 3 bullets for a small branch, up to about 15 for a large one. This is the one place the body restates the diff, and it is collapsed because the diff is already on the next tab.
- **Verification** — what was run and what it showed. Open with the 2–4 bullets that matter: test counts, *the one check that actually proves the claim*, a staging or manual result in a sentence. Below them, the detail: run ids, tables, cell-by-cell readbacks, mutation results. Demonstrated results stay distinct from assumptions and from mixed or negative outcomes.
- **Post-deploy monitoring** — where to look, healthy signals, failure signals, rollback, window. When the change has no runtime impact, the collapsible holds the single line `No additional operational monitoring required` and a one-line reason.

---

## Register — written for a new teammate

Three parts: a little context, ASD-STE100 Simplified Technical English, and the project's own vocabulary. Applied to a PR body:

**Context first.** The lede gives the reader the situation before the change — what a user was doing, what went wrong or was missing — in the same breath as what is different now. A reader who arrives cold has what they need by the end of the first paragraph.

**ASD-STE100.** The standard's writing rules, not a loose reading of them:

- One sentence carries one idea. A descriptive sentence has at most 25 words; a step in a walk-through has at most 20.
- A paragraph has at most six sentences and one topic. (The scannability rules below tighten this to four.)
- Active voice, present tense. "The job sets `status`", not "`status` is set by the job" or "the job will set".
- Verbs, not nominalizations: "the reader refuses", not "refusal by the reader".
- No noun clusters longer than three words. Break "portfolio contract fixture corpus" into a phrase.
- One word, one meaning, used the same way every time. Do not vary a term for style.

**Ubiquitous language.** When the repo has a glossary (`GLOSSARY.md`, `CONTEXT.md`, or similar), use its terms exactly, and gloss a term inline on first use for the reader who has not read it. When the repo has none, use the product's own words — the labels on the screen, the names in the ticket — and keep them consistent.

**`noslop`.** Hold it in author mode while writing (`references/compose.md` says how to load it and what to do without it). Its seven tests (mechanism, portability, actor, one idea, density, decision first, reader) govern every sentence, and its pattern catalog names the tics to avoid. Identifiers, paths, protocol names, error text, and thresholds stay verbatim where they *are* the claim — do not dilute mechanism into vague plain English.

On top of these, PR bodies add:

- **Gloss or drop.** Define a domain term the first time it appears, inline, in plain words — or do not use it. Never bold a term as a glossary marker.
- **Ground before leaning.** A concept is introduced before any sentence depends on it. The reader either walked in knowing it or met it in an earlier paragraph. If the walk-through needs a term the Background paragraph explains, the Background paragraph moves above the walk-through, or the gloss moves into the step. A lede that uses a term the body defines three sections later is ungrounded.
- **No people, no meetings.** "A teammate asked for this in last week's review" becomes what was asked for and why. Names belong on the ticket.
- **Numbers over adjectives.** "138 rows, 112 of them paying $0" beats "many rows paid nothing".
- **Short full sentences.** If the reader would have to reread it, split it. A row of fragments is a pose.
- **No process narration.** How the work went — which reviewer said what, how many passes ran, what the agent tried first — is not content. What was decided, and why, is.
- **Sources are private.** Plan documents, brainstorm docs, session notes, and their internal labels (unit numbers, phase numbers, decision ids) are local-only and invisible to the team. Read them to recover intent and decisions; write self-contained content. Never link them, name their paths, cite them, or use their labels. Step E scans for this.
- **Never fabricate the why.** The lede's "why" comes from real sources: the user's stated intent, the ticket, the plan, the conversation. If none carry it, ask; in non-interactive flows, state what the change does and omit the motivational claim.

### Scannable — written for a reader who skims first

Many readers, including readers with ADHD, take in a document by skimming its structure before reading any sentence. The Job Accommodation Network's ADHD guidance names what helps: written instructions, checklists and itemized steps, clearly labeled components, outlines with a visual hierarchy, and less to hold in working memory at once. In a PR body that means:

- **Short paragraphs.** Four sentences at most, one idea each, a blank line between them. A block of prose longer than that becomes a list or two paragraphs.
- **Lists for parallel items.** A sentence or paragraph that walks through named things in turn — "Step A builds the map, Step C assembles the spine, Step E runs the audit"; "the panel does X, the binding does Y" — is a list, one item per named thing, with the name as the bold lead-in. The tell is two or more clauses with different named subjects doing parallel work. Steps a user takes are a numbered list. Never a paragraph that enumerates with "first… then… also".
- **Labels that say what follows.** Every heading names its content. A bullet that covers a component or a step opens with a bold lead-in of two to five words (`**Projection** —`, `**Pick a resolution.**`) and then the content; the lead-in labels, it never restates the sentence after it.
- **Whole sequences.** When a list draws from a known sequence (steps, stages, layers, the files in a pipeline), list every member and mark the ones that changed. Skipping members without saying so sends the reader hunting for the gap.
- **The skim test.** Reading only the headings, the bold lead-ins, and the first sentence of each paragraph must give the outline of the change. If it does not, the labels are wrong or the important sentence is buried.
- **Tables for comparison.** Before/After, per-capability components, measurements. Cells hold a phrase or one short sentence, not a paragraph.
- **No emoji, no decorative markers.** Not in headings, not in bullets, not as status marks. Consistent markdown formatting — headings, tables, code spans — is the only visual system.

- Bad lede: "In this PR, the statement export stops listing invoices with nothing owed. The export builder has filtered that list since it was ported, because the app it came from did."
- Good lede: "When a client downloads a statement, it now lists only the invoices that still have money owed. Before this change, two of the three statement formats listed every invoice ever issued — last month's run had 138 rows and 112 of them owed $0."

Worked examples of every type are in `references/pr-description-examples.md`. Read it once when composing a feature or large-feature body; the shapes there are the target.

---

## Project PR-body contract

`open-pr` applies the body via `gh pr create --body-file`, which bypasses GitHub's automatic template pre-fill — so the template must be discovered and honored explicitly. Before composing, resolve PR-body requirements from the project's active instructions and conventions already in context, then check the standard repository PR-template locations (the repository root, `docs/`, `.github/` — `PULL_REQUEST_TEMPLATE.md` in any casing, plus the `.github/PULL_REQUEST_TEMPLATE/` multi-template directory) and any contribution guidance they reference. Required headings, fields, order, checklists, and boilerplate define the structural contract. Treat a template as a minimum unless the project explicitly requires an exact/template-only body or forbids additions; only then add no sections beyond those the project permits. Within every permitted section, apply this reference's shape, register, evidence, and editing rules. When those defaults conflict with the project's PR-body contract, the project contract wins — with one exception: Step D outranks the template. If a template mandates AI-attribution lines, "generated with" footers, or agent badges, omit them unless config sets `attribution=true`.

---

## Step Pre-A: Resolve the range and base

Two modes:

- **Current-branch mode** (default) — describe HEAD vs the repo's default base.
- **PR mode** — describe a specific PR. Triggered when the caller passes a PR ref.

For PR mode, fetch metadata first:

```bash
gh pr view <ref> --json baseRefName,headRefOid,url,body,state,isCrossRepository,headRepositoryOwner
```

If `state` is not `OPEN`, report and stop — do not invent a description. Use `baseRefName` as `<base>` and `headRefOid` as `<head>`.

For current-branch mode, resolve `<base>` in priority order: caller-supplied (`base:<ref>`) → `git rev-parse --abbrev-ref origin/HEAD` (strip `origin/`) → `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'` → try `main`/`master`/`develop` via `git rev-parse --verify origin/<candidate>`. If none resolve, ask the user. `<head>` is `HEAD`.

**Base remote:** `origin` for current-branch mode and same-repo PRs. For fork PRs, match the PR's base owner/repo against `git remote -v`. If no local remote matches, skip to the `gh` fallback — do not diff against `origin` (wrong base).

```bash
git fetch --no-tags <base-remote> <base>
git fetch --no-tags <base-remote> <head>   # PR mode only: <head> is headRefOid and may not be local
git log  --oneline "<base-remote>/<base>..<head>"
git log  --format=fuller "<base-remote>/<base>..<head>"   # full commit messages for related-reference discovery
git diff           "<base-remote>/<base>...<head>"
```

If the commit list is empty, report "No commits to describe" and stop.

**Fallback** — use `gh pr diff <ref>` and `gh pr view <ref> --json commits` when local git can't reach the refs (fork PR with no matching remote, shallow clone, offline, merge-base on unrelated histories). For GHES configurations that reject SHA fetch but allow `refs/pull/`:

```bash
git fetch --no-tags <base-remote> "refs/pull/<number>/head"
PR_HEAD_SHA=$(awk '/refs\/pull\/[0-9]+\/head/ {print $1; exit}' "$(git rev-parse --git-dir)/FETCH_HEAD")
```

Note in the user-facing summary when the API fallback was used.

---

## Step A: Build the scope map and pick the type

Before composing anything, build a compact internal **scope map** from the **complete oneline commit list and final three-dot diff**. Use the oneline subjects for full-range coverage; use the final diff to merge overlaps, discard fix-up-only work, and correct stale or misleading subjects; consult the fuller messages only when a subject remains opaque or conflicts with the diff. Group the remaining work into material outcome clusters (one is fine), name one umbrella outcome that covers them, and identify each cluster's **material claims** — what became possible, what was fixed, what risk changed, or what design decision the reviewer must assess. Derive this map from the full range, never from the latest commit, tracker title, branch name, or original request. **Classify each changed file by runtime purpose, not extension**: markdown or YAML may be inert docs, or runtime agent instructions, configuration, product content, or deployment behavior — a "docs-only" diff that is really runtime instruction carries real claims.

**State the umbrella as what is now different for someone using the software, never as the mechanism that produced it.** The title and the lede both inherit the map's altitude, so a mechanism-shaped umbrella cannot be corrected later — every later check compares against it and agrees with it.

**Pick the type** from the map, not from line count:

- One user-facing capability that did not exist → **New feature**.
- Two or more user-facing capabilities, or a new subsystem with its own components → **Large feature**.
- Existing behavior is different now (including copy, layout, a rule, a default, performance) → **Change to existing behavior**.
- Something was broken and now is not → **Bug fix**. When a fix also adds a capability (a diagnostic tool, say), the fix is the type and the tool is a paragraph under *Summary*.
- Config, membership, dependency bump, one-line copy, a mechanical rename → **Tiny**.

Two material outcomes of different types share the lede, and the body uses the shape of the larger one. Subtract fix-up commits (review fixes, lint, rebase resolutions) — they are invisible to the reader.

**Program altitude (multi-PR work).** After the PR-local scope map, check whether this PR sits inside a larger program — a multi-PR project, a series of dependent PRs, a multi-part plan. Judge from signals already in hand: the user's prompt and this conversation, a known plan path, an existing PR body, commit messages, sibling or series language in context. Do **not** invent a series, and do **not** run a repo-wide open-PR scan just for this step. When program context is present, the lede or a sentence right after it carries: the **program outcome** in one sentence, **this PR's contribution**, and its known **neighbors** — prior work landed and residual work still to come, each only when actually known. An early PR needs the lead-out; a middle one needs both; a late one needs the lead-in and says the arc completes when that is true. Omit either neighbor when unknown rather than guessing. When there is no program, write nothing about a series.

**Evidence** is broader than screenshots and passing tests — benchmarks, API captures, migration exercises, logs, compatibility matrices, evals, manual probes, and rollout results all count — but a result leads the *Verification* collapsible only when it changes confidence in a material claim; its detail follows it inside the same collapsible, never inline in the visible body. A bug fix's before-and-after proof is the exception: it is the visible `## Evidence` section.

---

## Step B: Compose the title

House default: **no-verb outcome Title Case** — 3-5 words naming the outcome, not the action. Derive it from the scope map's umbrella outcome, never one cluster or implementation mechanism.

- Good: `Deal Payment Schedules`, `Session Token Redis Cache`, `Faster CSV Imports`
- Bad: `Add payment schedules to deals` (verb-led), `PaymentScheduleBuilder Service` (mechanism, not outcome)

**Direct, not abstract.** Name the things a reader sees change, in the product's own words. An umbrella noun for them is too vague. `Same Buttons, Fields And Colours On Every Screen` beats `One Theme For Every Screen`, because "theme" is a mechanism word and the buttons, fields and colours are what changed. Never lead with a number that holds for one step only. `200 MB Uploads In About 10 Seconds` misled when only the send took 10 seconds and the whole upload still took minutes.

**Draft three, keep the most concrete.** Write three candidate titles from the umbrella outcome, then pick the one a reviewer scanning the PR list would understand without opening it. Under `options`, each option carries a different one of the three.

**Title style.** `title_style=outcome` always uses the house default above. `title_style=repo` (the default) uses it unless the repo's existing PR titles or project instructions clearly follow a different convention, and then matches that convention. `title_style=conventional` always uses conventional-commit `type(scope): description`: type by intent (`fix` over `feat` when ambiguous — reserve `feat` for capabilities the user could not previously accomplish), narrowest useful scope, imperative lowercase description under 72 chars, no trailing period.

**Never use `!` or `BREAKING CHANGE:` without explicit user confirmation** — they trigger automated major-version bumps.

---

## Step B1: Resolve related work references

Before writing the body, make an explicit related-reference pass. Gather candidate work-item references from the user prompt, caller handoff, branch name, full commit messages, existing PR body, PR template, plan or debugging notes, and visible URLs or IDs already in context. The Linear ticket line from `references/compose.md` is already decided; this pass covers everything else. Preserve existing related references when rewriting a PR unless the user asks to remove them.

Classify each candidate as:

- **closing reference** — the PR fully resolves the item and the tracker's closing syntax is known.
- **non-closing reference** — the PR is related, partial, investigative, follow-up, validation-only, or the tracker semantics are unknown.
- **uncertain** — the change clearly came from a tracked bug, incident, performance investigation, alert, or log trace, but the exact ID/link or close-vs-link intent is missing. Ask the user for the reference or intent; in non-interactive flows, use a non-closing reference or omit rather than pretending to close it.

Do not invent a closing keyword. Magic words are workflow actions, not decoration. If the candidate is ambiguous, put a neutral related reference in the related-reference sentence/block or omit it; do not scatter the ID through the summary.

Do not put a non-closing reference next to close/fix/resolve/address/report wording in prose. For partial or related work, write the behavioral scope in one sentence and put the tracker ID separately. Use the table's non-closing reference labels exactly; do not substitute synonyms like `Refs`, `References`, or `Toward` unless the project's documented tracker convention requires one of those labels. For a non-closing reference, the tracker ID appears only in that related-reference sentence or block, never in the lede or body prose — with one exception: follow-up tickets named in *Worth knowing* or *All decisions* as the home of deferred work.

- Bad: "closing one corruption path from #123"
- Bad: "partial fix for #123"
- Good: "This covers the duplicate-row retry path; concurrent cancellation remains follow-up work."
- Good: "Related: #123"

Common syntax examples:

| Tracker | Closing reference | Non-closing reference | Notes |
|---|---|---|---|
| GitHub Issues | `Fixes #123`; cross-repo: `Fixes owner/repo#123` | `Related: #123`; cross-repo: `Related: owner/repo#123` | Closing keywords are `close(s/d)`, `fix(es/ed)`, and `resolve(s/d)`. Use closing syntax only when the PR targets the default branch and truly resolves the issue; otherwise use a non-closing reference. Repeat the keyword for multiple closing issues. |
| Linear | `Resolves PROJ-123` (the ticket line) | `Part of PROJ-123` (the ticket line) or `Related to PROJ-123` | Linear supports closing and non-closing magic words. Put magic words in the PR description, not a PR comment. Multiple issues can follow one magic word when they share the same intent, e.g. `Fixes PROJ-123, DES-5 and PROJ-256`. |
| Other trackers | Use the project's documented closing keyword only when known. | Prefer a full URL or tracker ID under `Related`. | Some trackers parse commit messages, PR descriptions, or both. Follow project docs or tracker integration docs when present; otherwise never guess a closing action. |

The ticket line is part 2 of the spine. Non-closing references that need their own block go after *Worth knowing* and before the collapsibles.

---

## Step C: Assemble the body

When a project PR-body contract supplies headings or order, preserve that structure and place the applicable elements below within the sections it permits. Otherwise assemble the spine: lede → ticket line → visual → type section → `## How it works` (or `## How it fits together`) → `## Worth knowing` → non-closing related references when they need their own block → the four collapsibles (All decisions, In this PR, Verification, Post-deploy monitoring). A bug fix puts its six sections (*Bug fix sections* above) between the ticket line and the collapsibles. Nothing after the last collapsible — see Step D.

The lede is always a bare paragraph at the top — no heading above it, no label. A bug fix's `## What was wrong` and `## Summary` come after it and never replace it.

**Caller-supplied material.** An orchestrating caller hands over context: a plan summary, decisions and pivots, testing notes, review residuals, a monitoring section. This is source material, not a list of things to include. Route it: the *why* into the lede; decisions the reviewer would question into *How it works* as bold questions; every other decision, pivot, applied review finding, and residual into the *All decisions* collapsible as self-contained entries; the diff summary into *In this PR*; test results into *Verification* (the one-line results first, the detail below), except a bug fix's before-and-after proof, which goes into *Evidence*; the monitoring section into its collapsible. A decision a plan records becomes an *All decisions* entry stating what was decided and why, with no plan citation and no label. Point-in-time content: never an outstanding-items ledger, never updated after the PR opens — except the `Unapplied review findings` checkbox list, which is a ledger by design.

**Evidence and visuals:** a diff that touches frontend surfaces — views/templates (erb, haml, slim, jsx, tsx, vue, svelte), components, stylesheets, or UI JavaScript (e.g. Stimulus controllers) — should show the change; `references/compose.md` decides how visuals are obtained under the `visuals` setting. Placement is directly after the ticket line, or, inside a feature walk-through, at the step each one shows. Never under a `## Demo` or `## Screenshots` heading:

- **Before + after states** → a two-column markdown table, side by side: `| Before | After |` with one `![before](path)` per cell. In a *change to existing behavior* body this table opens the `## Before / After` section.
- **New surface with no meaningful before** → a single embedded image, at the walk-through step it illustrates.
- **Interactions** → a video alone on its own line, so it renders as an inline player; in a table cell or mid-sentence it degrades to a link. A GIF may ride in the Before|After table.

**Attaching local files.** Write each local image or video into the body by its absolute path (`![Before](/abs/before.png)`; a video as `![](/abs/demo.mp4)` alone on its line), then pass `--attach /abs/path` once per file on the same `gh pr create` / `gh pr edit` that posts the body. `gh` uploads each file to GitHub user-attachments and rewrites the path in place to the asset URL; a file attached but never referenced is appended at the end, so always reference it where it belongs. Wrap a path that contains spaces in angle brackets: `![after](</abs/Screen Shot.png>)`. Needs `gh` 2.99.0 or later (`gh pr create --help | grep -q -- --attach`; if missing, tell the user to upgrade `gh` rather than hand-rolling an upload), write access, and github.com or GitHub Enterprise Cloud. Limits: 10 MB per image, 100 MB per video (10 MB on free plans); compress video with `ffmpeg -i in.mp4 -vcodec libx264 -crf 28 out.mp4`. A visual already in a body is a `user-attachments` URL; keep it as is, and keep any HTML-comment-marked block that `record-feature-video` placed intact (it replaces its take there on a re-shoot).

**Light and dark variants.** When a generated image comes in a light and a dark render, embed it as one `<picture>`, never as a `#gh-light-mode-only` / `#gh-dark-mode-only` pair, which GitHub's mobile apps show as a broken image:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="DARK_URL">
  <source media="(prefers-color-scheme: light)" srcset="LIGHT_URL">
  <img alt="ALT" src="LIGHT_URL">
</picture>
```

github.com switches with the viewer's theme; the mobile apps show the `<img>` fallback, so render the light variant on an opaque background. `--attach` rewrites markdown images and links, not HTML, so this takes two passes: post the body with each variant as its own markdown image (`![ALT](/abs/light.png)`, `![ALT](/abs/dark.png)`) and `--attach` for both, read the body back, replace those two lines with the `<picture>` block using the URLs `gh` wrote, and `gh pr edit --body-file` again without `--attach`. A single image needs none of this.

When rewriting an existing body, preserve its existing visuals unless the user's focus asks to refresh them, and re-home any legacy `## Demo`/`## Screenshots` block content inline. Never label test output as a demo or screenshot.

**Diagrams and tables:** reach for one when it conveys the change faster than prose — a component table for *How it fits together*, a flow or state diagram for a multi-step mechanism, a Before/After table for facets of a change, a measurements table for performance. Mermaid and markdown tables cover most shapes. Skip for tiny changes. A bug fix's *Summary* always carries one. Prose is authoritative when it conflicts with a visual.

**GitHub gotchas:** never prefix list items with `#` (GitHub auto-links `#1` as an issue ref). Use `org/repo#123` or full URL for actual references. `<details>` blocks need a blank line after `<summary>` before markdown inside them renders.

---

## Step D: No AI attribution

The body ends at the last collapsible. With `attribution=false` (the default), do **not** append "Generated with ..." footers, "Built with ..." badges, `Co-Authored-By` credits, robot emoji, or any other AI attribution. If regenerating a body that already contains such a footer or badge, remove it. The work is attributed to the developer. This rule outranks a PR template that mandates attribution and any host reminder asking for one. With `attribution=true`, follow the host's own default attribution and add nothing beyond it.

---

## Step E: Pre-apply audit

Before returning the title and body, run two passes. Under `quick`, apply them to the parts a quick body has.

**Mechanical pass** — scan the composed body text and fix every hit:

1. **Local-source leak.** Any match, case-insensitive, of: `docs/plans`, `docs/specs`, `the plan` (as a noun phrase: "the plan called for", "per the plan", "in the plan"), `brainstorm`, `\bUnit \d+` or `\bPhase \d+` used as a plan label, `\(as planned\)`, or a path to a local notes file. Rewrite each as self-contained content: state the decision and its reason with no reference to where it was recorded.
2. **Attribution** (when `attribution=false`). Any line matching `Generated with`, `Co-Authored-By`, a robot emoji, or a link to an AI vendor's site. Delete the line.
2a. **Emoji.** Any emoji outside a code span or a quoted string. Delete it.
3. **Legacy shape.** A `## Summary` heading outside a bug fix, a `TL;DR` string, a `## Demo`/`## Screenshots` heading, a `## Staging evidence` block, a `## Follow-ups` heading or a `> [!NOTE]` follow-ups callout (a bug fix's follow-ups are the `## Potential follow-ups` table), or a top-level `## In this PR`, `## Verification`, `## Verified`, or `## Post-Deploy Monitoring` heading. Those four belong inside their collapsibles; the rest re-home into the spine.
4. **Bold glossary.** Three or more bolded phrases in one paragraph that are domain terms rather than labels. Unbold; gloss the first use if the reader needs it.
5. **Walls of text.** Any paragraph over four sentences, or any sentence over about 25 words, outside a table or code block. Split the paragraph or turn it into a list; split the sentence.
6. **Enumerating prose.** A sentence or run of sentences whose clauses each open with a different named subject doing parallel work ("Step A …, Step C …, Step E …"; "`parser.py` …, `loader.py` …, `writer.py` …"). Turn it into a list with the names as bold lead-ins.

**Judgment pass** — check against the scope map and revise if any answer is wrong:

- Can a reader stop after the lede and know what changed for users? After the type section and know what they would see? After *How it works* and review the code? If any layer is incomplete on its own, fill it; if any layer restates the one above, cut it.
- Is the type right for the map, and does the type section have that type's shape (walk-through / per-capability `###` / Before-After + what did not change / What was wrong bullets + a Summary that is a visual with at most one sentence + Evidence + Merge Danger / nothing)?
- Does the lede name a mechanism where an outcome belongs — "switches the resolver to a queue" rather than "stops duplicate notifications"? Audit the scope map, not just the sentence: a mechanism-shaped map produces a mechanism-shaped lede that reads fine. Restate the umbrella as what changes for someone using the software, then rewrite title and lede from it.
- Is a coequal outcome demoted into an aside — "also surfaced", "and while there", a trailing clause — when the map lists it as material? Two material outcomes share the lede; "also" is for supporting work only.
- When this PR sits in a known program, does the lede carry program altitude — the program outcome, this PR's contribution, and each known neighbor? Is any series claimed that was not in evidence?
- Does the body pass the skim test — headings, bold lead-ins, and first sentences alone give the outline? Are parallel items in lists, with lead-ins that label rather than restate?
- Does every sentence hold STE100 — one idea, at most 25 words, active voice, present tense — and does every domain term match the repo's glossary (or the product's own labels) with a gloss on first use?
- Does every sentence pass `noslop`'s tests — mechanism over feeling, actor named, one idea, decision first, and a reader without the code open can act on it? Are identifiers, paths, error text, and thresholds kept verbatim where they are the claim?
- Does the body narrate process — reviewer counts, passes, what was tried first — anywhere outside an *All decisions* entry that states a pivot as a decision? Cut it.
- Does *Verification* open with results rather than "tests passed", with its detail below rather than inline in the visible body?
- Does *All decisions* carry every decision the reviewer might question that *How it works* does not, and does *Worth knowing* carry every follow-up with its ticket? In a bug fix, does *Potential follow-ups* grade each row with only *Do soon*, *Plan it*, or *Nice to have*, most urgent first, at most five rows?
- Is every term grounded before a sentence leans on it — glossed in the lede or an earlier paragraph, never three sections later?
- Is the body sized to the change rather than the session? A tiny change with a long *All decisions* collapsible is a sign the session leaked; keep only decisions that concern what shipped.
- Can any sentence be cut without lowering a reader's confidence or understanding at its layer? Cut it — except headings, fields, checklists, or boilerplate the project's PR-body contract requires. Attribution is never protected content.
