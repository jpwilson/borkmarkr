import Foundation

/// How Browse orders what it is listing — topics, sources and side quests.
///
/// One enum for all three segments because it is the same three questions on
/// each of them: *which has the most in it*, *which did I touch last*, *where
/// is it in the alphabet*. The web app ships the identical three under the
/// identical labels; two lists that answer the same question must never call
/// it two different things, so `title` is the shared contract and changing a
/// string here means changing it there too.
///
/// Pure Foundation, pure functions. The ordering is the part worth testing and
/// none of it needs SwiftData, SwiftUI or a running app —
/// `Scripts/test_browse_sort.swift` exercises it directly.
enum BrowseSort: String, CaseIterable, Sendable {
    case borks, recent, alpha

    /// Chip label. Identical on iOS and on the web.
    var title: String {
        switch self {
        case .borks: "Most borks"
        case .recent: "Most recent"
        case .alpha: "A–Z"
        }
    }

    /// What every segment starts as: the order Browse has always used.
    static let fallback = BrowseSort.borks

    /// Unknown persisted values fall back rather than crashing — same guard
    /// `AccentRamp.named` uses, for the same reason.
    static func named(_ raw: String?) -> BrowseSort {
        guard let raw, let found = BrowseSort(rawValue: raw) else { return fallback }
        return found
    }

    /// Persisted per segment. "What am I looking for" is a different question
    /// on Topics than on Sources, and picking A–Z once to find a platform
    /// should not permanently reorder the topic grid.
    enum Key {
        static let topics = "browseSort.topics"
        static let sources = "browseSort.sources"
        static let journeys = "browseSort.journeys"
    }
}

/// One row of any of the three Browse lists, reduced to the four things an
/// ordering can depend on.
///
/// A struct rather than a protocol so the sort can be exercised without a
/// `Topic`, a `Platform`, a `Mission` or a store — and so the three call sites
/// physically cannot diverge on what "most recent" means.
struct BrowseSortEntry: Equatable, Sendable {
    let id: String
    let name: String
    let count: Int
    /// Newest `savedAt` among the borks inside. `nil` when there are none — a
    /// topic you just made, a source you have never saved from — and those
    /// sort last under `.recent` rather than pretending to be ancient.
    let recent: Date?
    /// Honoured by `.borks` only: an onboarding interest floats to the top of
    /// the grid, which is what Browse has always done. An A–Z that isn't
    /// alphabetical is not A–Z, so the other two ignore it.
    var pinned: Bool = false
    /// The list's own canonical order — `Taxonomy` order, `Platform.ordered`,
    /// newest quest first. Used as the final tiebreak so equal rows keep a
    /// stable, meaningful order: `Array.sorted` is not a stable sort, and
    /// without this a grid of equal-count topics reshuffles on every redraw.
    var rank: Int = 0
}

extension BrowseSort {
    func order(_ entries: [BrowseSortEntry]) -> [BrowseSortEntry] {
        entries.sorted(by: precedes)
    }

    /// Ids in order — the shape every call site wants, since each of them
    /// holds a richer object it needs to map back onto.
    func orderedIDs(_ entries: [BrowseSortEntry]) -> [String] {
        order(entries).map(\.id)
    }

    /// A strict weak ordering: every branch that cannot decide falls through
    /// to `rank`, so no two distinct rows ever compare equal in both
    /// directions.
    func precedes(_ a: BrowseSortEntry, _ b: BrowseSortEntry) -> Bool {
        switch self {
        case .borks:
            if a.pinned != b.pinned { return a.pinned }
            if a.count != b.count { return a.count > b.count }
        case .recent:
            if a.recent != b.recent {
                guard let left = a.recent else { return false }
                guard let right = b.recent else { return true }
                return left > right
            }
        case .alpha:
            // Locale-aware, and digit-aware: "Zone 2" sorts before "Zone 10",
            // and an accented name lands where a reader expects it rather
            // than after Z. Custom topics go through the same comparison as
            // the built-ins, so they mix into the list instead of clumping.
            let comparison = a.name.localizedStandardCompare(b.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }
        return a.rank < b.rank
    }
}
