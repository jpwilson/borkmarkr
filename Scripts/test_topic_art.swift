import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/topic-art-tests Core/Supabase.swift Core/TopicArt.swift Scripts/test_topic_art.swift`
///
/// Covers the decisions that spend money or leave a tile blank: which ids are
/// drawable, when a topic is worth asking about again, and which few get
/// asked on one pass. The network call itself isn't here — it needs a signed
/// in session and a server, and every failure path in it returns nil.

@main
enum TopicArtTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        // ── Which ids are drawable ────────────────────────────────────────
        // Must agree with CustomTopic.makeID and with TOPIC_ID in
        // supabase/functions/topic-art/index.ts. A built-in has bundled art
        // and must never reach the function.
        expect(TopicArt.isCustomID("custom.juice"), "a custom id is drawable")
        expect(TopicArt.isCustomID("custom.looksmaxxing"), "the screenshot's blank topic is drawable")
        expect(TopicArt.isCustomID("custom.trail-running"), "a hyphenated slug is drawable")
        expect(TopicArt.isCustomID("custom.zone2"), "digits are allowed in a slug")
        expect(!TopicArt.isCustomID("marketing"), "a built-in topic is not drawable")
        expect(!TopicArt.isCustomID("health"), "Health is bundled, not drawn")
        expect(!TopicArt.isCustomID("custom."), "an empty slug is not drawable")
        expect(!TopicArt.isCustomID("custom.-juice"), "a leading dash is not a makeID output")
        expect(!TopicArt.isCustomID("custom.juice-"), "a trailing dash is not a makeID output")
        expect(!TopicArt.isCustomID("custom.a--b"), "makeID collapses runs of dashes")
        expect(!TopicArt.isCustomID("custom.Juice"), "makeID lowercases, so uppercase is not ours")
        expect(!TopicArt.isCustomID("custom.juice/../etc"), "a path is not a topic id")
        expect(!TopicArt.isCustomID(""), "an empty id is not drawable")

        // makeID's own output must satisfy the check — this is the contract
        // between the two, and the reason the app can trust the server's 400.
        for raw in ["Juice", "Looksmaxxing", "Trail running", "Zone 2", "Hair & grooming", "  spaced  "] {
            let id = "custom." + raw.lowercased()
                .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
                .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            expect(TopicArt.isCustomID(id), "makeID(\"\(raw)\") → \(id) is drawable")
        }

        // ── When to ask ───────────────────────────────────────────────────
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = now.addingTimeInterval(-TopicArt.retryInterval - 60)
        let anHourAgo = now.addingTimeInterval(-3600)

        expect(
            TopicArt.wants(id: "custom.juice", hasArt: false, requestedAt: nil, now: now),
            "a new custom topic with no art is asked about"
        )
        expect(
            !TopicArt.wants(id: "custom.juice", hasArt: true, requestedAt: nil, now: now),
            "a topic that already has art is never asked about again"
        )
        expect(
            !TopicArt.wants(id: "marketing", hasArt: false, requestedAt: nil, now: now),
            "a built-in is never asked about, art or not"
        )
        expect(
            !TopicArt.wants(id: "custom.juice", hasArt: false, requestedAt: anHourAgo, now: now),
            "a recent failure is not retried on the next Browse appearance"
        )
        expect(
            TopicArt.wants(id: "custom.juice", hasArt: false, requestedAt: yesterday, now: now),
            "a failure from over a day ago is retried"
        )

        // ── Which few get asked ───────────────────────────────────────────
        struct Fake {
            let id: String
            let hasArt: Bool
            let requestedAt: Date?
            let created: Date
        }
        func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

        let topics = [
            Fake(id: "custom.juice",        hasArt: false, requestedAt: nil,       created: at(-500)),
            Fake(id: "custom.retention",    hasArt: false, requestedAt: nil,       created: at(-900)),
            Fake(id: "custom.looksmaxxing", hasArt: false, requestedAt: nil,       created: at(-700)),
            Fake(id: "custom.conspiracies", hasArt: false, requestedAt: nil,       created: at(-300)),
            Fake(id: "custom.done",         hasArt: true,  requestedAt: at(-800),  created: at(-1000)),
            Fake(id: "custom.justtried",    hasArt: false, requestedAt: anHourAgo, created: at(-1100)),
            Fake(id: "marketing",           hasArt: false, requestedAt: nil,       created: at(-2000)),
        ]
        let picked = TopicArt.backfillOrder(
            topics, id: \.id, hasArt: \.hasArt, requestedAt: \.requestedAt, created: \.created, now: now
        ).map(\.id)

        expect(picked.count == TopicArt.backfillBatch, "one pass asks for at most \(TopicArt.backfillBatch)")
        expect(
            picked == ["custom.retention", "custom.looksmaxxing", "custom.juice"],
            "oldest topics first, capped: \(picked)"
        )
        expect(!picked.contains("custom.done"), "a topic with art is not re-drawn")
        expect(!picked.contains("custom.justtried"), "a topic tried an hour ago waits")
        expect(!picked.contains("marketing"), "a built-in never reaches the backfill")

        let nothingToDo = TopicArt.backfillOrder(
            [Fake(id: "custom.done", hasArt: true, requestedAt: nil, created: at(-1))],
            id: \.id, hasArt: \.hasArt, requestedAt: \.requestedAt, created: \.created, now: now
        )
        expect(nothingToDo.isEmpty, "a fully drawn library asks for nothing")

        let noTopics = TopicArt.backfillOrder(
            [Fake](), id: \.id, hasArt: \.hasArt, requestedAt: \.requestedAt, created: \.created, now: now
        )
        expect(noTopics.isEmpty, "a library with no topics of its own asks for nothing")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
