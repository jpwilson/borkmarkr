#!/usr/bin/env python3
"""Regenerate the web app's copy of the taxonomy from Core/Taxonomy.swift.

Sibling of gen_taxonomy_ts.py, but for docs/web/ — and it keeps the hue,
because the web renders chips and gradients the same way the app does.

    python3 Scripts/gen_taxonomy_js.py

Run it after editing Core/Taxonomy.swift.
"""

import json
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Core" / "Taxonomy.swift"
OUT = ROOT / "docs" / "taxonomy.js"

TOPIC = re.compile(
    r'Topic\(id: "([^"]+)", name: "([^"]+)", hue: ([\d.]+), subs: \[(.*?)\]\)', re.S
)


def main() -> None:
    source = SWIFT.read_text()
    topics = TOPIC.findall(source)
    if len(topics) < 40:
        raise SystemExit(f"Only parsed {len(topics)} topics — the Swift shape changed?")

    out = []
    for topic_id, name, hue, raw_subs in topics:
        subs = re.findall(r'"([^"]+)"', raw_subs)
        out.append({"id": topic_id, "name": name, "hue": float(hue), "subs": subs})

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        "// GENERATED FILE — do not edit.\n"
        "// Regenerate with: python3 Scripts/gen_taxonomy_js.py\n"
        f"// Source: Core/Taxonomy.swift ({len(topics)} topics)\n"
        "const TAXONOMY = " + json.dumps(out, ensure_ascii=False, indent=1) + ";\n"
    )
    print(f"Wrote {OUT.relative_to(ROOT)} ({len(topics)} topics)")


if __name__ == "__main__":
    main()
