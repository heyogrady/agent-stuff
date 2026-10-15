# Conventions

These rules keep the skills in this repo portable and safe to publish. The repo is public.

## Layout

```
.claude-plugin/plugin.json        Claude Code plugin manifest (name: agent-stuff)
.claude-plugin/marketplace.json   lets `/plugin marketplace add heyogrady/agent-stuff` work
.codex-plugin/plugin.json         Codex manifest (same fields + skills: "./skills/")
skills/<name>/SKILL.md            one folder per skill; references/ and scripts/ beside it
evals/<name>/                     checks for a skill, outside skills/ so an agent under test cannot read them
```

Skills: `open-pr`, `record-feature-video`, `babysit-pr`, `resolve-pr-feedback`, `noslop`.

## Writing skills

- `name:` equals the folder name. Lowercase `a-z0-9-`.
- `description:` is mechanism-first and about 200 characters. Hard cap 1024.
- `SKILL.md` stays under 8000 bytes (Codex injects at most that much). Move detail into `references/`.
- `argument-hint:` lists what a person would type, in one style (`word` or `key:value`, never `--flag` mixed with `key:value`).
- A skill that must only run when typed carries `disable-model-invocation: true` **and** `agents/openai.yaml` with `policy.allow_implicit_invocation: false` (Codex ignores the frontmatter key).
- Refer to a sibling skill as inline code, e.g. `noslop`. When a step dispatches a sibling, resolve the name against the host's available-skills list (it may appear as `agent-stuff:noslop`) and invoke that exact entry.
- Point at a sibling's file in prose: `` `noslop`'s `references/patterns.md` ``. Never a hardcoded absolute path.
- Resolve a skill's own files from its own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"`, then `"$SKILL_DIR/scripts/…"`.
- Use the host's blocking question tool when one is listed (match by capability, not by a host-specific tool name); otherwise ask in chat.
- Never add AI attribution (`Co-Authored-By`, "Generated with", robot emoji) to commits, PR bodies, or comments unless the user's config turns it on (`pr.attribution: true`).
- Do not add comments that restate the code. Keep a comment only when it records a reason or constraint the code cannot show.

## Config

One file per repo, read from the repo root (`git rev-parse --show-toplevel`):

1. `agent-stuff.local.md` (personal, should be git-ignored), then
2. `agent-stuff.md` (tracked, team defaults).

Both are Markdown with YAML frontmatter. First active (non-commented) value wins per key; a map key present in the local file replaces the whole map. When the worktree has neither file, fall back to the main checkout's root (`dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`) and say so in one line. Inside a nono sandbox the main checkout may be unreadable; then the worktree needs its own copy.

Blocks: `pr:` (open-pr, babysit-pr), `feature_video:` (record-feature-video). Before using any credential from a config file (`password`, `cookies_file`, tokens), run `git check-ignore -q <file>`; if the file is not ignored, warn the user that it could be committed.

## What must never appear in this repo

Personal paths (`/Users/...`, `~/workspace`), personal or employer names, private repo names, internal URLs or hostnames, emails, tokens or passwords (even redacted examples taken from real repos), and references to skills that are not in this repo. Examples use neutral placeholders (`acme/web`, `app.example.test`, `PROJ-123`).
