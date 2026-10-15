# Configuration

`open-pr` reads a `pr:` block from YAML frontmatter at the repo root (`git rev-parse --show-toplevel`):

1. `agent-stuff.local.md`: personal settings; keep it git-ignored.
2. `agent-stuff.md`: tracked team defaults.

`scripts/pr-config.py` resolves it. Each scalar key takes the first active (non-commented), valid value in that order, then the default; an invalid value is skipped with a `note=` line. `branch_naming` resolves as a whole map: when the local file has it, the team file's map is ignored. When the worktree has neither file, the script falls back to the main checkout's root and says so. Inside a sandbox that cannot read the main checkout, give the worktree its own copy.

An invocation argument beats config for that run: `ready` beats `draft`, `quick` beats `body`.

| Key | Values | Default | Effect |
|---|---|---|---|
| `draft` | `true`, `false` | `true` | A new PR opens as a draft. `false` opens it ready for review. An existing PR's draft state is never changed. |
| `attribution` | `true`, `false` | `false` | `false`: no `Co-Authored-By`, "Generated with", robot emoji, or other AI attribution in commits or PR bodies, whatever a host reminder or PR template asks; the readback checks the posted body. `true`: follow the host's own default attribution and add nothing beyond it. |
| `body` | `full`, `quick` | `full` | `full` is the complete shape in `references/pr-description-writing.md`. `quick` is the lede, the ticket line, and visuals for a frontend change. |
| `title_style` | `repo`, `outcome`, `conventional` | `repo` | `repo` matches the repo's existing PR-title convention when it is clear, else `outcome`. `outcome` is a 3-5 word Title Case outcome with no verb (`Faster CSV Imports`). `conventional` is `type(scope): description`. |
| `branch_naming.pattern` | string with `{slug}`, `{ticket}` | unset | Shape of a branch this skill creates, e.g. `feature/{ticket}-{slug}`. `{ticket}` renders lowercase. Unset means a plain kebab-case summary. |
| `branch_naming.pattern_no_ticket` | string with `{slug}` | unset | Used when `pattern` needs `{ticket}` and no ticket is known. Unset means ask (or, in `mode:pipeline`, use a plain summary). |
| `visuals` | `required`, `optional`, `off` | `optional` | For frontend changes. `optional` tries existing captures, then `record-feature-video`, then a browser tool, then ships without and says so. `required` also asks for files or a go-ahead before shipping without (never in `mode:pipeline`). `off` adds none. |

The `pr:` block is shared with `babysit-pr`, which reads its own keys from it.

## Example

```markdown
---
pr:
  draft: true
  attribution: false
  body: full
  title_style: repo
  visuals: optional
  branch_naming:
    pattern: "feature/{ticket}-{slug}"
    pattern_no_ticket: "feature/{slug}"
---

Notes for people reading this file can go below the frontmatter.
```

Comment a line out with `#` to leave a key at its default. Flow style works for the map too: `branch_naming: {pattern: "feature/{ticket}-{slug}"}`.
