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

        for (offset, sample) in samples.enumerated() {
            guard let url = URL(string: sample.url) else { continue }
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
                savedAt: Calendar.current.date(byAdding: .day, value: -offset, to: .now) ?? .now
            )
            context.insert(bookmark)
        }
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
    }

    private static let samples: [Sample] = [
        Sample(url: "https://www.tiktok.com/@physio.jane/video/7390",
               title: "5-minute hip mobility flow you can do at your desk",
               author: "@physio.jane", platform: .tiktok, kind: .clip,
               category: "fitness", sub: "Mobility", tags: ["hips", "desk", "daily"],
               duration: 312, note: "Do this before long runs."),
        Sample(url: "https://x.com/hubermanclips/status/180233",
               title: "Magnesium glycinate thread", author: "@hubermanclips",
               platform: .x, kind: .thread, category: "health", sub: "Sleep",
               tags: ["magnesium", "sleep"],
               text: "Magnesium glycinate is the most over-recommended and least understood sleep supplement. A short thread on what the actual evidence says, and who it genuinely helps:"),
        Sample(url: "https://www.youtube.com/watch?v=protein30",
               title: "I tried the 30g protein breakfast for 30 days — here is what happened",
               author: "@macrofriendly", platform: .youtube, kind: .video,
               category: "nutrition", sub: "High-protein", tags: ["breakfast", "protein"],
               duration: 768),
        Sample(url: "https://www.instagram.com/reel/C8xhamstring",
               title: "4 stretches for tight hamstrings after long runs",
               author: "@run.physio", platform: .instagram, kind: .reel,
               category: "fitness", sub: "Stretching", tags: ["hamstrings", "running"],
               duration: 48),
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
               note: "Try the checklist pattern on the scraper job."),
        Sample(url: "https://www.instagram.com/reel/C10toddler",
               title: "The tantrum reset that finally worked for us",
               author: "@gentle.parent", platform: .instagram, kind: .reel,
               category: "parenting", sub: "Discipline", tags: ["toddlers", "tantrum"],
               duration: 44),
        Sample(url: "https://www.smittenkitchen.com/2026/06/one-pan-orzo",
               title: "One-pan lemon orzo that reheats properly",
               author: "smittenkitchen.com", platform: .web, kind: .article,
               category: "recipes", sub: "One-pan", tags: ["orzo", "weeknight"]),
        Sample(url: "https://www.tiktok.com/@weldlife/video/3310",
               title: "Reading a weld: what good penetration actually looks like",
               author: "@weldlife", platform: .tiktok, kind: .clip,
               category: "trades", sub: "Welding", tags: ["welding", "technique"],
               duration: 96),
        Sample(url: "https://www.youtube.com/watch?v=gardenbeds",
               title: "No-dig beds, two years on", author: "@plotandplant",
               platform: .youtube, kind: .video, category: "garden", sub: "Vegetables",
               tags: ["no-dig", "beds"], duration: 954),
    ]
}
#endif
