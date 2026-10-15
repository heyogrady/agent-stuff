# Branch creation from the default branch

Local `<base>` may hold stale commits (another worktree advanced it) or commits the user made intending to branch later. Git cannot tell these apart, so ask when unpushed commits are present.

## Decision flow

### 1. Fetch the fresh remote base

```bash
git fetch --no-tags origin <base>
```

If the fetch fails (network, auth, no remote), use the fallback at the bottom.

### 2. Check for unpushed commits on `<base>`

```bash
git log origin/<base>..HEAD --oneline
```

- **Empty:** set `BASE_REF=origin/<base>` and go to step 3.
- **Non-empty:** show the list and ask:

  > "Local `<base>` has N unpushed commits not on `origin/<base>`. Carry them onto the new feature branch, or leave them on local `<base>`?"

  - **Carry forward**: `BASE_REF=HEAD`. The new branch keeps them.
  - **Leave on `<base>`**: `BASE_REF=origin/<base>`. The new branch starts clean.

  Never default silently; carrying unrelated commits into a PR is worse than asking. In `mode:pipeline`, stop and report the choice that is needed.

### 3. Create the feature branch

```bash
git checkout --no-overwrite-ignore -b <branch-name> "$BASE_REF"
```

`--no-overwrite-ignore` keeps a local `.env`, a build cache, or any other ignored file from being clobbered by a same-named file on the base. Without it, git treats an ignored path as free to overwrite.

If checkout fails because uncommitted or ignored files would be overwritten, stop and ask the user to handle the colliding paths (in `mode:pipeline`, report the blocker). Never stash or delete them.

## Fetch failure fallback

Branch from the current local `HEAD`:

```bash
git checkout --no-overwrite-ignore -b <branch-name>
```

Say in the report that base freshness was not verified. Skip the unpushed-commits check; without a fresh `origin/<base>` its answer is unreliable.
