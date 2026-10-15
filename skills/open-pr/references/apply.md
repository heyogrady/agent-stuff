# Step 4: apply and report

Read when entering Step 4. It covers every mode's apply path, the `gh` mechanics, the readback, and the report.

## By mode

**Describe-only.** Print the title and body (all three options under `options`). Apply only if the user then asks; that apply follows "Refresh" below.

**Options.** Before any create or edit, print the three options as plain text and wait for the reply:

```
Option 1:
  Title: <title>
  Description:
  <full body>

Option 2: ...
Option 3: ...

Which one? (1, 2, or 3)
```

Do not use a picker or blocking question tool here: the user often edits an option in the reply. Apply the chosen one, with their edits, exactly. In `mode:pipeline`, `options` is ignored.

**New PR** (full workflow, no PR matched in Step 1). Immediately before creating, **always** re-run `gh pr list --head <branch> --state open --json number,url,isDraft,headRefName,headRepositoryOwner` (branch name only; target the base repo on a fork). This catches a PR that appeared since Step 1, or one Step 1 missed because its check came back unknown.

- A PR whose `headRepositoryOwner` and `headRefName` match the current head: switch to "Existing PR".
- Exit 0 with no match: create it per "Applying via gh".
- Non-zero exit: resolve `gh auth status` or connectivity first. Never assume no PR exists.

**Existing PR** (full workflow, matched in Step 1). Step 2 already pushed the new commits onto it. Report the URL, then ask whether to rewrite the description. **No**: done. **Yes**: compose (Step 3) if not done, then follow "Refresh". In `mode:pipeline` the answer is no.

**Refresh** (a PR ref on the invocation, a request to rewrite a description, or a confirmed rewrite above). Compare the proposed title and body with the current ones. When identical, keep them and do not call `gh pr edit`. Otherwise preview and ask: "New title: `<title>` (`<N>` chars). Lede: `<first two sentences>`. Body: `<L>` lines. Apply?" If declined, the user may give focus text for a regenerate; do not apply. If confirmed, apply with `gh pr edit`. In `mode:pipeline`, skip the ask and apply (the identical-body rule still holds).

## Applying via gh

Write the body to a temp file and pass it with `--body-file <path>`. Never use `--body-file -`, stdin pipes, or `--body "$(cat ...)"`: wrappers and stdin handling can silently produce an empty body while `gh` still exits 0 and prints a URL.

```bash
BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/open-pr-body.XXXXXX") && cat >> "$BODY_FILE" <<'__PR_BODY_END__'
<the composed body, verbatim>
__PR_BODY_END__
```

The quoted sentinel keeps `$VAR`, backticks, and any literal `EOF` inside the body from being expanded. Substitute `<TITLE>` verbatim; if it contains `"`, `` ` ``, `$`, or `\`, escape them or use single quotes.

```bash
gh pr create --draft --title "<TITLE>" --body-file "$BODY_FILE"   # new PR
gh pr edit <url> --title "<TITLE>" --body-file "$BODY_FILE"        # existing PR
```

**Draft or ready.** A new PR opens as a draft. Drop `--draft` when the invocation carries `ready` or config says `draft=false`. Never change an existing PR's draft state; marking a draft ready is the user's call.

**Local visuals.** When the body references local files, add `--attach <abs-path>` once per file to that same command (writing reference, **Attaching local files**). Uploads cannot be undone, so attach only on the final apply, never on a preview. For a light/dark image pair, run the writing reference's **Light and dark variants** second pass before the readback.

## Readback

Run `gh pr view <url> --json body --jq .body` and confirm:

- With `attribution=false`, no attribution line survived (`Generated with`, `Co-Authored-By`, a robot emoji, a link to an AI vendor). A host hook or template may have added one after the apply.
- No local-source leak that the Step E mechanical pass would flag.
- No local file path survived; every attached path now reads as a `user-attachments` URL.

On any violation, fix the body file and `gh pr edit --body-file` again before reporting.

## Feature video

When Step 3 deferred visuals to `record-feature-video`, invoke it now with the PR number (namespaced as the host's skill list shows it). Pass `mode:pipeline` when this run has it. It posts the clip into the body itself. If it reports `video skipped`, or cannot be loaded, carry its reason into the report. It never blocks the report.

## Report

Print, one line each:

- The PR URL and whether it is a draft or ready for review.
- The ticket line used, or `no ticket`.
- Paths left out by `exclude:`.
- The visuals result when the change is frontend: attached, filmed, or the "shipped without visuals" flag.
- Any fallback the run took (noslop unavailable, base freshness not verified, `gh` API diff fallback).

Then, when `babysit-pr` is in the host's skill list and the PR is new, one line saying it can watch CI and review comments on this PR. Never start it from here.
