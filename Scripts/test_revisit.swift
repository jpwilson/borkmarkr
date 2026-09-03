import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/revisit-tests Core/Platform.swift Core/Copy.swift Core/Revisit.swift Scripts/test_revisit.swift`

@main
enum RevisitTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // A fixed "now" so nothing here depends on the day it runs.
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 14))!
        let today = calendar.startOfDay(for: now)
        func daysAgo(_ days: Int, hour: Int = 9) -> Date {
            calendar.date(byAdding: .hour, value: hour,
                          to: calendar.date(byAdding: .day, value: -days, to: today)!)!
        }

        var serial = 0
        func bork(
            _ days: Int,
            platform: Platform = .instagram,
            topic: (id: String, name: String)? = nil,
            opens: Int = 0,
            lastOpened: Date? = nil,
            title: String? = nil
        ) -> RevisitBork {
            serial += 1
            return RevisitBork(
                id: "b\(serial)",
                title: title ?? "bork \(serial)",
                platform: platform,
                topicID: topic?.id,
                topicName: topic?.name,
                savedAt: daysAgo(days),
                openCount: opens,
                lastOpenedAt: lastOpened
            )
        }

        let fitness = (id: "fitness", name: "Fitness")
        let crypto = (id: "crypto", name: "Crypto")
        let recipes = (id: "recipes", name: "Recipes")

        // MARK: Thin state

        let thin = Revisit.build(borks: (0..<9).map { bork($0) }, quests: [], now: now, calendar: calendar)
        expect(thin.isThin, "nine borks is still the thin state")
        expect(thin.total == 9, "the thin state still counts what is there")

        let notThin = Revisit.build(borks: (0..<10).map { bork($0) }, quests: [], now: now, calendar: calendar)
        expect(!notThin.isThin, "ten borks fills the screen in")

        // MARK: 1 — Saved this week

        let week = Revisit.build(
            borks: [
                bork(0, platform: .instagram, topic: fitness),
                bork(1, platform: .instagram, topic: fitness),
                bork(2, platform: .x, topic: fitness),
                bork(3, platform: .youtube, topic: recipes),
                // Last week: Fitness had one, Recipes had three.
                bork(8, platform: .x, topic: fitness),
                bork(9, platform: .x, topic: recipes),
                bork(10, platform: .x, topic: recipes),
                bork(11, platform: .x, topic: recipes),
                // Older than both windows.
                bork(40, platform: .web, topic: recipes),
            ],
            quests: [], now: now, calendar: calendar
        )
        let thisWeek = week.thisWeek
        expect(thisWeek?.count == 4, "this week counts the last seven days only")
        expect(
            thisWeek?.headline == "4 borks · 2 Instagram · 1 X · 1 YouTube",
            "the headline splits by platform, biggest first — got \(thisWeek?.headline ?? "nil")"
        )
        expect(
            thisWeek?.rising.first?.id == "fitness",
            "Fitness grew 3→ this week against 1 last week and leads"
        )
        expect(
            thisWeek?.rising.contains { $0.id == "recipes" } == false,
            "Recipes shrank and is not listed as rising"
        )
        expect(
            thisWeek?.rising.first?.previous == 1,
            "growth carries last week's number, not just this week's"
        )

        let quietWeek = Revisit.build(borks: [bork(20), bork(30)], quests: [], now: now, calendar: calendar)
        expect(quietWeek.thisWeek == nil, "a week with no saves hides the section")

        // MARK: 2 — You keep coming back to

        let opened = Revisit.build(
            borks: [
                bork(30, opens: 2, lastOpened: daysAgo(1)),
                bork(31, opens: 9, lastOpened: daysAgo(20)),
                bork(32, opens: 2, lastOpened: daysAgo(9)),
                bork(33, opens: 0),
                bork(34, opens: 1, lastOpened: daysAgo(2)),
                bork(35, opens: 5, lastOpened: daysAgo(30)),
                bork(36, opens: 4, lastOpened: daysAgo(30)),
                bork(37, opens: 3, lastOpened: daysAgo(30)),
            ],
            quests: [], now: now, calendar: calendar
        )
        expect(opened.comingBack.count == 5, "the strip is capped at five")
        expect(opened.comingBack.map(\.openCount) == [9, 5, 4, 3, 2], "sorted by open count")
        expect(
            opened.comingBack.last?.lastOpenedAt == daysAgo(1),
            "ties on open count break by most recently opened"
        )
        expect(
            opened.comingBack.allSatisfy { $0.openCount > 0 },
            "a never-opened bork is never something you keep coming back to"
        )

        // MARK: 3 — Saved, never opened

        let stale = Revisit.build(
            borks: [
                bork(2, opens: 0),                       // too new to count
                bork(8, opens: 0), bork(9, opens: 0),
                bork(30, opens: 0), bork(31, opens: 1),  // opened once — not stale
            ] + (0..<12).map { bork(20 + $0, opens: 0) },
            quests: [], now: now, calendar: calendar
        )
        expect(stale.neverOpened?.total == 15, "never-opened counts everything older than a week")
        expect(stale.neverOpened?.items.count == 15, "the model keeps all of them for the full list")
        expect(stale.neverOpened?.preview.count == Revisit.neverOpenedCap, "the section shows twelve")
        expect(stale.neverOpened?.overflow == 3, "the overflow is what the cap left out")
        expect(
            stale.neverOpened?.headline == "15 things you saved and never looked at.",
            "the copy names the number — got \(stale.neverOpened?.headline ?? "nil")"
        )
        expect(
            (stale.neverOpened?.items.first?.savedAt ?? .distantPast)
                > (stale.neverOpened?.items.last?.savedAt ?? .distantFuture),
            "newest first"
        )
        expect(
            stale.neverOpened?.preview.first?.id == stale.neverOpened?.items.first?.id,
            "the preview is the head of the same list"
        )

        let one = Revisit.build(borks: [bork(20, opens: 0)], quests: [], now: now, calendar: calendar)
        expect(one.neverOpened?.headline == "1 thing you saved and never looked at.", "singular reads properly")

        let allOpened = Revisit.build(borks: [bork(20, opens: 1, lastOpened: now)], quests: [], now: now, calendar: calendar)
        expect(allOpened.neverOpened == nil, "nothing stale hides the section")

        // MARK: 4 — A month ago

        let month = Revisit.build(
            borks: [
                bork(27), bork(28), bork(30), bork(33), bork(35), bork(36),
            ],
            quests: [], now: now, calendar: calendar
        )
        expect(month.monthAgo.count == 3, "capped at three")
        expect(
            month.monthAgo.allSatisfy { $0.savedAt <= daysAgo(28) && $0.savedAt >= daysAgo(35) },
            "only the 28–35 day window"
        )
        expect(
            month.monthAgo.first?.savedAt == daysAgo(28),
            "newest of the window first"
        )

        // MARK: 5 — Side quests in progress

        let quests = Revisit.build(
            borks: [bork(1)],
            quests: [
                RevisitQuest(id: "q1", title: "Improve mobility", remaining: 2),
                RevisitQuest(id: "q2", title: "Finished thing", remaining: 0),
            ],
            now: now, calendar: calendar
        )
        expect(quests.quests.map(\.id) == ["q1"], "only quests with steps left")

        // MARK: 6 — What's shifting

        // 12 recent + 12 earlier = 24, past the floor of 20. Fitness goes
        // 4/12 → 9/12; Crypto goes 8/12 → 3/12.
        let shifting = Revisit.build(
            borks: (0..<9).map { bork(2 + $0 % 20, topic: fitness) }
                + (0..<3).map { _ in bork(5, topic: crypto) }
                + (0..<4).map { _ in bork(40, topic: fitness) }
                + (0..<8).map { _ in bork(45, topic: crypto) },
            quests: [], now: now, calendar: calendar
        )
        expect(shifting.shifts.count == 2, "two topics moved — got \(shifting.shifts.count)")
        expect(
            shifting.shiftSentence == "More Fitness, less Crypto",
            "the sentence is the section — got \(shifting.shiftSentence ?? "nil")"
        )
        expect(shifting.shifts.first?.isUp == true, "the biggest mover leads")

        let tooFew = Revisit.build(
            borks: (0..<5).map { _ in bork(2, topic: fitness) } + (0..<5).map { _ in bork(45, topic: crypto) },
            quests: [], now: now, calendar: calendar
        )
        expect(tooFew.shifts.isEmpty, "under twenty borks across both windows says nothing")
        expect(tooFew.shiftSentence == nil, "and offers no sentence")

        let steady = Revisit.build(
            borks: (0..<12).map { _ in bork(2, topic: fitness) } + (0..<12).map { _ in bork(45, topic: fitness) },
            quests: [], now: now, calendar: calendar
        )
        expect(steady.shifts.isEmpty, "a library that did not change reports no shift")

        // MARK: Nothing at all

        let nothing = Revisit.build(borks: [], quests: [], now: now, calendar: calendar)
        expect(nothing.hasNothing, "an empty library has nothing in any section")
        expect(nothing.total == 0 && nothing.isThin, "and is thin")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
