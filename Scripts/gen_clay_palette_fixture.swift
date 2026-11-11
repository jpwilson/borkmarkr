import Foundation

/// Writes `Scripts/fixtures/clay_palette_cases.json`: the clay palette
/// (`Core/ClayPalette.swift`) for every integer hue 0–359, every built-in
/// topic and Sand. The Swift and the web tests both read it, so the iPhone and
/// `docs/palette.js` can never drift apart without one of them failing.
///
/// Custom topics' hues are integers (`CustomTopic.nextHue` steps by 7°; the
/// web's `CUSTOM_HUES` are whole degrees), so the 360 integer hues cover them.
///
/// Regenerate after changing the recipe, from the repo root:
/// `swiftc -parse-as-library -o /tmp/gen-clay-palette Core/ClayPalette.swift Core/Taxonomy.swift Scripts/gen_clay_palette_fixture.swift && /tmp/gen-clay-palette`

@main
enum GenClayPaletteFixture {
    static func entry(_ c: ClayColours) -> [String: String] {
        ["tint": c.tint.hex, "mid": c.mid.hex, "deep": c.deep.hex]
    }

    static func main() throws {
        var hues: [[String: Any]] = []
        for h in 0..<360 {
            var row: [String: Any] = entry(ClayRecipe.colours(hue: Double(h)))
            row["hue"] = h
            hues.append(row)
        }
        let topics: [[String: Any]] = Taxonomy.all.map { topic in
            var row: [String: Any] = entry(ClayRecipe.colours(hue: topic.hue))
            row["id"] = topic.id
            row["hue"] = topic.hue
            return row
        }
        let fixture: [String: Any] = [
            "about": "Clay palette cases, written by Scripts/gen_clay_palette_fixture.swift from Core/ClayPalette.swift. Do not edit by hand.",
            "hues": hues,
            "topics": topics,
            "neutral": entry(ClayRecipe.neutral),
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: "Scripts/fixtures/clay_palette_cases.json")
        try (data + Data("\n".utf8)).write(to: url)
        print("wrote \(hues.count) hues, \(topics.count) topics and Sand to \(url.path)")
    }
}
