#if DEBUG
import Foundation
import SwiftData

/// Development-only sample data. Never compiled into a Release build.
///
/// Run with the `-seed` launch argument to populate a fresh library:
///   xcrun simctl launch <device> com.jpwilson.borkmarkr -seed
///
/// Exists so the masonry, the card variants and the dual-axis browse can be
/// exercised without hand-saving thirty links every time the store is reset.
enum DebugSeed {

    static var isRequested: Bool {
        CommandLine.arguments.contains("-seed")
    }

    @MainActor
    static func run(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Bookmark>())) ?? 0
        guard existing == 0 else { return }

        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: .now) ?? .now
        }

        var saved: [Bookmark] = []
        for (offset, sample) in samples.enumerated() {
            guard let url = URL(string: sample.url) else { continue }
            let age = sample.days ?? offset
            let bookmark = Bookmark(
                url: url,
                title: sample.title,
                author: sample.author,
                platform: sample.platform,
                kind: sample.kind,
                categoryID: sample.category,
                subcategory: sample.sub,
                tags: sample.tags,
                text: sample.text,
                durationSeconds: sample.duration,
                noteText: sample.note,
                noteDate: sample.note == nil ? nil : .now,
                savedAt: daysAgo(age)
            )
            // Usage signal. Revisit is built entirely from these two fields, so
            // a seed where nothing was ever opened shows a permanently empty
            // "you keep coming back to" — which is the one section a screenshot
            // has to prove works.
            if sample.opens > 0 {
                bookmark.openCount = sample.opens
                bookmark.lastOpenedAt = daysAgo(sample.openedDaysAgo)
            }
            context.insert(bookmark)
            saved.append(bookmark)
        }

        let quest = Mission(title: "Improve mobility for running", categoryID: "fitness")
        quest.bookmarkIDs = saved.filter { $0.categoryID == "fitness" }.map(\.id)
        quest.todos = [
            QuestTodo(title: "Hip flow before every long run", done: true),
            QuestTodo(title: "Book one physio session"),
            QuestTodo(title: "Try the hamstring set twice a week"),
        ]
        context.insert(quest)

        try? context.save()
    }

    private struct Sample {
        let url: String, title: String, author: String
        let platform: Platform, kind: ItemKind
        let category: String, sub: String
        let tags: [String]
        var text: String? = nil
        var duration: Int? = nil
        var note: String? = nil
        /// Days before now this was saved. Defaults to the sample's position,
        /// which gives one a day; the older block below sets it explicitly so
        /// Revisit's month-ago and 30-vs-30 windows have something in them.
        var days: Int? = nil
        var opens: Int = 0
        var openedDaysAgo: Int = 1
    }

    private static let samples: [Sample] = [
        Sample(url: "https://www.tiktok.com/@physio.jane/video/7390",
               title: "5-minute hip mobility flow you can do at your desk",
               author: "@physio.jane", platform: .tiktok, kind: .clip,
               category: "fitness", sub: "Mobility", tags: ["hips", "desk", "daily"],
               duration: 312, note: "Do this before long runs.", opens: 7, openedDaysAgo: 1),
        Sample(url: "https://x.com/hubermanclips/status/180233",
               title: "Magnesium glycinate thread", author: "@hubermanclips",
               platform: .x, kind: .thread, category: "health", sub: "Sleep",
               tags: ["magnesium", "sleep"],
               text: "Magnesium glycinate is the most over-recommended and least understood sleep supplement. A short thread on what the actual evidence says, and who it genuinely helps:"),
        Sample(url: "https://www.youtube.com/watch?v=protein30",
               title: "I tried the 30g protein breakfast for 30 days — here is what happened",
               author: "@macrofriendly", platform: .youtube, kind: .video,
               category: "nutrition", sub: "High-protein", tags: ["breakfast", "protein"],
               duration: 768, opens: 4, openedDaysAgo: 2),
        Sample(url: "https://www.instagram.com/reel/C8xhamstring",
               title: "4 stretches for tight hamstrings after long runs",
               author: "@run.physio", platform: .instagram, kind: .reel,
               category: "fitness", sub: "Stretching", tags: ["hamstrings", "running"],
               duration: 48, opens: 3, openedDaysAgo: 4),
        Sample(url: "https://www.threads.net/@macromusings/post/991",
               title: "On fasting windows", author: "@macromusings",
               platform: .threads, kind: .thread, category: "nutrition", sub: "Fasting",
               tags: ["fasting"],
               text: "Nobody needs a 16:8 window. They need to stop eating at 11pm. The window is downstream of the actual habit."),
        Sample(url: "https://www.youtube.com/shorts/aZ9kdinner",
               title: "5-ingredient high-protein dinner in 12 minutes",
               author: "@quickmacros", platform: .shorts, kind: .short,
               category: "recipes", sub: "High-protein", tags: ["dinner", "quick"],
               duration: 51),
        Sample(url: "https://arstechnica.com/2026/07/the-quiet-return-of-local-models",
               title: "The quiet return of local models", author: "arstechnica.com",
               platform: .web, kind: .article, category: "ai", sub: "Local models",
               tags: ["local", "inference"]),
        Sample(url: "https://www.tiktok.com/@detailgeek/video/8821",
               title: "Paint correction on a 20 year old daily driver",
               author: "@detailgeek", platform: .tiktok, kind: .clip,
               category: "cars", sub: "Detailing", tags: ["detailing", "paint"],
               duration: 187),
        Sample(url: "https://www.pinterest.com/pin/smallkitchen",
               title: "Small kitchen storage that actually works",
               author: "pinterest.com", platform: .pinterest, kind: .pin,
               category: "cleaning", sub: "Storage", tags: ["kitchen", "storage"]),
        Sample(url: "https://www.instagram.com/reel/C9morning",
               title: "My 10-minute calm morning routine", author: "@calm.mornings",
               platform: .instagram, kind: .reel, category: "wellness",
               sub: "Morning routines", tags: ["morning", "habits"], duration: 39),
        Sample(url: "https://x.com/indexinvestor/status/44120",
               title: "ETFs vs index funds", author: "@indexinvestor",
               platform: .x, kind: .thread, category: "investing", sub: "ETFs & index funds",
               tags: ["etf", "index fund"],
               text: "People use these interchangeably and then get surprised by the tax treatment. The difference that actually matters is how they trade, not what they hold."),
        Sample(url: "https://www.youtube.com/watch?v=unsolvedcase",
               title: "Unsolved: the detective who never closed the case",
               author: "@casefilesdaily", platform: .youtube, kind: .video,
               category: "truecrime", sub: "Cold cases", tags: ["unsolved", "detective"],
               duration: 1432),
        Sample(url: "https://www.tiktok.com/@booktok.sam/video/5512",
               title: "This novel destroyed me in the best way",
               author: "@booktok.sam", platform: .tiktok, kind: .clip,
               category: "books", sub: "Recommendations", tags: ["fiction", "booktok"],
               duration: 62),
        Sample(url: "https://www.youtube.com/shorts/promptagents",
               title: "Prompt patterns for agents that actually finish the task",
               author: "@aibuilds", platform: .shorts, kind: .short,
               category: "ai", sub: "Agents", tags: ["prompting", "agents"],
               duration: 58,
               note: "Try the checklist pattern on the scraper job.", opens: 5, openedDaysAgo: 3),
        Sample(url: "https://www.instagram.com/reel/C10toddler",
               title: "The tantrum reset that finally worked for us",
               author: "@gentle.parent", platform: .instagram, kind: .reel,
               category: "parenting", sub: "Discipline", tags: ["toddlers", "tantrum"],
               duration: 44),
        Sample(url: "https://www.smittenkitchen.com/2026/06/one-pan-orzo",
               title: "One-pan lemon orzo that reheats properly",
               author: "smittenkitchen.com", platform: .web, kind: .article,
               category: "recipes", sub: "One-pan", tags: ["orzo", "weeknight"],
               opens: 2, openedDaysAgo: 6),
        Sample(url: "https://www.tiktok.com/@weldlife/video/3310",
               title: "Reading a weld: what good penetration actually looks like",
               author: "@weldlife", platform: .tiktok, kind: .clip,
               category: "trades", sub: "Welding", tags: ["welding", "technique"],
               duration: 96),
        Sample(url: "https://www.youtube.com/watch?v=gardenbeds",
               title: "No-dig beds, two years on", author: "@plotandplant",
               platform: .youtube, kind: .video, category: "garden", sub: "Vegetables",
               tags: ["no-dig", "beds"], duration: 954),

        // ── Older, so Revisit has a past to talk about ──────────────────────
        // Everything above is one bork a day for the last few weeks, which
        // fills the Library nicely and leaves "a month ago" and the 30-vs-30
        // comparison permanently empty. These carry an explicit `days` and are
        // deliberately lopsided — a run of crypto and investing two months ago,
        // a run of running now — so "What's shifting" has an actual shift.
        Sample(url: "https://www.youtube.com/watch?v=zone2",
               title: "Zone 2, and why every plan starts there",
               author: "@runsciencedaily", platform: .youtube, kind: .video,
               category: "fitness", sub: "Running", tags: ["zone 2", "base"],
               duration: 1104, days: 26),
        Sample(url: "https://www.instagram.com/reel/C11cadence",
               title: "Cadence drills that stop the heel strike",
               author: "@run.physio", platform: .instagram, kind: .reel,
               category: "fitness", sub: "Running", tags: ["cadence", "running"],
               duration: 51, days: 27),
        Sample(url: "https://www.tiktok.com/@physio.jane/video/7420",
               title: "Calf raises: the boring fix for shin pain",
               author: "@physio.jane", platform: .tiktok, kind: .clip,
               category: "fitness", sub: "Strength", tags: ["calves", "running"],
               duration: 143, days: 28),
        Sample(url: "https://www.youtube.com/shorts/hillreps",
               title: "Hill reps in 20 minutes", author: "@quickmiles",
               platform: .shorts, kind: .short, category: "fitness", sub: "Running",
               tags: ["hills", "intervals"], duration: 47, days: 29),
        Sample(url: "https://www.instagram.com/reel/C12fuel",
               title: "What to eat before a long run", author: "@macrofriendly",
               platform: .instagram, kind: .reel, category: "fitness", sub: "Running",
               tags: ["fuelling", "running"], duration: 62, days: 30),
        Sample(url: "https://x.com/onchainkate/status/77120",
               title: "Rollups, in plain English", author: "@onchainkate",
               platform: .x, kind: .thread, category: "crypto", sub: "Ethereum",
               tags: ["rollups", "l2"],
               text: "Every explainer starts with the word \u{201c}sequencer\u{201d} and loses you. Start here instead: a rollup is a way to do the arithmetic somewhere cheap and post the receipt somewhere expensive.",
               days: 33),
        Sample(url: "https://www.youtube.com/watch?v=selfcustody",
               title: "Self-custody without losing everything",
               author: "@keysandcoins", platform: .youtube, kind: .video,
               category: "crypto", sub: "Wallets", tags: ["custody", "seed phrase"],
               duration: 892, days: 35),
        Sample(url: "https://x.com/onchainkate/status/77004",
               title: "Stablecoin yields are somebody's loan",
               author: "@onchainkate", platform: .x, kind: .thread,
               category: "crypto", sub: "Stablecoins", tags: ["yield", "risk"],
               text: "If you cannot name who is borrowing and what happens when they do not pay, the yield is not a yield. It is a queue.",
               days: 38),
        Sample(url: "https://www.tiktok.com/@chartsdaily/video/6610",
               title: "Reading a funding rate without kidding yourself",
               author: "@chartsdaily", platform: .tiktok, kind: .clip,
               category: "crypto", sub: "Trading", tags: ["funding", "leverage"],
               duration: 118, days: 42),
        Sample(url: "https://www.coindesk.com/2026/07/the-quiet-quarter",
               title: "The quiet quarter", author: "coindesk.com",
               platform: .web, kind: .article, category: "crypto", sub: "Markets",
               tags: ["cycle", "quiet"], days: 45),
        Sample(url: "https://www.youtube.com/watch?v=btcstorage",
               title: "Cold storage, six months on", author: "@keysandcoins",
               platform: .youtube, kind: .video, category: "crypto", sub: "Wallets",
               tags: ["cold storage"], duration: 640, days: 48),
        Sample(url: "https://x.com/indexinvestor/status/43880",
               title: "The fee you cannot see", author: "@indexinvestor",
               platform: .x, kind: .thread, category: "investing", sub: "Fees",
               tags: ["fees", "trackers"],
               text: "A 0.7% fund and a 0.07% fund are not a rounding error apart. Over thirty years one of them quietly keeps a quarter of the money.",
               days: 40),
        Sample(url: "https://www.youtube.com/watch?v=rebalance",
               title: "Rebalancing, and when not to bother",
               author: "@plainmoney", platform: .youtube, kind: .video,
               category: "investing", sub: "Portfolio", tags: ["rebalancing"],
               duration: 733, days: 44),
        Sample(url: "https://www.morningstar.com/2026/06/bonds-again",
               title: "Bonds, again", author: "morningstar.com",
               platform: .web, kind: .article, category: "investing", sub: "Bonds",
               tags: ["bonds", "duration"], days: 50),
        Sample(url: "https://www.youtube.com/watch?v=localfirst",
               title: "Local-first apps and the sync problem",
               author: "@buildlogs", platform: .youtube, kind: .video,
               category: "tech", sub: "Software", tags: ["local-first", "sync"],
               duration: 1520, days: 52),
        Sample(url: "https://www.tiktok.com/@shipfast/video/2211",
               title: "One keyboard shortcut per day", author: "@shipfast",
               platform: .tiktok, kind: .clip, category: "tech", sub: "Productivity",
               tags: ["shortcuts"], duration: 39, days: 55),
    ]
}
#endif
