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

        // `-borks N` caps the live library so the save-limit surfaces can be
        // photographed at an exact count; `-waiting M` then adds borks flagged
        // as having arrived over the limit. Both are DEBUG-only — see
        // `ScreenshotDefaults`.
        let cap = ScreenshotDefaults.seedBorks
        let liveSamples = cap.map { Array(samples.prefix(max(0, $0))) } ?? samples
        let waitingSamples = cap == nil
            ? []
            : Array(samples.dropFirst(liveSamples.count).prefix(ScreenshotDefaults.seedWaiting))

        var saved: [Bookmark] = []
        for (offset, sample) in liveSamples.enumerated() {
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
            // The cover the platform published, as `PreviewFetcher` would have
            // written it. Set here rather than passed to `init` so the seed
            // doesn't widen a model initialiser it is the only caller of.
            bookmark.imageURLString = sample.image
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

        // A bork the share sheet accepted after the limit was reached: saved,
        // on the phone, greyed in the Library, waiting for an account.
        for (offset, sample) in waitingSamples.enumerated() {
            guard let url = URL(string: sample.url) else { continue }
            let bookmark = Bookmark(
                url: url, title: sample.title, author: sample.author,
                platform: sample.platform, kind: sample.kind,
                categoryID: sample.category, subcategory: sample.sub,
                tags: sample.tags, text: sample.text,
                durationSeconds: sample.duration,
                savedAt: Date.now.addingTimeInterval(Double(offset) * -600)
            )
            bookmark.imageURLString = sample.image
            bookmark.waitingSince = Date.now.addingTimeInterval(Double(offset) * -600)
            context.insert(bookmark)
        }

        // A capped seed is a save-limit screenshot, not a Browse one: the
        // custom topic and the side quest would push the live count past the
        // number that was asked for.
        guard cap == nil else {
            try? context.save()
            return
        }

        // A topic the user invented, with subtopics to match, mixing into the
        // grid under A–Z. The 50 built-ins carry bundled clay art; a topic you
        // made has none until the `topic-art` function draws it.
        //
        // The seed used to leave that art off, which made this its only
        // exercise of the hero band's tint fallback — and drew a blank paper
        // tile two rows into Browse, the first thing the eye lands on in the
        // store screenshot, where it reads as a broken image. So it gets the
        // scene `topic-art` would have drawn for it. The fallback is still
        // exercised by every topic created at runtime, in the seconds between
        // creating one and its art landing.
        let custom = CustomTopic(name: "Trail running", hue: CustomTopic.nextHue(existing: []))
        custom.imageURLString = Cover.trailRunning
        // Stamped as already asked for, so Browse's backfill doesn't spend a
        // round trip re-drawing a topic that has its scene.
        custom.artRequestedAt = .now
        context.insert(custom)
        // `-myTopics "Running"` — extra topics of the user's own, for the
        // shots that need one with a particular name. See ScreenshotDefaults.
        var extras = [custom]
        for name in ScreenshotDefaults.seedCustomTopics {
            let topic = CustomTopic(name: TaxonomyName.formatted(name),
                                    hue: CustomTopic.nextHue(existing: extras))
            context.insert(topic)
            extras.append(topic)
        }
        for name in ["Races", "Shoes", "Ultras"] {
            context.insert(CustomSubtopic(categoryID: custom.id, name: name))
        }
        for (offset, sample) in customSamples.enumerated() {
            guard let url = URL(string: sample.url) else { continue }
            let bookmark = Bookmark(
                url: url,
                title: sample.title,
                author: sample.author,
                platform: sample.platform,
                kind: sample.kind,
                categoryID: custom.id,
                subcategory: sample.sub,
                tags: sample.tags,
                durationSeconds: sample.duration,
                savedAt: daysAgo(offset * 3 + 2)
            )
            bookmark.imageURLString = sample.image
            context.insert(bookmark)
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

    /// Filed under the seeded custom topic rather than a built-in, so the
    /// `category` field is left off — `run` supplies it.
    private static let customSamples: [Sample] = [
        Sample(url: "https://www.youtube.com/watch?v=utmb2026",
               title: "UTMB, from the back of the pack", author: "@longwaydown",
               platform: .youtube, kind: .video, category: "", sub: "Races",
               tags: ["ultra", "utmb"], duration: 1840,
               image: Cover.talkingHead),
        Sample(url: "https://www.instagram.com/reel/C13trailshoes",
               title: "Three trail shoes, six hundred kilometres",
               author: "@dirt.miles", platform: .instagram, kind: .reel,
               category: "", sub: "Shoes", tags: ["shoes", "gear"], duration: 74,
               image: Cover.mobility),
        Sample(url: "https://www.tiktok.com/@vertgang/video/9912",
               title: "Power hiking is not cheating", author: "@vertgang",
               platform: .tiktok, kind: .clip, category: "", sub: "Ultras",
               tags: ["vert", "technique"], duration: 58,
               image: Cover.footPain),
        Sample(url: "https://www.irunfar.com/2026/07/night-running-kit",
               title: "What to carry when the race runs into the dark",
               author: "irunfar.com", platform: .web, kind: .article,
               category: "", sub: "Ultras", tags: ["kit", "night"],
               image: Cover.physiology),
        Sample(url: "https://www.youtube.com/shorts/downhillform",
               title: "Downhill form drills for beaten quads",
               author: "@dirt.miles", platform: .shorts, kind: .short,
               category: "", sub: "Ultras", tags: ["downhill", "quads"], duration: 44,
               image: Cover.explainer),
    ]

    /// Real cover art for the seeded borks.
    ///
    /// Without these every seeded media bork falls back to `CoverImage`'s
    /// gradient — which is the right thing in the app (Instagram and TikTok
    /// don't publish thumbnails to unauthenticated requests, so for a real
    /// library it is permanent, and deliberately handsome) and the wrong thing
    /// in an App Store screenshot, where a column of flat gradients behind a
    /// play glyph reads as "the images failed to load".
    ///
    /// These are real thumbnails from the founder's own library, copied into
    /// our storage bucket, so what the screenshots show is a genuine cover
    /// arriving through the ordinary `AsyncImage` path. Nothing is drawn over
    /// the app's own pixels and no UI is invented.
    ///
    /// Named rather than numbered so an assignment below can be read for what
    /// it puts on the card. Seven of the eight saved covers are here: the
    /// eighth is a 1.8 KB all-black frame (mean luminance 0.9 of 255), which
    /// on a card is indistinguishable from the missing image this exists to
    /// fix, so it is deliberately left out.
    private enum Cover {
        private static let bucket = "https://pcjuxnhqxyfvgagnblzv.supabase.co/storage/v1/object/public/thumbs/2571a6ca-9bb5-4a2e-82af-889f0a75b940/"

        /// Neck and shoulder mobility routine.
        static let mobility = bucket + "430c1837cabd5a4df0f14b8658916f9e144666aac9e9cc92c42aea8b59ceb14c"
        /// Piece to camera in front of a health infographic.
        static let explainer = bucket + "ba1b3db32c46b3d6f6112b75eef3509451257ef24a99f73b7fcbfac7023323f1"
        /// Anatomy overlay on a standing figure.
        static let physiology = bucket + "291a8478c88c2e925cf95d42396ecff200410041e752f6796c7d25295d096637"
        /// Bare feet on rock — "I have pain in my foot when I run".
        static let footPain = bucket + "1664ce24840262280721058735aaf3ce6c5d0235e3ed6abbe993b6f3c346b449"
        /// A screenshotted post, the way a long text clip gets saved.
        static let postScreenshot = bucket + "c2a51b2fc848e622fe4bd05fcd820b78a73f3daec11c3b02153d236c93df4500"
        /// Talking to camera, shot in a car.
        static let talkingHead = bucket + "c39f2b624a35cb86f55d8948f6cb1f6c68a366ac3cfc1bf811262a0ea43d1353"
        /// Supermarket aisle, scoring food.
        static let groceries = bucket + "3348920972b98fa1d12afdb8e739de3a9d2b7054e7fd5f76da320bc8b353df7f"

        /// The clay scene the `topic-art` function draws for a running topic,
        /// already published on the marketing site. Stands in for generated
        /// art so the seeded custom topic is not blank paper in a screenshot.
        static let trailRunning = "https://bookmarker.lol/img/quests/run.jpg"
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
        /// Cover thumbnail. Last, so the memberwise initialiser takes it last
        /// and every sample below can name it on its own final line.
        ///
        /// Left nil on X and Threads posts: a text post has no cover in the
        /// real app either — it renders as the post itself, with the handle
        /// and the platform mark — so a cover there would be invented UI, not
        /// a fix.
        var image: String? = nil
    }

    private static let samples: [Sample] = [
        Sample(url: "https://www.tiktok.com/@physio.jane/video/7390",
               title: "5-minute hip mobility flow you can do at your desk",
               author: "@physio.jane", platform: .tiktok, kind: .clip,
               category: "fitness", sub: "Mobility", tags: ["hips", "desk", "daily"],
               duration: 312, note: "Do this before long runs.", opens: 7, openedDaysAgo: 1,
               image: Cover.mobility),
        Sample(url: "https://x.com/hubermanclips/status/180233",
               title: "Magnesium glycinate thread", author: "@hubermanclips",
               platform: .x, kind: .thread, category: "health", sub: "Sleep",
               tags: ["magnesium", "sleep"],
               text: "Magnesium glycinate is the most over-recommended and least understood sleep supplement. A short thread on what the actual evidence says, and who it genuinely helps:"),
        Sample(url: "https://www.youtube.com/watch?v=protein30",
               title: "I tried the 30g protein breakfast for 30 days — here is what happened",
               author: "@macrofriendly", platform: .youtube, kind: .video,
               category: "nutrition", sub: "High-protein", tags: ["breakfast", "protein"],
               duration: 768, opens: 4, openedDaysAgo: 2,
               image: Cover.groceries),
        Sample(url: "https://www.instagram.com/reel/C8xhamstring",
               title: "4 stretches for tight hamstrings after long runs",
               author: "@run.physio", platform: .instagram, kind: .reel,
               category: "fitness", sub: "Stretching", tags: ["hamstrings", "running"],
               duration: 48, opens: 3, openedDaysAgo: 4,
               image: Cover.footPain),
        Sample(url: "https://www.threads.net/@macromusings/post/991",
               title: "On fasting windows", author: "@macromusings",
               platform: .threads, kind: .thread, category: "nutrition", sub: "Fasting",
               tags: ["fasting"],
               text: "Nobody needs a 16:8 window. They need to stop eating at 11pm. The window is downstream of the actual habit."),
        Sample(url: "https://www.youtube.com/shorts/aZ9kdinner",
               title: "5-ingredient high-protein dinner in 12 minutes",
               author: "@quickmacros", platform: .shorts, kind: .short,
               category: "recipes", sub: "High-protein", tags: ["dinner", "quick"],
               duration: 51,
               image: Cover.groceries),
        Sample(url: "https://arstechnica.com/2026/07/the-quiet-return-of-local-models",
               title: "The quiet return of local models", author: "arstechnica.com",
               platform: .web, kind: .article, category: "ai", sub: "Local models",
               tags: ["local", "inference"],
               image: Cover.postScreenshot),
        Sample(url: "https://www.tiktok.com/@detailgeek/video/8821",
               title: "Paint correction on a 20 year old daily driver",
               author: "@detailgeek", platform: .tiktok, kind: .clip,
               category: "cars", sub: "Detailing", tags: ["detailing", "paint"],
               duration: 187,
               image: Cover.talkingHead),
        Sample(url: "https://www.pinterest.com/pin/smallkitchen",
               title: "Small kitchen storage that actually works",
               author: "pinterest.com", platform: .pinterest, kind: .pin,
               category: "cleaning", sub: "Storage", tags: ["kitchen", "storage"],
               image: Cover.explainer),
        Sample(url: "https://www.instagram.com/reel/C9morning",
               title: "My 10-minute calm morning routine", author: "@calm.mornings",
               platform: .instagram, kind: .reel, category: "wellness",
               sub: "Morning routines", tags: ["morning", "habits"], duration: 39,
               image: Cover.mobility),
        Sample(url: "https://x.com/indexinvestor/status/44120",
               title: "ETFs vs index funds", author: "@indexinvestor",
               platform: .x, kind: .thread, category: "investing", sub: "ETFs & index funds",
               tags: ["etf", "index fund"],
               text: "People use these interchangeably and then get surprised by the tax treatment. The difference that actually matters is how they trade, not what they hold."),
        Sample(url: "https://www.youtube.com/watch?v=unsolvedcase",
               title: "Unsolved: the detective who never closed the case",
               author: "@casefilesdaily", platform: .youtube, kind: .video,
               category: "truecrime", sub: "Cold cases", tags: ["unsolved", "detective"],
               duration: 1432,
               image: Cover.talkingHead),
        Sample(url: "https://www.tiktok.com/@booktok.sam/video/5512",
               title: "This novel destroyed me in the best way",
               author: "@booktok.sam", platform: .tiktok, kind: .clip,
               category: "books", sub: "Recommendations", tags: ["fiction", "booktok"],
               duration: 62,
               image: Cover.postScreenshot),
        Sample(url: "https://www.youtube.com/shorts/promptagents",
               title: "Prompt patterns for agents that actually finish the task",
               author: "@aibuilds", platform: .shorts, kind: .short,
               category: "ai", sub: "Agents", tags: ["prompting", "agents"],
               duration: 58,
               note: "Try the checklist pattern on the scraper job.", opens: 5, openedDaysAgo: 3,
               image: Cover.explainer),
        Sample(url: "https://www.instagram.com/reel/C10toddler",
               title: "The tantrum reset that finally worked for us",
               author: "@gentle.parent", platform: .instagram, kind: .reel,
               category: "parenting", sub: "Discipline", tags: ["toddlers", "tantrum"],
               duration: 44,
               image: Cover.talkingHead),
        Sample(url: "https://www.smittenkitchen.com/2026/06/one-pan-orzo",
               title: "One-pan lemon orzo that reheats properly",
               author: "smittenkitchen.com", platform: .web, kind: .article,
               category: "recipes", sub: "One-pan", tags: ["orzo", "weeknight"],
               opens: 2, openedDaysAgo: 6,
               image: Cover.groceries),
        Sample(url: "https://www.tiktok.com/@weldlife/video/3310",
               title: "Reading a weld: what good penetration actually looks like",
               author: "@weldlife", platform: .tiktok, kind: .clip,
               category: "trades", sub: "Welding", tags: ["welding", "technique"],
               duration: 96,
               image: Cover.physiology),
        Sample(url: "https://www.youtube.com/watch?v=gardenbeds",
               title: "No-dig beds, two years on", author: "@plotandplant",
               platform: .youtube, kind: .video, category: "garden", sub: "Vegetables",
               tags: ["no-dig", "beds"], duration: 954,
               image: Cover.mobility),

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
               duration: 1104, days: 26,
               image: Cover.physiology),
        Sample(url: "https://www.instagram.com/reel/C11cadence",
               title: "Cadence drills that stop the heel strike",
               author: "@run.physio", platform: .instagram, kind: .reel,
               category: "fitness", sub: "Running", tags: ["cadence", "running"],
               duration: 51, days: 27,
               image: Cover.talkingHead),
        Sample(url: "https://www.tiktok.com/@physio.jane/video/7420",
               title: "Calf raises: the boring fix for shin pain",
               author: "@physio.jane", platform: .tiktok, kind: .clip,
               category: "fitness", sub: "Strength", tags: ["calves", "running"],
               duration: 143, days: 28,
               image: Cover.explainer),
        Sample(url: "https://www.youtube.com/shorts/hillreps",
               title: "Hill reps in 20 minutes", author: "@quickmiles",
               platform: .shorts, kind: .short, category: "fitness", sub: "Running",
               tags: ["hills", "intervals"], duration: 47, days: 29,
               image: Cover.footPain),
        Sample(url: "https://www.instagram.com/reel/C12fuel",
               title: "What to eat before a long run", author: "@macrofriendly",
               platform: .instagram, kind: .reel, category: "fitness", sub: "Running",
               tags: ["fuelling", "running"], duration: 62, days: 30,
               image: Cover.groceries),
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
               duration: 892, days: 35,
               image: Cover.postScreenshot),
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
               duration: 118, days: 42,
               image: Cover.explainer),
        Sample(url: "https://www.coindesk.com/2026/07/the-quiet-quarter",
               title: "The quiet quarter", author: "coindesk.com",
               platform: .web, kind: .article, category: "crypto", sub: "Markets",
               tags: ["cycle", "quiet"], days: 45,
               image: Cover.postScreenshot),
        Sample(url: "https://www.youtube.com/watch?v=btcstorage",
               title: "Cold storage, six months on", author: "@keysandcoins",
               platform: .youtube, kind: .video, category: "crypto", sub: "Wallets",
               tags: ["cold storage"], duration: 640, days: 48,
               image: Cover.physiology),
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
               duration: 733, days: 44,
               image: Cover.talkingHead),
        Sample(url: "https://www.morningstar.com/2026/06/bonds-again",
               title: "Bonds, again", author: "morningstar.com",
               platform: .web, kind: .article, category: "investing", sub: "Bonds",
               tags: ["bonds", "duration"], days: 50,
               image: Cover.postScreenshot),
        Sample(url: "https://www.youtube.com/watch?v=localfirst",
               title: "Local-first apps and the sync problem",
               author: "@buildlogs", platform: .youtube, kind: .video,
               category: "tech", sub: "Software", tags: ["local-first", "sync"],
               duration: 1520, days: 52,
               image: Cover.explainer),
        Sample(url: "https://www.tiktok.com/@shipfast/video/2211",
               title: "One keyboard shortcut per day", author: "@shipfast",
               platform: .tiktok, kind: .clip, category: "tech", sub: "Productivity",
               tags: ["shortcuts"], duration: 39, days: 55,
               image: Cover.mobility),
    ]
}
#endif
