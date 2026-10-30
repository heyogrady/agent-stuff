#!/usr/bin/env python3
"""Lint a PR title and body against open-pr's mechanical rules.

Covers what a regex can decide: Step E's mechanical pass (leaks, attribution,
emoji, legacy headings, walls of text), the body's structure (bare lede,
collapsible names, order and blank line, nothing after the last one), the
bug-fix sections, and the outcome title shape. Bold glossaries, enumerating
prose, and everything in the judgment pass are left to the behavioral pack.

Usage: lint-body.py BODY.md [--title "Title"] [--title-style outcome|any]
Prints one `RULE  line N: detail` per hit. Exit status: number of hits.
"""
import argparse
import re
import sys

COLLAPSIBLES = ["All decisions", "In this PR", "Verification", "Post-deploy monitoring"]
BUG_SECTIONS = ["What was wrong", "Summary", "Evidence", "Merge Danger",
                "Potential follow-ups", "Verify in production"]
URGENCY = {"Do soon", "Plan it", "Nice to have"}
LEAKS = [r"docs/plans", r"docs/specs", r"\b(per|in|from|following) the plan\b",
         r"\bthe plan (called|calls|said|says)\b", r"brainstorm", r"\bUnit \d+\b",
         r"\bPhase \d+\b", r"\(as planned\)"]
ATTRIBUTION = [r"Generated with", r"Co-Authored-By", "\U0001F916",
               r"\b(claude\.ai|claude\.com|anthropic\.com|openai\.com|chatgpt\.com)\b"]
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-⛿✅✔✖"
                   "❌❎✨⭐⭕]")
ABBREV = re.compile(r"\b(e\.g|i\.e|etc|vs|approx)\.", re.I)
SENTENCE_WORDS = 30   # the rule says "about 25"; leave room for "about"
PARAGRAPH_SENTENCES = 4


def prose_lines(lines):
    """Yield (n, line) outside fenced code, with inline code and quotes blanked."""
    fence = None
    for n, line in enumerate(lines, 1):
        m = re.match(r"\s*(`{3,}|~{3,})", line)
        if m:
            mark = m.group(1)
            if fence is None:
                fence = mark
            elif mark.startswith(fence[0]) and len(mark) >= len(fence):
                fence = None
            continue
        if fence is None:
            yield n, line


def scrub(line):
    line = re.sub(r"`[^`]*`", "x", line)
    return re.sub(r"\"[^\"]*\"|“[^”]*”", "x", line)


