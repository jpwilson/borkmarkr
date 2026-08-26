import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/tag-recency-tests Core/Platform.swift Core/TagRecency.swift Scripts/test_tag_recency.swift`

@main
enum TagRecencyTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        let now = Date()
        let day: TimeInterval = 86_400
        let items: [TagRecency.Item] = [
            .init(categoryID: "marketing", subcategory: "Ads", tags: ["ugc", "instagram"], at: now.addingTimeInterval(-day)),
            .init(categoryID: "marketing", subcategory: "Ads", tags: ["hook"], at: now),
            .init(categoryID: "marketing", subcategory: "SEO", tags: ["audit"], at: now.addingTimeInterval(-2 * day)),
            .init(categoryID: "fitness", subcategory: "Running", tags: ["goata"], at: now.addingTimeInterval(-30 * day)),
            .init(categoryID: "fitness", subcategory: "Running", tags: ["tempo"], at: now.addingTimeInterval(-day)),
            .init(categoryID: "fitness", subcategory: "Yoga", tags: ["injuries"], at: now.addingTimeInterval(-3600)),
        ]

        let ads = TagRecency.suggestions(
            in: items, categoryID: "marketing", subcategory: "Ads", excluding: [], limit: 2
        )
        expect(ads.first == "hook", "most recent Ads tag wins")
        expect(ads.contains("ugc"), "older Ads tag still appears")
        expect(!ads.contains("instagram"), "platform names are dropped")
        expect(!ads.contains("audit"), "SEO-only tag is not in the Ads exact pair")
        expect(!ads.contains("goata"), "Fitness tags stay out of Marketing › Ads")

        let adsFilled = TagRecency.suggestions(
            in: items, categoryID: "marketing", subcategory: "Ads", excluding: [], limit: 8
        )
        expect(adsFilled.contains("audit"), "thin Ads row fills from Marketing")

        expect(
            TagRecency.suggestions(in: items, categoryID: nil, subcategory: nil).isEmpty,
            "no category → no suggestions"
        )

        let prefix = TagRecency.suggestions(
            in: items, categoryID: "marketing", subcategory: "Ads", excluding: [], prefix: "h"
        )
        expect(prefix == ["hook"], "prefix filter keeps hook")

        let excluded = TagRecency.suggestions(
            in: items, categoryID: "marketing", subcategory: "Ads", excluding: ["hook"]
        )
        expect(!excluded.contains("hook"), "already-applied tags are excluded")

        let running = TagRecency.suggestions(
            in: items, categoryID: "fitness", subcategory: "Running", limit: 2
        )
        expect(running.first == "tempo", "recency beats an older tag")
        expect(!running.contains("injuries"), "Yoga injuries is not an exact Running tag")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
