import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/topic-picker-tests Core/Taxonomy.swift Core/TopicPickerQuery.swift Scripts/test_topic_picker.swift`

@main
enum TopicPickerTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
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

        let shownAll = TopicPickerQuery.shown(topics: Taxonomy.all, subs: { $0.subs }, filter: "")
        let names = shownAll.map(\.name)
        expect(
            names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            "unfiltered picker is A–Z"
        )

        let shownRun = TopicPickerQuery.shown(topics: Taxonomy.all, subs: { $0.subs }, filter: "Run")
        expect(shownRun.contains(where: { $0.id == "fitness" }), "Run lists Fitness")
        expect(!shownRun.contains(where: { $0.id == "gaming" }), "Run does not list Gaming")

        expect(TopicPickerQuery.canAddName("Run", to: fitness.subs), "Run is a new Fitness sub")
        expect(!TopicPickerQuery.canAddName("Running", to: fitness.subs), "Running already exists")
        expect(!TopicPickerQuery.canAddName("r", to: []), "single-letter names are rejected")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