def lint(body, title, title_style):
    hits = []
    hit = lambda rule, n, msg: hits.append((rule, n, msg))
    lines = body.splitlines()
    prose = list(prose_lines(lines))
    bug_fix = any(re.match(r"## What was wrong\s*$", l) for _, l in prose)

    for n, line in prose:
        flat = scrub(line)
        for pat in LEAKS:
            if re.search(pat, flat, re.I):
                hit("E1-leak", n, line.strip()[:80])
                break
        for pat in ATTRIBUTION:
            if re.search(pat, line, re.I):
                hit("E2-attribution", n, line.strip()[:80])
                break
        if EMOJI.search(flat) and not re.search("\U0001F916", line):
            hit("E2a-emoji", n, line.strip()[:80])
        h = re.match(r"(#{1,6})\s+(.*?)\s*$", line)
        if h:
            name = h.group(2)
            legacy = (
                (name.lower() == "summary" and not bug_fix)
                or name.lower() in ("demo", "screenshots", "staging evidence", "follow-ups",
                                    "in this pr", "verification", "verified",
                                    "post-deploy monitoring"))
            if legacy:
                hit("E3-legacy", n, line.strip())
        if re.search(r"TL;DR", line, re.I):
            hit("E3-legacy", n, "TL;DR")
        if re.match(r">\s*\[!NOTE\]", line):
            nxt = " ".join(l for _, l in prose if n < _ <= n + 3)
            if re.search(r"follow", nxt, re.I):
                hit("E3-legacy", n, "follow-ups callout")
        if re.match(r"\s*([-*+]|\d+\.)\s+#\d", line) or re.match(r"#\d", line):
            hit("S5-issue-autolink", n, line.strip()[:80])

    # E5: walls of text, per paragraph or list item, outside tables and code
    block, start = [], None

    def flush():
        if not block:
            return
        text = ABBREV.sub(lambda m: m.group(1), scrub(" ".join(block)))
        text = re.sub(r"<[^>]+>", " ", text)
        sentences = [s for s in re.split(r"(?<=[.!?])[*_)\"”]*\s+(?=[A-Z0-9*_(\[`])", text) if s.strip()]
        if len(sentences) > PARAGRAPH_SENTENCES:
            hit("E5-wall", start, "paragraph of %d sentences" % len(sentences))
        for s in sentences:
            words = len(re.findall(r"\S+", s))
            if words > SENTENCE_WORDS:
                hit("E5-wall", start, "%d-word sentence: %s..." % (words, s[:50]))

    in_code = {n for n, _ in prose}
    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        boundary = (n not in in_code or not stripped or stripped.startswith(("|", "#", "<"))
                    or re.match(r"([-*+]|\d+\.)\s", stripped))
        if boundary:
            flush()
            block, start = [], None
            if n in in_code and re.match(r"([-*+]|\d+\.)\s", stripped):
                block, start = [re.sub(r"^([-*+]|\d+\.)\s+", "", stripped)], n
            continue
        if start is None:
            start = n
        block.append(stripped)
    flush()

    # S1: the lede is a bare paragraph at the top
    first = next(((n, l) for n, l in enumerate(lines, 1) if l.strip()), None)
    if first is None:
        hit("S1-lede", 1, "empty body")
    elif re.match(r"\s*(#|<|\||[-*+]\s|\d+\.\s|>|```)", first[1]):
        hit("S1-lede", first[0], "body opens with something other than a paragraph")

    # S2-S4: collapsibles
    seen = []
    for n, line in enumerate(lines, 1):
        if "<details" not in line:
            continue
        m = re.match(r"<details><summary><strong>(.+?)</strong></summary>\s*$", line.strip())
        if not m:
            hit("S2-collapsible", n, "not <details><summary><strong>Name</strong></summary>")
            continue
        name = m.group(1)
        if name not in COLLAPSIBLES:
            hit("S2-collapsible", n, "unknown collapsible %r" % name)
        else:
            seen.append((n, COLLAPSIBLES.index(name), name))
        if n < len(lines) and lines[n].strip():
            hit("S3-blank-after-summary", n, name)
    for (n1, i1, a), (n2, i2, b) in zip(seen, seen[1:]):
        if i2 <= i1:
            hit("S2-collapsible", n2, "%r after %r is out of order" % (b, a))
    closes = [n for n, l in enumerate(lines, 1) if l.strip() == "</details>"]
    if closes and any(l.strip() for l in lines[closes[-1]:]):
        hit("S4-after-collapsibles", closes[-1] + 1, "content after the last collapsible")

    # B1-B3: bug-fix sections
    if bug_fix:
        order = [(n, BUG_SECTIONS.index(m.group(1))) for n, l in prose
                 for m in [re.match(r"## (.+?)\s*$", l)] if m and m.group(1) in BUG_SECTIONS]
        for (n1, i1), (n2, i2) in zip(order, order[1:]):
            if i2 <= i1:
                hit("B1-bug-order", n2, "%s after %s" % (BUG_SECTIONS[i2], BUG_SECTIONS[i1]))
        if not any(i == 2 for _, i in order):
            hit("B1-bug-order", 1, "bug fix has no ## Evidence")
        section, bullets, rows = None, 0, []
        for n, line in prose:
            m = re.match(r"## (.+?)\s*$", line)
            if m:
                section = m.group(1)
                continue
            if section == "What was wrong" and re.match(r"[-*+]\s", line):
                bullets += 1
            if section == "Potential follow-ups" and line.startswith("|"):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if cells and cells[0] not in ("Urgency",) and not set(cells[0]) <= set("-: "):
                    rows.append((n, cells[0]))
        if not 3 <= bullets <= 5:
            hit("B2-what-was-wrong", 1, "%d bullets; the rule is three to five" % bullets)
        for n, grade in rows:
            if grade not in URGENCY:
                hit("B3-follow-ups", n, "urgency %r is not Do soon / Plan it / Nice to have" % grade)
        if len(rows) > 5:
            hit("B3-follow-ups", rows[5][0], "%d rows; at most five" % len(rows))

    # T1: outcome title
    if title is not None:
        if not title.strip() or title.rstrip().endswith("."):
            hit("T1-title", 0, "empty or ends with a period: %r" % title)
        if title_style == "outcome":
            words = title.split()
            if not 3 <= len(words) <= 5:
                hit("T1-title", 0, "%d words; the outcome style is 3-5" % len(words))
            low = [w for w in words if w[0].isalpha() and not w[0].isupper()]
            if low:
                hit("T1-title", 0, "not Title Case: %s" % ", ".join(low))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("body")
    ap.add_argument("--title")
    ap.add_argument("--title-style", default="any", choices=["outcome", "any"])
    args = ap.parse_args()
    with open(args.body, encoding="utf-8") as fh:
        hits = lint(fh.read(), args.title, args.title_style)
    for rule, n, msg in hits:
        print("%-24s line %d: %s" % (rule, n, msg))
    return min(len(hits), 125)


if __name__ == "__main__":
    sys.exit(main())
