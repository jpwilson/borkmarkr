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
        // Must agree with TopicArt.customID (CustomTopic.makeID forwards to
        // it) and with TOPIC_ID in supabase/functions/topic-art/index.ts. A
        // built-in has bundled art and must never reach the function.
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

        // ── The id a name gets ────────────────────────────────────────────
        // This table is duplicated verbatim in Scripts/test_browse.mjs against
        // docs/index.html's makeTopicID. That is the whole point: a topic
        // invented on the phone and the same topic invented in the web tab
        // have to land on one id, or the two disagree about which topic a bork
        // is even in. If you change one table, change both.
        let ids: [(String, String)] = [
            ("Juice", "custom.juice"),
            ("Looksmaxxing", "custom.looksmaxxing"),
            ("Trail running", "custom.trail-running"),
            ("Zone 2", "custom.zone-2"),
            ("Hair & grooming", "custom.hair-grooming"),
            ("  spaced  ", "custom.spaced"),
            // The build 13 fix. "Café culture" used to keep its é, which no
            // TOPIC_ID and no ART_ID accepts, so it never got art.
            ("Café culture", "custom.cafe-culture"),
            ("Cafe culture", "custom.cafe-culture"),
            ("Über alles", "custom.uber-alles"),
            ("Crème brûlée", "custom.creme-brulee"),
            ("Naïve", "custom.naive"),
            ("ÅNGSTRÖM", "custom.angstrom"),
            ("!!!", "custom.topic"),
            // Nothing Latin survives the fold, so the hash is what keeps two
            // of them from being one topic. See TopicArt.customID.
            ("北京", "custom.topic-36943181"),
            ("Готовка", "custom.topic-9888f5f3"),
            ("Ελλάδα", "custom.topic-f49bab5a"),
        ]
        for (name, id) in ids {
            let made = TopicArt.customID(from: name)
            expect(made == id, "customID(\"\(name)\") is \(id)\n     got      \(made)")
            expect(TopicArt.isCustomID(id), "\(id) is drawable")
        }
        expect(TopicArt.customID(from: "Café culture") == TopicArt.customID(from: "Cafe culture"),
               "the accent is not a second topic")
        expect(TopicArt.customID(from: "北京") != TopicArt.customID(from: "Готовка"),
               "two names with no Latin in them are still two topics")

        // Store.foldCustomTopicIDs repairs an id it finds in the store by
        // folding its slug, which has to land where the *name* lands and has
        // to be a no-op the second time it runs.
        expect(TopicArt.customID(from: "café-culture") == "custom.cafe-culture",
               "re-folding an old accented id lands where the name does")
        expect(TopicArt.customID(from: "trail-running") == "custom.trail-running",
               "re-folding an id that was already fine changes nothing")
        expect(TopicArt.customID(from: "topic-36943181") == "custom.topic-36943181",
               "and a hashed id is stable under a second fold")

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

        // A transient failure comes back within the hour; a server give-up waits a day.
        let stampNow = Date()
        let transient = TopicArt.requestStamp(reason: "http-402", now: stampNow)
        expect(TopicArt.wants(id: "custom.juice", hasArt: false, requestedAt: transient,
                              now: stampNow.addingTimeInterval(TopicArt.transientRetryInterval + 1)),
               "a 402 is asked about again after an hour")
        expect(!TopicArt.wants(id: "custom.juice", hasArt: false, requestedAt: transient,
                               now: stampNow.addingTimeInterval(TopicArt.transientRetryInterval - 60)),
               "…but not before")
        let gaveUp = TopicArt.requestStamp(reason: "given-up", now: stampNow)
        expect(!TopicArt.wants(id: "custom.juice", hasArt: false, requestedAt: gaveUp,
                               now: stampNow.addingTimeInterval(TopicArt.transientRetryInterval + 1)),
               "a give-up still waits the full day")
        expect(TopicArt.requestStamp(reason: nil, now: stampNow) == stampNow, "success stamps now")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
