import Foundation

/// macOS-runnable checks for the create-flow helpers. Compile with:
///
/// ```
/// swiftc -parse-as-library -o /tmp/borkmarkr-core-tests \
///   Core/Platform.swift Core/Taxonomy.swift \
///   Core/TagRecency.swift Core/TopicPickerQuery.swift \
///   Scripts/test_core.swift
/// /tmp/borkmarkr-core-tests
/// ```

@main
enum CoreTests {
    static func main() {
        var failures = 0

        func expect(_ cond: Bool, _ message: String) {
            if cond {
                print("ok   \(message)")
            } else {
                failures += 1
                print("FAIL \(message)")
            }
        }

        func topic(_ id: String) -> Topic {
            guard let found = Taxonomy.all.first(where: { $0.id == id }) else {
                fatalError("missing topic \(id)")
            }
            return found
        }

        let fitness = topic("fitness")
        let gaming = topic("gaming")
        let marketing = topic("marketing")

        expect(
            TopicPickerQuery.matchRank(topicName: fitness.name, subs: fitness.subs, needle: "run") == 2,
            "run matches Fitness via Running"
        )
        expect(
            TopicPickerQuery.matchRank(topicName: gaming.name, subs: gaming.subs, needle: "run") == nil,
            "run does not match Gaming/Speedruns"
        )
        expect(
            TopicPickerQuery.matchRank(topicName: gaming.name, subs: gaming.subs, needle: "speed") == 2,
            "speed matches Gaming via Speedruns"
        )
        expect(
            TopicPickerQuery.matchRank(topicName: gaming.name, subs: gaming.subs, needle: "game") == 0,
            "game matches Gaming by topic token"
        )
        expect(
            TopicPickerQuery.matchRank(topicName: marketing.name, subs: marketing.subs, needle: "brand") == 2,
            "brand matches Marketing via Branding"
        )
        expect(
            TopicPickerQuery.matchingSubs(gaming.subs, needle: "run").isEmpty,
            "no Gaming sub is a run- token"
        )
        expect(
            TopicPickerQuery.matchingSubs(fitness.subs, needle: "run").contains("Running"),
            "Running is highlighted for run"
        )

        let shownAll = TopicPickerQuery.shown(
            topics: Taxonomy.all,
            subs: { $0.subs },
            filter: ""
        )
        let names = shownAll.map(\.name)
        expect(
            names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            "unfiltered picker is A–Z"
        )

        let shownRun = TopicPickerQuery.shown(
            topics: Taxonomy.all,
            subs: { $0.subs },
            filter: "Run"
        )
        expect(shownRun.contains(where: { $0.id == "fitness" }), "Run lists Fitness")
        expect(!shownRun.contains(where: { $0.id == "gaming" }), "Run does not list Gaming")

        expect(TopicPickerQuery.canAddName("Run", to: fitness.subs), "Run is a new Fitness sub")
        expect(!TopicPickerQuery.canAddName("Running", to: fitness.subs), "Running already exists")
        expect(!TopicPickerQuery.canAddName("r", to: []), "single-letter names are rejected")

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
            in: items,
            categoryID: "marketing",
            subcategory: "Ads",
            excluding: [],
            limit: 2
        )
        expect(ads.first == "hook", "most recent Ads tag wins")
        expect(ads.contains("ugc"), "older Ads tag still appears")
        expect(!ads.contains("instagram"), "platform names are dropped")
        expect(!ads.contains("audit"), "SEO-only tag is not in the Ads exact pair")
        expect(!ads.contains("goata"), "Fitness tags stay out of Marketing › Ads")

        let adsFilled = TagRecency.suggestions(
            in: items,
            categoryID: "marketing",
            subcategory: "Ads",
            excluding: [],
            limit: 8
        )
        expect(adsFilled.contains("audit"), "empty-ish Ads row fills from Marketing")

        let none = TagRecency.suggestions(in: items, categoryID: nil, subcategory: nil)
        expect(none.isEmpty, "no category → no suggestions")

        let prefix = TagRecency.suggestions(
            in: items,
            categoryID: "marketing",
            subcategory: "Ads",
            excluding: [],
            prefix: "h"
        )
        expect(prefix == ["hook"], "prefix filter keeps hook")

        let excluded = TagRecency.suggestions(
            in: items,
            categoryID: "marketing",
            subcategory: "Ads",
            excluding: ["hook"]
        )
        expect(!excluded.contains("hook"), "already-applied tags are excluded")

        let running = TagRecency.suggestions(
            in: items,
            categoryID: "fitness",
            subcategory: "Running",
            limit: 2
        )
        expect(running.first == "tempo", "recency beats the extra older tempo use")
        expect(!running.contains("injuries"), "Yoga injuries is not an exact Running tag")

        if failures > 0 {
            print("\n\(failures) failed")
            exit(1)
        }
        print("\nall passed")
    }
}
