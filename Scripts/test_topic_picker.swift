import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/topic-picker-tests Core/Taxonomy.swift Core/TopicPickerQuery.swift Core/Initials.swift Scripts/test_topic_picker.swift`

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

        // ── Best match first ──────────────────────────────────────────────
        // The founder's report: typing "runn" listed Fitness above their own
        // Running topic, because Fitness has a Running subtopic and F sorts
        // before R. A topic whose own name matches beats one that matches only
        // through a subtopic; the picker auto-expands the first row, so the
        // wrong first row is also the wrong open row.
        let running = Topic(id: "custom.running", name: "Running", hue: 21, subs: ["Intervals", "Races"])
        let withCustom = Taxonomy.all + [running]
        let ranked = TopicPickerQuery.shown(topics: withCustom, subs: { $0.subs }, filter: "runn")
        expect(ranked.first?.id == "custom.running",
               "runn puts the user's own Running topic first, not Fitness\n     got      \(ranked.first?.name ?? "nothing")")
        expect(ranked.contains(where: { $0.id == "fitness" }),
               "…and Fitness is still listed, below it")
        if let mine = ranked.firstIndex(where: { $0.id == "custom.running" }),
           let fit = ranked.firstIndex(where: { $0.id == "fitness" }) {
            expect(mine < fit, "a name match outranks a subtopic match")
        }

        // Within a tier the old order stands: a name-token match, then a
        // name that merely contains the letters, then a subtopic match — and
        // A–Z inside each of those.
        let aardvark = Topic(id: "custom.aardvark", name: "Aardvark running", hue: 5, subs: [])
        let prerunner = Topic(id: "custom.prerunner", name: "Prerunner", hue: 7, subs: [])
        let tiered = TopicPickerQuery.shown(topics: [prerunner, running, fitness, aardvark],
                                            subs: { $0.subs }, filter: "runn")
        expect(tiered.map(\.id) == ["custom.aardvark", "custom.running", "custom.prerunner", "fitness"],
               "name token (A–Z), then name-contains, then subtopic\n     got      \(tiered.map(\.id))")

        // Being a custom topic is not itself a tier — it wins here on the name.
        let strength = Topic(id: "custom.strength", name: "Strength", hue: 9, subs: [])
        let byName = TopicPickerQuery.shown(topics: [strength, fitness], subs: { $0.subs }, filter: "strength")
        expect(byName.map(\.id) == ["custom.strength", "fitness"],
               "a custom topic is ranked by the same rule, not floated or sunk")

        // Nothing matching still returns nothing — the sheet is what offers
        // "Add topic", and only then does it sit above the (empty) list.
        expect(TopicPickerQuery.shown(topics: withCustom, subs: { $0.subs }, filter: "zzzzqq").isEmpty,
               "a query nothing matches shows no topics")

        // Subtopics are A–Z, built-in and yours in one list (iOS 1.0.2).
        let fitnessSubs = TopicPickerQuery.alphabetical(fitness.subs)
        expect(
            fitnessSubs == fitness.subs.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            "built-in subtopics come back A–Z"
        )
        expect(
            Set(fitnessSubs) == Set(fitness.subs),
            "sorting subtopics neither drops nor invents one"
        )
        // JP's report (Seb round): Health read Conditions, Medications,
        // Symptoms, Sleep, Heart & BP, Diabetes… — the authored order.
        let health = topic("health")
        let healthAZ = TopicPickerQuery.alphabetical(health.subs)
        expect(
            healthAZ == health.subs.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                && healthAZ != health.subs,
            "Health's subtopics are drawn A–Z, not in authored order\n     got      \(healthAZ.prefix(4))"
        )
        let mixed = TopicPickerQuery.alphabetical(["Zone 10", "bouldering", "Zone 2", "Mobility"])
        expect(
            mixed == ["bouldering", "Mobility", "Zone 2", "Zone 10"],
            "a user's own subtopics sort in with the built-ins, case-insensitively and numerically"
        )

        expect(TopicPickerQuery.canAddName("Run", to: fitness.subs), "Run is a new Fitness sub")
        expect(!TopicPickerQuery.canAddName("Running", to: fitness.subs), "Running already exists")
        expect(!TopicPickerQuery.canAddName("r", to: []), "single-letter names are rejected")

        // ── Initials — whose letter the avatar wears ──────────────────────
        // The Library header showed a hardcoded "J" (the founder's) to every
        // person, signed in or not. One rule now, shared by both avatars.
        func initial(_ name: String?, _ email: String?) -> String? {
            Initials.letter(displayName: name, email: email)
        }
        expect(initial("Sebastian", nil) == "S", "a display name gives its first letter")
        expect(initial("seb", nil) == "S", "…uppercased")
        expect(initial(nil, "seb@example.com") == "S", "no name: the email's local part")
        expect(initial("", "jp@example.com") == "J", "an empty name falls through to the email")
        expect(initial("   ", "jp@example.com") == "J", "and so does a blank one")
        expect(initial("Jean-Paul", "seb@example.com") == "J", "the name wins over the email")
        expect(initial("élodie", nil) == "É", "accents survive: élodie is É")
        expect(initial("ßtefan", nil) == "S", "one grapheme, even where uppercasing makes two (ß → SS)")
        expect(initial("🦊 Sam", nil) == "S", "emoji and punctuation are skipped")
        expect(initial("_sam", nil) == "S", "…and so is a leading underscore")
        expect(initial(nil, "_underscore@example.com") == "U", "…in an email too")
        expect(initial("日本語", nil) == "日", "a CJK name keeps its first character")
        expect(initial(nil, "42crows@example.com") == "4", "a digit is a letter for this purpose")
        expect(initial(nil, "sam") == "S", "an address with no @ is used whole")
        expect(initial(nil, nil) == nil, "signed out: nothing — the circle wears a glyph, not a J")
        expect(initial(nil, "") == nil, "an empty email is nobody")
        expect(initial(nil, "@example.com") == nil, "and so is one with nothing before the @")
        expect(initial("...", "!!!") == nil, "nothing letter-like anywhere is nobody")
        expect(Initials.localPart(of: "a@b@c") == "a", "the local part stops at the first @")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
