#!/usr/bin/env python3
"""Builds docs/llms-full.txt — the plain text of every public page.

Run from the repo root after changing any public page:

    python3 Scripts/gen_llms_full.py

Deliberately dumb: it reads the committed HTML in docs/, drops script, style
and svg, keeps headings, paragraphs, list items and table rows, and writes one
text file. There is no build step on this site, so the output is committed.
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
SITE = "https://bookmarker.lol"

# (url path, file, what the page is for). Order is the order a reader should
# meet them in. Redirect stubs (/get/, /web/) and user content (/c/) are out.
PAGES = [
    ("/", "index.html", "Home and web app"),
    ("/what-is-bookmarker", "what-is-bookmarker.html", "What bookmarker is"),
    ("/app/", "app/index.html", "The iPhone app"),
    ("/faq", "faq.html", "FAQ"),
    ("/alternatives", "alternatives.html", "Alternatives and competitors"),
    ("/vs-twitter-bookmarks", "vs-twitter-bookmarks.html", "Comparison"),
    ("/vs-raindrop", "vs-raindrop.html", "Comparison"),
    ("/vs-twillot", "vs-twillot.html", "Comparison"),
    ("/vs-mymind", "vs-mymind.html", "Comparison"),
    ("/how-to-organize-twitter-bookmarks", "how-to-organize-twitter-bookmarks.html", "Guide"),
    ("/how-to-search-twitter-bookmarks", "how-to-search-twitter-bookmarks.html", "Guide"),
    ("/lifetime", "lifetime.html", "Founding-member reservation"),
    ("/palace/", "palace/index.html", "Library Island"),
    ("/press/", "press/index.html", "Press kit"),
    ("/privacy", "privacy.html", "Privacy policy"),
    ("/terms", "terms.html", "Terms of use"),
]

BLOCK = r"h1|h2|h3|h4|p|li|tr|section|div|td|th|dt|dd|blockquote|ol|ul|table|header|footer|main|article"


# index.html is the web app. Only its signed-out half is prose; the rest is
# button labels and sheet titles that read as noise in a text dump.
HOME_ONLY = re.compile(r'(?s)<section id="auth".*?<!-- \u2500+ App')


def extract(path, crop=None):
    raw = open(path, encoding="utf-8").read()
    if crop:
        m = crop.search(raw)
        if m:
            raw = raw[: raw.index("</head>") + 7] + m.group(0)
    title = re.search(r"(?is)<title>(.*?)</title>", raw)
    desc = re.search(r'(?is)<meta\s+name="description"\s+content="(.*?)"', raw)
    body = re.sub(r"(?is)<(script|style|noscript|svg|template)\b.*?</\1>", " ", raw)
    body = re.sub(r"(?is)<!--.*?-->", " ", body)
    body = re.sub(r"(?is)<head\b.*?</head>", " ", body)
    # Headings keep their level so the text still has a shape.
    for level in (1, 2, 3, 4):
        body = re.sub(r"(?is)<h%d\b[^>]*>(.*?)</h%d>" % (level, level),
                      lambda m, l=level: "\n\n" + "#" * (l + 1) + " " + m.group(1) + "\n", body)
    body = re.sub(r"(?is)<li\b[^>]*>", "\n- ", body)
    body = re.sub(r"(?is)</(%s)>" % BLOCK, "\n", body)
    body = re.sub(r"(?is)<br\s*/?>", "\n", body)
    body = re.sub(r"(?s)<[^>]+>", "", body)
    body = html.unescape(body)
    lines = []
    for line in body.split("\n"):
        line = re.sub(r"[ \t\xa0]+", " ", line).strip()
        if not line:
            if lines and lines[-1] != "":
                lines.append("")
            continue
        if line == "-":
            continue
        if lines and lines[-1] == line:
            continue
        lines.append(line)
    text = "\n".join(lines).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    return (html.unescape(title.group(1)).strip() if title else "",
            html.unescape(desc.group(1)).strip() if desc else "",
            text)


def main():
    out = [
        "# bookmarker — full text of every public page",
        "",
        "bookmarker is a free bookmark manager for iPhone and the web that collects everything you save on",
        "Instagram, X (Twitter), TikTok, YouTube and the open web into one library, files every save into a topic",
        "and subtopic automatically, and lets you search it again later.",
        "",
        "Home: %s/   Short version: %s/llms.txt" % (SITE, SITE),
        "Generated from the committed HTML in docs/ by Scripts/gen_llms_full.py. Last updated: 2026-10-21.",
        "",
    ]
    for path, rel, kind in PAGES:
        full = os.path.join(DOCS, rel)
        if not os.path.exists(full):
            print("missing:", rel, file=sys.stderr)
            return 1
        title, desc, text = extract(full, HOME_ONLY if path == "/" else None)
        out += ["", "=" * 78, "",
                "# %s%s" % (SITE, path),
                "",
                "Title: %s" % title,
                "Description: %s" % desc,
                "Page type: %s" % kind,
                "", text, ""]
    body = "\n".join(out).rstrip() + "\n"
    dest = os.path.join(DOCS, "llms-full.txt")
    open(dest, "w", encoding="utf-8").write(body)
    print("%s — %d bytes, %d words" % (dest, len(body), len(body.split())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
