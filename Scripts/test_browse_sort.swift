import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/browse-sort-tests Core/BrowseSort.swift Scripts/test_browse_sort.swift`
///
/// Browse's three segments all order through `BrowseSort`, and the same three
/// options ship on the web. What is checked here is what the user would
/// notice: that the default is the order Browse has always had, that A–Z is
/// actually alphabetical (custom topics included), that "most recent" puts an
/// empty topic last rather than first, and that nothing reshuffles when the
/// numbers tie.

@main
enum BrowseSortTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        func day(_ offset: Int) -> Date {
            Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(Double(offset) * 86_400)
        }

        // ── Labels are a cross-platform contract ──────────────────────────
        expect(BrowseSort.borks.title == "Most borks", "the count option is Most borks")
        expect(BrowseSort.recent.title == "Most recent", "the recency option is Most recent")
        expect(BrowseSort.alpha.title == "A–Z", "the alphabetical option is A–Z, with an en dash")
        expect(BrowseSort.allCases.count == 3, "three options, no more")
        expect(BrowseSort.fallback == .borks, "the default is Most borks — what Browse did before")
        expect(BrowseSort.named("alpha") == .alpha, "a persisted choice comes back")
        expect(BrowseSort.named("nonsense") == .borks, "a junk default falls back")
        expect(BrowseSort.named(nil) == .borks, "nothing persisted falls back")
        expect(
            Set([BrowseSort.Key.topics, BrowseSort.Key.sources, BrowseSort.Key.journeys]).count == 3,
            "each segment persists under its own key"
        )

        // ── The topic grid ────────────────────────────────────────────────
        let topics = [
            BrowseSortEntry(id: "fitness", name: "Fitness", count: 8, recent: day(-1), rank: 0),
            BrowseSortEntry(id: "crypto", name: "Crypto", count: 12, recent: day(-40), rank: 1),
            BrowseSortEntry(id: "art", name: "Art & design", count: 3, recent: day(-2), rank: 2),
            // A topic you made and have not filed anything into yet.
            BrowseSortEntry(id: "custom.bouldering", name: "Bouldering", count: 0, recent: nil, rank: 3),
        ]

        expect(
            BrowseSort.borks.orderedIDs(topics) == ["crypto", "fitness", "art", "custom.bouldering"],
            "Most borks is count descending"
        )
        expect(
            BrowseSort.recent.orderedIDs(topics) == ["fitness", "art", "crypto", "custom.bouldering"],
            "Most recent is newest bork first, and an empty topic is last"
        )
        expect(
            BrowseSort.alpha.orderedIDs(topics) == ["art", "custom.bouldering", "crypto", "fitness"],
            "A–Z mixes a custom topic in among the built-ins"
        )

        // ── Interests float, but only where floating is honest ────────────
        let pinned = [
            BrowseSortEntry(id: "garden", name: "Garden", count: 1, recent: day(-9), pinned: true, rank: 5),
            BrowseSortEntry(id: "crypto", name: "Crypto", count: 12, recent: day(-40), rank: 1),
        ]
        expect(
            BrowseSort.borks.orderedIDs(pinned) == ["garden", "crypto"],
            "an onboarding interest still floats to the top of Most borks"
        )
        expect(
            BrowseSort.alpha.orderedIDs(pinned) == ["crypto", "garden"],
            "A–Z ignores interests — an A–Z that isn't alphabetical is not A–Z"
        )
        expect(
            BrowseSort.recent.orderedIDs(pinned) == ["garden", "crypto"],
            "Most recent ignores interests and answers only about dates"
        )

        // ── Ties keep the list's own order, in both directions ────────────
        let tied = [
            BrowseSortEntry(id: "b", name: "Beta", count: 4, recent: day(-3), rank: 1),
            BrowseSortEntry(id: "a", name: "Alpha", count: 4, recent: day(-3), rank: 0),
            BrowseSortEntry(id: "c", name: "Gamma", count: 4, recent: day(-3), rank: 2),
        ]
        for option in BrowseSort.allCases {
            let forward = option.orderedIDs(tied)
            let backward = option.orderedIDs(tied.reversed())
            expect(forward == backward, "\(option.title) does not depend on input order")
        }
        expect(BrowseSort.borks.orderedIDs(tied) == ["a", "b", "c"], "equal counts fall back to canonical order")
        expect(
            BrowseSort.recent.orderedIDs([
                BrowseSortEntry(id: "x", name: "X", count: 0, recent: nil, rank: 1),
                BrowseSortEntry(id: "y", name: "Y", count: 0, recent: nil, rank: 0),
            ]) == ["y", "x"],
            "two never-used entries keep canonical order rather than shuffling"
        )

        // ── Sources: every platform is listed, empty ones sink ────────────
        let sources = [
            BrowseSortEntry(id: "x", name: "X", count: 4, recent: day(-6), rank: 0),
            BrowseSortEntry(id: "instagram", name: "Instagram", count: 9, recent: day(-1), rank: 1),
            BrowseSortEntry(id: "grok", name: "Grok", count: 0, recent: nil, rank: 7),
            BrowseSortEntry(id: "web", name: "Web", count: 2, recent: day(-30), rank: 8),
        ]
        expect(
            BrowseSort.borks.orderedIDs(sources) == ["instagram", "x", "web", "grok"],
            "a source you have never saved from sinks to the bottom of Most borks"
        )
        expect(
            BrowseSort.alpha.orderedIDs(sources) == ["grok", "instagram", "web", "x"],
            "A–Z on sources is by display name"
        )
        expect(
            BrowseSort.borks.order(sources).count == sources.count,
            "sorting never drops a row"
        )

        // ── A–Z is locale-aware, not byte order ───────────────────────────
        let awkward = [
            BrowseSortEntry(id: "z10", name: "Zone 10", count: 0, recent: nil, rank: 0),
            BrowseSortEntry(id: "z2", name: "Zone 2", count: 0, recent: nil, rank: 1),
            BrowseSortEntry(id: "eclair", name: "Éclairs", count: 0, recent: nil, rank: 2),
            BrowseSortEntry(id: "east", name: "eastern europe", count: 0, recent: nil, rank: 3),
        ]
        let alphabetical = BrowseSort.alpha.orderedIDs(awkward)
        expect(
            alphabetical.firstIndex(of: "z2")! < alphabetical.firstIndex(of: "z10")!,
            "Zone 2 sorts before Zone 10, not after it"
        )
        expect(
            alphabetical.firstIndex(of: "east")! < alphabetical.firstIndex(of: "eclair")!
                && alphabetical.firstIndex(of: "eclair")! < alphabetical.firstIndex(of: "z2")!,
            "an accent and a lowercase initial land where a reader expects them"
        )

        // ── Degenerate input ──────────────────────────────────────────────
        for option in BrowseSort.allCases {
            expect(option.order([]).isEmpty, "\(option.title) of nothing is nothing")
        }

        print(failures == 0 ? "\nAll browse sort checks passed."
                            : "\n\(failures) browse sort check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
