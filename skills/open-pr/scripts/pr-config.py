#!/usr/bin/env python3
"""Print the resolved `pr:` config for open-pr as key=value lines.

Layers: agent-stuff.local.md, then agent-stuff.md, at the worktree root; when
the worktree has neither, the main checkout's root. Scalars resolve per key
(first valid active value wins); `branch_naming` resolves as a whole map.
No YAML library is used so the result does not depend on what is installed.
"""
import os
import subprocess
import sys

DEFAULTS = {
    "draft": "true",
    "attribution": "false",
    "body": "full",
    "title_style": "repo",
    "visuals": "optional",
}
ALLOWED = {
    "draft": {"true", "false"},
    "attribution": {"true", "false"},
    "body": {"full", "quick"},
    "title_style": {"outcome", "conventional", "repo"},
    "visuals": {"required", "optional", "off"},
}
BOOLS = {"true": "true", "yes": "true", "on": "true",
         "false": "false", "no": "false", "off": "false"}
FILES = ("agent-stuff.local.md", "agent-stuff.md")


def git(*args):
    out = subprocess.run(("git",) + args, capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def strip_comment(value):
    quote = None
    for i, ch in enumerate(value):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or value[i - 1] in " \t"):
            return value[:i].rstrip()
    return value.strip()


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def split_flow(body):
    parts, quote, cur = [], None, ""
    for ch in body:
        if quote:
            quote = None if ch == quote else quote
        elif ch in "\"'":
            quote = ch
        elif ch == ",":
            parts.append(cur)
            cur = ""
            continue
        cur += ch
    parts.append(cur)
    out = {}
    for part in parts:
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip()] = unquote(v)
    return out


def frontmatter(path):
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None
    if not lines or lines[0].strip() != "---":
        return []
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            return lines[1:i]
    return []


def pr_block(lines):
    """Return {key: scalar or dict} for the active top-level `pr:` map."""
    block, inside, child_indent, nested = {}, False, None, None
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        text = strip_comment(raw.strip())
        if indent == 0:
            inside = text.split(":", 1)[0].strip() == "pr" and text.endswith(":")
            child_indent, nested = None, None
            continue
        if not inside or ":" not in text:
            continue
        if child_indent is None:
            child_indent = indent
        key, value = (s.strip() for s in text.split(":", 1))
        if indent == child_indent:
            nested = None
            if value.startswith("{") and value.endswith("}"):
                block[key] = split_flow(value[1:-1])
            elif value == "":
                block[key] = {}
                nested = key
            else:
                block[key] = unquote(value)
        elif nested and indent > child_indent:
            block[nested][key] = unquote(value)
    return block


def valid(key, value):
    if not isinstance(value, str) or value == "":
        return None
    value = value.lower()
    if key in ("draft", "attribution"):
        value = BOOLS.get(value, value)
    return value if value in ALLOWED[key] else None


def main():
    top = git("rev-parse", "--show-toplevel")
    if not top:
        print("error=not a git repository")
        return 1
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    main_root = os.path.dirname(common) if common else None
    layers, notes = [], []
    for name in FILES:
        fm = frontmatter(os.path.join(top, name))
        if fm is not None:
            layers.append((os.path.join(top, name), pr_block(fm)))
    if not layers and main_root and os.path.realpath(main_root) != os.path.realpath(top):
        for name in FILES:
            path = os.path.join(main_root, name)
            fm = frontmatter(path)
            if fm is None and os.path.exists(path):
                notes.append("main checkout config unreadable (sandbox?): " + path)
            elif fm is not None:
                layers.append((path, pr_block(fm)))
        if layers:
            notes.append("worktree has no config; using the main checkout's")

    resolved, sources = {}, {}
    for key in DEFAULTS:
        for path, block in layers:
            value = valid(key, block.get(key))
            if value is not None:
                resolved[key], sources[key] = value, path
                break
            if key in block:
                notes.append("ignored invalid pr.%s=%r in %s" % (key, block[key], path))
        resolved.setdefault(key, DEFAULTS[key])
        sources.setdefault(key, "default")

    naming, naming_src = {}, "default"
    for path, block in layers:
        if isinstance(block.get("branch_naming"), dict):
            naming, naming_src = block["branch_naming"], path
            break

    for key in DEFAULTS:
        print("%s=%s  # %s" % (key, resolved[key], sources[key]))
    for sub in ("pattern", "pattern_no_ticket"):
        print("branch_naming.%s=%s  # %s" % (sub, naming.get(sub, ""), naming_src))
    for note in notes:
        print("note=" + note)
    return 0


if __name__ == "__main__":
    sys.exit(main())
