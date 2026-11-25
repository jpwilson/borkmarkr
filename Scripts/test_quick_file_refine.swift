import Foundation

/// The refine panel's ordering rules (`QuickFileRefine`) against the fixture
/// the web's port is checked against too, plus the snapshot helpers.
///
/// Compile and run from the repo root:
/// `swiftc -parse-as-library -o /tmp/quick-file-refine-tests Core/Platform.swift Core/TagRecency.swift Core/QuickFile/QuickFileRefine.swift Scripts/test_quick_file_refine.swift && /tmp/quick-file-refine-tests`

/// `QuickFileRefineSource.none` reads the taxonomy, which this script doesn't
/// compile. A stand-in with no topics.
enum Taxonomy {
    struct Entry { let subs: [String] }
    static func category(id: String) -> Entry? { nil }
}

@main
enum QuickFileRefineTests {
    struct Cases: Decodable {
        struct Subtopic: Decodable { let name: String; let all, suggested, used, expect: [String] }
        struct Tag: Decodable {
            struct Chip: Decodable { let tag: String; let on: Bool }
            let name: String
            let chosen, suggested, recent: [String]
            let expect: [Chip]
        }
        struct Clean: Decodable { let raw: String; let expect: String? }
        let subtopics: [Subtopic]
        let tags: [Tag]
        let clean: [Clean]
    }

    static func main() {
        var failures = 0
        var passed = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { passed += 1; print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        let path = "Scripts/fixtures/quick_file_refine_cases.json"
        guard let data = FileManager.default.contents(atPath: path),
              let cases = try? JSONDecoder().decode(Cases.self, from: data) else {
            print("FAIL can't read \(path) (run from the repo root)")
            exit(1)
        }

        for c in cases.subtopics {
            let got = QuickFileRefine.subtopicChips(all: c.all, suggested: c.suggested, used: c.used)
            expect(got == c.expect, "subtopics: \(c.name)" + (got == c.expect ? "" : " — got \(got)"))
        }
        for c in cases.tags {
            let got = QuickFileRefine.tagChips(chosen: c.chosen, suggested: c.suggested, recent: c.recent)
            let want = c.expect.map { QuickFileRefine.TagChip(tag: $0.tag, isOn: $0.on) }
            expect(got == want, "tags: \(c.name)" + (got == want ? "" : " — got \(got)"))
        }
        for c in cases.clean {
            let got = QuickFileRefine.cleanTag(c.raw)
            expect(got == c.expect, "clean: \(c.raw.debugDescription)" + (got == c.expect ? "" : " — got \(String(describing: got))"))
        }

        // Most-used subtopics: count, then the newest, then A–Z.
        let now = Date()
        let day: TimeInterval = 86_400
        let uses: [QuickFileRefine.Use] = [
            .init(categoryID: "fitness", subcategory: "Yoga", at: now.addingTimeInterval(-9 * day)),
            .init(categoryID: "fitness", subcategory: "Yoga", at: now.addingTimeInterval(-8 * day)),
            .init(categoryID: "fitness", subcategory: "Running", at: now.addingTimeInterval(-day)),
            .init(categoryID: "fitness", subcategory: "Cycling", at: now.addingTimeInterval(-day)),
            .init(categoryID: "fitness", subcategory: "Mobility", at: now.addingTimeInterval(-5 * day)),
            .init(categoryID: "fitness", subcategory: nil, at: now),
            .init(categoryID: "recipes", subcategory: "Pasta", at: now),
        ]
        let use = QuickFileRefine.subUse(uses, perTopic: 3)
        expect(use["fitness"] == ["Yoga", "Cycling", "Running"], "subUse: count, newest, A–Z, capped")
        expect(use["recipes"] == ["Pasta"], "subUse: per topic")

        // Recent tags per filing, falling back to the topic's.
        let items: [TagRecency.Item] = [
            .init(categoryID: "fitness", subcategory: "Running", tags: ["tempo", "TikTok"], at: now),
            .init(categoryID: "fitness", subcategory: "Yoga", tags: ["stretch"], at: now.addingTimeInterval(-day)),
            .init(categoryID: "recipes", subcategory: nil, tags: [], at: now),
        ]
        let table = QuickFileRefine.recentTagTable(items)
        let running = QuickFileRefine.recentTags(in: table, categoryID: "fitness", subcategory: "Running")
        expect(running.first == "tempo" && !running.contains("tiktok"), "recentTags: the pair's own, no site names")
        let other = QuickFileRefine.recentTags(in: table, categoryID: "fitness", subcategory: "Cycling")
        expect(Set(other) == ["tempo", "stretch"], "recentTags: an unknown pair falls back to the topic")
        expect(QuickFileRefine.recentTags(in: table, categoryID: "recipes", subcategory: nil).isEmpty,
               "recentTags: an untagged topic has none")
        expect(QuickFileRefine.recentTagTable(items, pairs: 1).count == 1, "recentTagTable: capped by pairs")

        print("\n\(passed) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
