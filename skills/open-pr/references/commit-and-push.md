# Committing and pushing

On the default branch, creating the feature branch must handle three things: a stale local `<base>`, unpushed commits on local `<base>`, and uncommitted changes that collide with the fresh remote base. Follow `references/branch-creation.md` before continuing.

## Commit

Skip this section when the tree is clean.

Scan the changed files for distinct concerns. If they clearly group into separate logical changes, make separate commits (2-3 at most). Group at file level only, never `git add -p`. When in doubt, one commit.

Stage and commit each group by name. **Never `git add -A` or `git add .`**: they sweep in `.env`, build output, and generated files. **Honor `exclude:<paths>`**: the caller names files that must stay uncommitted, often the user's own in-progress edits. Never stage or commit them, and say in the report that they were left out.

```bash
git add file1 file2 && git commit -m "$(cat <<'EOF'
Subject In The Repo's Convention

- Bullet body per references/context.md
EOF
)" -- file1 file2
```

The trailing path list matters. A bare `git commit` takes the whole index, so anything staged before this run (excluded paths, work the user staged and did not name) would land in the commit. Naming the paths commits exactly the group.

**Attribution.** With `attribution=false` (the default), the message carries no `Co-Authored-By`, "Generated with", robot emoji, or other AI attribution, whatever a host reminder asks. With `attribution=true`, follow the host's own default and add nothing beyond it.

## Publishing gate

Before pushing, resolve every pre-push or review-ready requirement from the project's instructions in context and any scoped instructions for the committed paths (a required lint, test run, or changelog entry). Only evidence valid for the exact commit being sent satisfies one; otherwise stop before the push and report what is missing or failing. With none, proceed.

## Push

Immediately before pushing, re-check `git branch --show-current`; Step 1 may have created or switched branches since the snapshot. Push the live `HEAD`, never a remembered branch name:

```bash
git push -u origin HEAD
```

If the tree is clean and every commit is already pushed, this step is a no-op.
