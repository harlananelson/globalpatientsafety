#!/usr/bin/env python3
"""Post-process a built Quarto page: alt text, table header ids, focusable code."""

from __future__ import annotations

import html
import re
import sys

CSS = """
a.skip-link { position: absolute; left: 0; top: -3rem; background: #fff; color: #0b4f6a; padding: .5rem 1rem; z-index: 2000; }
a.skip-link:focus { top: 0; }
.llm-access { background: #e7eef3; color: #1a2332; padding: .75rem 1rem; font-family: Inter, sans-serif; }
.llm-access a { color: #0b4f6a; }
#quarto-document-content a, #TOC a, nav.toc a { color: #0b4f6a; }
:focus-visible { outline: 3px solid #0b4f6a; outline-offset: 2px; }
"""

HEAD_LINKS = """<meta name="description" content="Machine path: GET /pipeline?sponsor= on this site, and GET https://faers.mobi/signals for FAERS signals.">
<link rel="alternate" type="text/markdown" href="/{page}.md">
<link rel="alternate" href="/llms.txt" title="llms.txt">
<link rel="service-desc" type="application/json" href="/openapi.json">
<style>{css}</style>
"""


def _has_attr(tag: str, name: str) -> bool:
    """True when the attribute is real, not a substring of a data URI."""
    stripped = re.sub(r'"[^"]*"', '""', tag)
    stripped = re.sub(r"'[^']*'", "''", stripped)
    return re.search(rf"\b{name}\s*=", stripped, flags=re.I) is not None


def add_alts(text: str) -> str:
    headings = []
    for match in re.finditer(r"<h[1-3]\b[^>]*>(.*?)</h[1-3]>", text, flags=re.I | re.S):
        label = re.sub(r"<[^>]+>", "", match.group(1))
        label = re.sub(r"\s+", " ", label).strip()
        headings.append((match.start(), label))

    def alt_for(pos: int) -> str:
        label = "Chart"
        for start, heading in headings:
            if start < pos and heading:
                label = heading
        return f"Chart: {label}. The numbers are also in the tables on this page."

    def repl(match: re.Match[str]) -> str:
        tag = match.group(0)
        if _has_attr(tag, "alt"):
            return tag
        alt = html.escape(alt_for(match.start()), quote=True)
        return tag[:-1] + f' alt="{alt}">'

    return re.sub(r"<img\b[^>]*>", repl, text, flags=re.I)


def fix_headers(text: str) -> str:
    ids = set(re.findall(r'\bid="([^"]+)"', text))

    def repl(match: re.Match[str]) -> str:
        raw = match.group(1)
        if raw in ids:
            return match.group(0)
        hyphen = raw.replace(" ", "-")
        if hyphen in ids:
            return f'headers="{hyphen}"'
        return match.group(0)

    return re.sub(r'headers="([^"]*)"', repl, text)


def focusable_pre(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        tag = match.group(0)
        if _has_attr(tag, "tabindex"):
            return tag
        return tag[:-1] + ' tabindex="0">'

    return re.sub(r"<pre\b[^>]*>", repl, text, flags=re.I)


def focusable_main(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        tag = match.group(1)
        if _has_attr(tag, "tabindex"):
            return match.group(0)
        return tag + ' tabindex="-1">'

    return re.sub(
        r'(<main\b[^>]*\bid="quarto-document-content"[^>]*)>',
        repl,
        text,
        count=1,
        flags=re.I,
    )


def inject_head(text: str, page: str) -> str:
    block = HEAD_LINKS.format(page=html.escape(page, quote=True), css=CSS)
    # A description we already inserted should not be duplicated on a second pass.
    if 'rel="service-desc"' in text:
        return text
    return text.replace("</head>", block + "</head>", 1)


def polish(text: str, page: str) -> str:
    text = inject_head(text, page)
    text = add_alts(text)
    text = fix_headers(text)
    text = focusable_pre(text)
    text = focusable_main(text)
    return text


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: polish_html.py FILE PAGE", file=sys.stderr)
        return 2
    path, page = argv[1], argv[2]
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    updated = polish(text, page)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(updated)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
