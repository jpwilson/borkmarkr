import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/quest-brief-tests Core/Supabase.swift Core/QuestBrief.swift Scripts/test_quest_brief.swift`
///
/// Covers what goes up, what is kept, and when it is asked for again. The
/// call itself is not here — it needs a signed-in session and a server, and
/// every failure path in it returns nil, which is the template.

@main
enum QuestBriefTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        // ── What goes up ──────────────────────────────────────────────────
        let todo = QuestBrief.Request.Todo.self
        let request = QuestBrief.request(
            id: "q1",
            title: "  Breathing  ",
            topic: "Health",
            subtopic: "",
            titles: ["Box breathing for runners", "   ", "Nasal breathing on easy runs"],
            todos: [todo.init(title: "Try 4-7-8 tonight", done: false), todo.init(title: "  ", done: true)]
        )
        expect(request != nil, "a named quest makes a request")
        expect(request?.title == "Breathing", "the title is trimmed")
        expect(request?.topic == "Health", "the topic rides along")
        expect(request?.subtopic == nil, "a blank subtopic is dropped, not sent as empty")
        expect(request?.titles == ["Box breathing for runners", "Nasal breathing on easy runs"], "blank titles are dropped")
        expect(request?.todos.count == 1, "blank steps are dropped")
        expect(request?.todos.first?.title == "Try 4-7-8 tonight", "a step keeps its text")

        expect(QuestBrief.request(id: "q", title: "   ", topic: nil, subtopic: nil, titles: [], todos: []) == nil,
               "no title, no request — the function would refuse it")

        let empty = QuestBrief.request(id: "q", title: "Sleep properly", topic: nil, subtopic: nil, titles: [], todos: [])
        expect(empty != nil && empty?.titles.isEmpty == true,
               "a quest with nothing on it is still asked about — that is the case Seb hit")

        let many = QuestBrief.request(
            id: "q", title: "Marathon", topic: "Fitness", subtopic: "Running",
            titles: (1...20).map { "Title \($0)" },
            todos: (1...12).map { todo.init(title: "Step \($0)", done: false) }
        )
        expect(many?.titles.count == QuestBrief.maxTitles, "at most \(QuestBrief.maxTitles) titles go up")
        expect(many?.todos.count == QuestBrief.maxTodos, "at most \(QuestBrief.maxTodos) steps go up")

        let long = QuestBrief.request(
            id: "q", title: String(repeating: "a", count: 400), topic: nil, subtopic: nil,
            titles: [String(repeating: "b", count: 400)], todos: []
        )
        expect(long?.title.count == QuestBrief.maxField, "a title is clamped to \(QuestBrief.maxField)")
        expect(long?.titles.first?.count == QuestBrief.maxField, "a bork title is clamped too")

        if let request, let data = try? JSONEncoder().encode(request),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            expect(object["id"] as? String == "q1", "the wire shape carries the quest id")
            expect((object["titles"] as? [String])?.count == 2, "the wire shape carries titles as strings")
            expect(((object["todos"] as? [[String: Any]])?.first?["done"] as? Bool) == false, "the wire shape carries done flags")
            expect(object["subtopic"] == nil || object["subtopic"] is NSNull, "a nil subtopic is absent or null, never \"\"")
        } else {
            expect(false, "the request encodes as JSON")
        }

        // ── What is kept ──────────────────────────────────────────────────
        func parse(_ text: String) -> QuestBrief.Brief? {
            QuestBrief.parse(Data(text.utf8))
        }

        let good = parse(#"{"summary":"You want to breathe easier on runs. Two borks so far, both on nasal breathing.","steps":["Try nasal breathing on Sunday's run","Log how the 4-7-8 felt","Try nasal breathing on Sunday's run","- Book a breathwork class"]}"#)
        expect(good != nil, "a real reply parses")
        expect(good?.summary.hasPrefix("You want to breathe") == true, "the summary is kept as written")
        expect(good?.steps == ["Try nasal breathing on Sunday's run", "Log how the 4-7-8 felt", "Book a breathwork class"],
               "steps are deduplicated and a leading bullet is stripped")

        expect(parse(#"{"summary":null,"steps":[]}"#) == nil, "the function's empty reply is no brief")
        expect(parse(#"{"summary":"   ","steps":["Do something"]}"#) == nil, "steps without a summary are not a brief")
        expect(parse(#"{"steps":["Do something"]}"#) == nil, "a missing summary is no brief")
        expect(parse("not json") == nil, "garbage is no brief")
        expect(parse(#"{"summary":"\"Quoted.\"","steps":[]}"#)?.summary == "Quoted.", "wrapping quotes are removed")

        let five = parse(#"{"summary":"Fine.","steps":["One","Two","Three","Four","Five"]}"#)
        expect(five?.steps.count == QuestBrief.maxSteps, "at most \(QuestBrief.maxSteps) steps are kept")

        let overlong = parse("{\"summary\":\"\(String(repeating: "x", count: 600))\",\"steps\":[\"\(String(repeating: "y", count: 200))\",\"Short\"]}")
        expect(overlong?.summary.count == QuestBrief.maxSummary, "a rambling summary is cut at \(QuestBrief.maxSummary)")
        expect(overlong?.steps == ["Short"], "a step over \(QuestBrief.maxStep) characters is dropped, not cut")

        expect(parse(#"{"summary":"Fine.","steps":"not an array"}"#)?.steps == [], "steps that are not an array read as none")

        // ── Storage round trip ────────────────────────────────────────────
        let brief = QuestBrief.Brief(summary: "Two sentences. Really.", steps: ["A", "B"])
        let stored = QuestBrief.encode(brief)
        expect(stored != nil, "a brief encodes for the store")
        expect(QuestBrief.decode(stored) == brief, "and decodes back unchanged")
        expect(QuestBrief.decode(nil) == nil, "a quest with no brief decodes to nil")
        expect(QuestBrief.decode("{") == nil, "a corrupt column decodes to nil, not a crash")

        // ── When to ask again ─────────────────────────────────────────────
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 60 * 60
        expect(QuestBrief.isStale(briefAt: nil, briefCount: nil, count: 0, now: now), "no brief is stale")
        expect(!QuestBrief.isStale(briefAt: now.addingTimeInterval(-day), briefCount: 3, count: 3, now: now),
               "a day-old brief for the same pile is fresh")
        expect(QuestBrief.isStale(briefAt: now.addingTimeInterval(-day), briefCount: 3, count: 4, now: now),
               "one more bork makes it stale")
        expect(QuestBrief.isStale(briefAt: now.addingTimeInterval(-day), briefCount: 3, count: 2, now: now),
               "one fewer bork makes it stale")
        expect(QuestBrief.isStale(briefAt: now.addingTimeInterval(-8 * day), briefCount: 3, count: 3, now: now),
               "eight days makes it stale")
        expect(!QuestBrief.isStale(briefAt: now.addingTimeInterval(-6 * day), briefCount: 3, count: 3, now: now),
               "six days does not")
        expect(QuestBrief.isStale(briefAt: now.addingTimeInterval(-day), briefCount: nil, count: 3, now: now),
               "a brief with no count on record is stale — it predates the rule")

        // ── Steps already taken ───────────────────────────────────────────
        let offered = QuestBrief.Brief(summary: "S.", steps: ["Book the physio", "Try the hip flow", "Run easy on Sunday"])
        expect(QuestBrief.pendingSteps(offered, existing: ["book the physio ", "Run Easy On Sunday"]) == ["Try the hip flow"],
               "a step already on the to-do list is not offered again, whatever its case")
        expect(QuestBrief.pendingSteps(nil, existing: ["anything"]) == [], "no brief, no steps")
        expect(QuestBrief.pendingSteps(offered, existing: []).count == 3, "a fresh to-do list gets all three")

        print(failures == 0 ? "\nAll quest brief checks passed." : "\n\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
