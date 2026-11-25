import Foundation

/// The clay palette (`Core/ClayPalette.swift`): the fixture both platforms read,
/// the SYSTEM.md reference rows, and the two contrast rules for every hue.
///
/// Compile and run from the repo root:
/// `swiftc -parse-as-library -o /tmp/clay-palette-tests Core/ClayPalette.swift Core/Taxonomy.swift Scripts/test_clay_palette.swift && /tmp/clay-palette-tests`

@main
enum ClayPaletteTests {
    struct Entry: Decodable { let tint, mid, deep: String; let hue: Double?; let id: String? }
    struct Cases: Decodable { let hues: [Entry]; let topics: [Entry]; let neutral: Entry }

    static func main() {
        var failures = 0
        var passed = 0
        func expect(_ cond: Bool, _ message: @autoclosure () -> String) {
            if cond { passed += 1 } else { failures += 1; print("FAIL \(message())") }
        }

        // 1. The fixture matches exactly (it is what palette.js is held to).
        let path = "Scripts/fixtures/clay_palette_cases.json"
        guard let data = FileManager.default.contents(atPath: path),
              let cases = try? JSONDecoder().decode(Cases.self, from: data) else {
            print("FAIL could not read \(path)"); exit(1)
        }
        func same(_ c: ClayColours, _ e: Entry) -> Bool {
            c.tint.hex == e.tint && c.mid.hex == e.mid && c.deep.hex == e.deep
        }
        expect(cases.hues.count == 360, "fixture has 360 hues, not \(cases.hues.count)")
        for e in cases.hues {
            let c = ClayRecipe.colours(hue: e.hue ?? -1)
            expect(same(c, e), "hue \(e.hue ?? -1): \(c.tint.hex) \(c.mid.hex) \(c.deep.hex) ≠ fixture \(e.tint) \(e.mid) \(e.deep)")
        }
        expect(cases.topics.count == Taxonomy.all.count, "fixture has every built-in topic")
        for topic in Taxonomy.all {
            guard let e = cases.topics.first(where: { $0.id == topic.id }) else {
                expect(false, "fixture is missing \(topic.id)"); continue
            }
            expect(e.hue == topic.hue, "\(topic.id)'s hue is \(topic.hue) in Taxonomy, \(e.hue ?? -1) in the fixture")
            expect(same(ClayRecipe.colours(hue: topic.hue), e), "\(topic.id) matches the fixture")
        }
        expect(same(ClayRecipe.neutral, cases.neutral), "Sand matches the fixture")

        // 2. The reference rows: the topic each row was drawn for lands within
        //    ±6 per channel; Sand is the row exactly.
        func distance(_ a: ClayRGB, _ b: ClayRGB) -> Int {
            max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
        }
        var worstReference = 0
        for ref in ClayRecipe.references {
            let got = ref.topicHue.map { ClayRecipe.colours(hue: $0) } ?? ClayRecipe.neutral
            let d = [distance(got.tint, ref.colours.tint), distance(got.mid, ref.colours.mid), distance(got.deep, ref.colours.deep)]
            worstReference = max(worstReference, d.max() ?? 0)
            let label = "\(ref.family) (hue \(ref.topicHue.map { "\(Int($0))" } ?? "Sand")): \(got.tint.hex) \(got.mid.hex) \(got.deep.hex)"
            if ref.topicHue == nil {
                expect(d == [0, 0, 0], "\(label) is the Sand row exactly")
            } else {
                expect(d.allSatisfy { $0 <= 6 }, "\(label) within ±6 of the row (off by \(d))")
            }
        }
        // The topics the brief names, by id, so a hue change in Taxonomy shows up here.
        let named: [(String, String)] = [("garden", "Sage"), ("travel", "Dusty blue"), ("health", "Rose"),
                                         ("ai", "Lilac"), ("nutrition", "Teal"), ("recipes", "Ochre"),
                                         ("cars", "Terracotta")]
        for (id, family) in named {
            guard let topic = Taxonomy.all.first(where: { $0.id == id }),
                  let ref = ClayRecipe.references.first(where: { $0.family == family }) else {
                expect(false, "\(id) / \(family) exist"); continue
            }
            let got = ClayRecipe.colours(hue: topic.hue)
            let d = [distance(got.tint, ref.colours.tint), distance(got.mid, ref.colours.mid), distance(got.deep, ref.colours.deep)]
            expect(d.allSatisfy { $0 <= 6 }, "\(id) lands on \(family) within ±6 (off by \(d))")
        }

        // 3. Contrast, both rules, for every hue, every built-in and Sand.
        var worstDeepOnTint = (ratio: 99.0, what: "")
        var worstWhiteOnDeep = (ratio: 99.0, what: "")
        func check(_ c: ClayColours, _ what: String) {
            let a = ClayRecipe.contrast(c.deep, c.tint)
            let b = ClayRecipe.contrast(.white, c.deep)
            expect(a >= 4.5, "\(what): deep on tint \(String(format: "%.2f", a)):1 < 4.5")
            expect(b >= 4.5, "\(what): white on deep \(String(format: "%.2f", b)):1 < 4.5")
            if a < worstDeepOnTint.ratio { worstDeepOnTint = (a, what) }
            if b < worstWhiteOnDeep.ratio { worstWhiteOnDeep = (b, what) }
        }
        for h in 0..<360 { check(ClayRecipe.colours(hue: Double(h)), "hue \(h)") }
        for topic in Taxonomy.all { check(ClayRecipe.colours(hue: topic.hue), topic.id) }
        check(ClayRecipe.neutral, "Sand")

        print(String(format: "worst deep on tint %.2f:1 (%@), worst white on deep %.2f:1 (%@), reference rows within %d/255",
                     worstDeepOnTint.ratio, worstDeepOnTint.what, worstWhiteOnDeep.ratio, worstWhiteOnDeep.what, worstReference))
        print("\(passed) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
