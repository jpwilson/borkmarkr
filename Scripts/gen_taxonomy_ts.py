#!/usr/bin/env python3
"""Regenerate the Edge Function's copy of the taxonomy from Core/Taxonomy.swift.

The taxonomy has to exist in two places: the app (which renders it) and the
Edge Function (which puts it in the prompt). Two hand-maintained copies of a
612-entry list will drift, and drift here is silent — the model happily returns
a topic ID the app no longer has.

Two things stop that. This script, so the server copy is generated rather than
typed. And client-side validation in SmartCategorizer, so a stale server copy
degrades to "no suggestion" instead of a wrong one.

    python3 Scripts/gen_taxonomy_ts.py

Run it after editing Core/Taxonomy.swift, then redeploy the function.
"""

import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Core" / "Taxonomy.swift"
OUT = ROOT / "supabase" / "functions" / "categorize" / "taxonomy.ts"

TOPIC = re.compile(
    r'Topic\(id: "([^"]+)", name: "([^"]+)", hue: [\d.]+, subs: \[(.*?)\]\)', re.S
)


def main() -> None:
    source = SWIFT.read_text()
    topics = TOPIC.findall(source)
    if len(topics) < 40:
        raise SystemExit(f"Only parsed {len(topics)} topics — the Swift shape changed?")

    lines = []
    for topic_id, name, raw_subs in topics:
        subs = re.findall(r'"([^"]+)"', raw_subs)
        lines.append(f"{topic_id} ({name}): {', '.join(subs)}")

    body = "\n".join(lines)
    sub_count = sum(len(re.findall(r'"([^"]+)"', s)) for _, _, s in topics)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        "// GENERATED FILE — do not edit.\n"
        "// Regenerate with: python3 Scripts/gen_taxonomy_ts.py\n"
        f"// Source: Core/Taxonomy.swift ({len(topics)} topics, {sub_count} subtopics)\n"
        "\n"
        "export const TAXONOMY = `" + body.replace("`", "'") + "`;\n"
        "\n"
        "export const TOPIC_IDS = new Set([\n"
        + "".join(f'  "{t[0]}",\n' for t in topics)
        + "]);\n"
    )
    print(f"Wrote {OUT.relative_to(ROOT)} — {len(topics)} topics, {sub_count} subtopics, {len(body)} chars")


if __name__ == "__main__":
    main()
