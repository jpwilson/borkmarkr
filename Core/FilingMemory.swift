import Foundation

// MARK: - History

/// One filing you made, reduced to what Quick File's ranking reads.
///
/// There is no table for this. Every bookmark already carries its topic,
/// subtopic, author, URL, who filed it (`filingSource`) and when it last
/// changed, and all of that syncs. A separate history would be a second copy
/// with its own conflict rules. So history is derived on demand from the saves
/// themselves: the app reads SwiftData, the web reads its rows
/// (`FilingSuggest.historyFromRows` in `docs/filing-suggest.js`).
struct FilingHistoryItem: Codable, Sendable {
    var categoryID: String
    var subcategory: String?
    /// A `FilingKeys.creator` key, never a raw author string.
    var creator: String?
    /// A `FilingKeys.domain` key. Web links only.
    var domain: String?
    var at: Date
}

extension FilingHistoryItem {
    /// From a save's own fields, with both keys derived exactly as the web's
    /// `historyFromRows` derives them. Only `"user"` filings belong in history;
    /// that check stays with the caller, which is the one holding the field.
    init(categoryID: String, subcategory: String?, author: String?, url: URL?, at: Date) {
        self.init(categoryID: categoryID,
                  subcategory: subcategory,
                  creator: url.flatMap { FilingKeys.creator(author: author, url: $0) },
                  domain: url.flatMap { FilingKeys.domain(url: $0) },
                  at: at)
    }
}

// MARK: - Memory

/// Your filing history, folded down to the three questions the dial asks.
///
/// - **creators**: where did this creator's posts go?
/// - **domains**: where did this website's pages go? Web links only.
/// - **habits**: which topic › subtopic pairs do you file into, and how lately?
///
/// Only your own filings (`filingSource == "user"`) from the last 365 days
/// count. A guess the app made is not evidence of what you want. The caps
/// (400 creators × 3 picks, 200 domains × 3 picks, 24 habits) keep the
/// snapshot the Share Extension reads small.
///
/// Timestamps are whole seconds since 1970, every count is an integer and
/// every ordering is total, so this file and `docs/filing-suggest.js` build
/// the same memory from the same rows. `Scripts/check_filing_parity.mjs`
/// holds them to it.
struct FilingMemory: Codable, Sendable, Equatable {

    /// How many times one creator's (or one site's) posts went to one place,
    /// and when last.
    struct Pick: Codable, Sendable, Equatable {
        var categoryID: String
        var subcategory: String?
        var count: Int
        /// Seconds since 1970.
        var last: Int
    }

    /// A topic › subtopic pair you file into, with the times of your most
    /// recent filings there: newest first, at most six, which is enough for
    /// the habit score (it stops at 6) to come out exact.
    struct Habit: Codable, Sendable, Equatable {
        var categoryID: String
        var subcategory: String?
        var recent: [Int]
    }

    private(set) var creators: [String: [Pick]]
    private(set) var domains: [String: [Pick]]
    private(set) var habits: [Habit]

    enum Limit {
        static let creators = 400
        static let domains = 200
        static let picksPerKey = 3
        static let habits = 24
        static let recentPerHabit = 6
        static let horizonDays = 365
    }

    /// How lately: each filing is worth 3 in its first week, 2 in its first
    /// month and 1 in its first year.
    enum Recency {
        static let week = 3
        static let month = 2
        static let year = 1
    }

    static let empty = FilingMemory(creators: [:], domains: [:], habits: [])

    /// Memory from scratch. Exactly `empty.adding(items, now:)`.
    static func build(from items: [FilingHistoryItem], now: Date) -> FilingMemory {
        empty.adding(items, now: now)
    }

    /// Folds in filings the store hasn't seen yet (drafts still in the Share
    /// Extension's inbox, picks made a moment ago in triage) so the next
    /// suggestion already knows about them. Returns a new memory, pruned to
    /// the caps as of `now`.
    func adding(_ items: [FilingHistoryItem], now: Date) -> FilingMemory {
        let nowSeconds = FilingParity.seconds(now)
        let horizon = nowSeconds - Limit.horizonDays * FilingParity.day
        var creators = self.creators
        var domains = self.domains
        var habits: [String: Habit] = [:]
        for habit in self.habits { habits[Self.pairKey(habit.categoryID, habit.subcategory)] = habit }

        for item in items {
            guard !item.categoryID.isEmpty else { continue }
            let sub = item.subcategory.flatMap { $0.isEmpty ? nil : $0 }
            let at = FilingParity.seconds(item.at)
            guard at >= horizon else { continue }
            if let key = item.creator, !key.isEmpty {
                creators[key] = Self.counting(creators[key] ?? [], item.categoryID, sub, at)
            }
            if let key = item.domain, !key.isEmpty {
                domains[key] = Self.counting(domains[key] ?? [], item.categoryID, sub, at)
            }
            let pair = Self.pairKey(item.categoryID, sub)
            var habit = habits[pair] ?? Habit(categoryID: item.categoryID, subcategory: sub, recent: [])
            habit.recent = Array((habit.recent + [at]).sorted(by: >).prefix(Limit.recentPerHabit))
            habits[pair] = habit
        }

        return FilingMemory(
            creators: Self.pruned(creators, keep: Limit.creators, horizon: horizon),
            domains: Self.pruned(domains, keep: Limit.domains, horizon: horizon),
            habits: Self.pruned(Array(habits.values), now: nowSeconds, horizon: horizon)
        )
    }

    /// The recency score of a set of filing times: 3, 2 or 1 each by age,
    /// nothing past a year. Uncapped; callers cap it.
    static func recency(of times: [Int], now: Int) -> Int {
        var total = 0
        for at in times {
            let age = now - at
            if age <= 7 * FilingParity.day { total += Recency.week }
            else if age <= 30 * FilingParity.day { total += Recency.month }
            else if age <= Limit.horizonDays * FilingParity.day { total += Recency.year }
        }
        return total
    }

    // MARK: Folding and pruning

    private static func pairKey(_ categoryID: String, _ subcategory: String?) -> String {
        categoryID + "\u{1F}" + (subcategory ?? "")
    }

    private static func counting(_ picks: [Pick], _ categoryID: String, _ subcategory: String?, _ at: Int) -> [Pick] {
        var picks = picks
        if let index = picks.firstIndex(where: { $0.categoryID == categoryID && $0.subcategory == subcategory }) {
            picks[index].count += 1
            picks[index].last = max(picks[index].last, at)
        } else {
            picks.append(Pick(categoryID: categoryID, subcategory: subcategory, count: 1, last: at))
        }
        return picks
    }

    /// Most picks first, then the most recent, then A–Z: a total order.
    private static func comesFirst(_ a: Pick, _ b: Pick) -> Bool {
        if a.count != b.count { return a.count > b.count }
        if a.last != b.last { return a.last > b.last }
        if a.categoryID != b.categoryID { return FilingParity.less(a.categoryID, b.categoryID) }
        return FilingParity.less(a.subcategory, b.subcategory)
    }

    /// Each key keeps its three strongest picks from the last year; past the
    /// cap, the keys with the most picks (then the most recent) stay.
    private static func pruned(_ table: [String: [Pick]], keep: Int, horizon: Int) -> [String: [Pick]] {
        var kept: [(key: String, picks: [Pick], total: Int, last: Int)] = []
        for (key, picks) in table {
            let fresh = Array(picks.filter { $0.last >= horizon }.sorted(by: comesFirst).prefix(Limit.picksPerKey))
            guard let newest = fresh.map(\.last).max() else { continue }
            kept.append((key, fresh, fresh.reduce(0) { $0 + $1.count }, newest))
        }
        if kept.count > keep {
            kept.sort { a, b in
                if a.total != b.total { return a.total > b.total }
                if a.last != b.last { return a.last > b.last }
                return FilingParity.less(a.key, b.key)
            }
            kept = Array(kept.prefix(keep))
        }
        var out: [String: [Pick]] = [:]
        for entry in kept { out[entry.key] = entry.picks }
        return out
    }

    /// Habits from the last year, strongest recency first, then the most
    /// recent, then A–Z.
    private static func pruned(_ habits: [Habit], now: Int, horizon: Int) -> [Habit] {
        let fresh: [Habit] = habits.compactMap { habit in
            let recent = habit.recent.filter { $0 >= horizon }
            guard !recent.isEmpty else { return nil }
            return Habit(categoryID: habit.categoryID, subcategory: habit.subcategory,
                         recent: Array(recent.prefix(Limit.recentPerHabit)))
        }
        let ranked = fresh.sorted { a, b in
            let wa = recency(of: a.recent, now: now), wb = recency(of: b.recent, now: now)
            if wa != wb { return wa > wb }
            if a.recent[0] != b.recent[0] { return a.recent[0] > b.recent[0] }
            if a.categoryID != b.categoryID { return FilingParity.less(a.categoryID, b.categoryID) }
            return FilingParity.less(a.subcategory, b.subcategory)
        }
        return Array(ranked.prefix(Limit.habits))
    }
}

// MARK: - Keys

/// The two things a past filing is remembered by: who made the post, and which
/// website it came from.
///
/// **Creator.** The handle in the URL when the URL names one (`/@name/video/…`,
/// `x.com/name/status/…`, `instagram.com/name/reel/…`), otherwise the stored
/// author unless it is a placeholder (empty, a platform name, the link's own
/// host). Then decomposed, lowercased and cut down to `a–z 0–9`, so
/// `@Kayla.Walks` on TikTok, `kayla_walks` on X and a "Kayla Walks" YouTube
/// channel are one creator, and the key is plain ASCII on both platforms.
/// Under two characters is no key. The URL rules port `Platform.handle` with an
/// ASCII-only character set, which the JS can match exactly.
///
/// **Web links have no creator.** Their author is usually the site itself,
/// which `domain` already counts; counting it twice would let one website
/// outvote what the page says.
///
/// **Domain.** The host without `www.`, for web links only. A TikTok's host
/// says nothing about its topic.
enum FilingKeys {

    static func creator(author: String?, url: URL) -> String? {
        resolve(author: author, url: url)?.key
    }

    /// How the creator reads in a reason line: `@kayla.walks` for a handle in
    /// the URL, otherwise the author exactly as stored ("@kaylawalks" from
    /// TikTok, "Squat Mechanics" from YouTube). Nil whenever `creator` is nil.
    static func creatorLabel(author: String?, url: URL) -> String? {
        resolve(author: author, url: url)?.label
    }

    static func domain(url: URL) -> String? {
        guard Platform.detect(from: url) == .web, let raw = url.host?.lowercased() else { return nil }
        let host = raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
        return host.isEmpty ? nil : host
    }

    private static func resolve(author: String?, url: URL) -> (key: String, label: String)? {
        let platform = Platform.detect(from: url)
        if let handle = handle(in: url, platform: platform), let key = key(handle) {
            return (key, "@" + handle)
        }
        guard platform != .web, let author, !isPlaceholder(author, url: url) else { return nil }
        // The label is the author as stored: TikTok and X store "@handle",
        // YouTube a channel name. Adding an "@" here would invent a handle.
        let name = FilingParity.trim(author)
        guard let key = key(name) else { return nil }
        return (key, name)
    }

    /// `Platform.handle` without the "@", restricted to ASCII.
    private static func handle(in url: URL, platform: Platform) -> String? {
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first else { return nil }

        func clean(_ raw: String) -> String? {
            let name = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
            guard name.unicodeScalars.count <= 40, isHandle(name) else { return nil }
            return name
        }

        switch platform {
        case .tiktok, .threads, .youtube, .shorts:
            return first.hasPrefix("@") ? clean(first) : nil
        case .x:
            let reserved: Set<String> = ["i", "home", "search", "hashtag", "intent", "share", "explore", "messages", "notifications", "settings"]
            guard segments.count >= 3, segments[1] == "status", !reserved.contains(first.lowercased()) else { return nil }
            return clean(first)
        case .instagram:
            if first == "stories", segments.count >= 2 { return clean(segments[1]) }
            let postPaths: Set<String> = ["reel", "reels", "p", "tv"]
            guard segments.count >= 3, postPaths.contains(segments[1]), !postPaths.contains(first) else { return nil }
            return clean(first)
        case .pinterest, .grok, .web:
            return nil
        }
    }

    /// Non-empty and nothing but `A–Z a–z 0–9 . _ -`.
    private static func isHandle(_ name: String) -> Bool {
        !name.unicodeScalars.isEmpty && name.unicodeScalars.allSatisfy { s in
            ("a"..."z").contains(s) || ("A"..."Z").contains(s) || ("0"..."9").contains(s)
                || s == "." || s == "_" || s == "-"
        }
    }

    private static func key(_ raw: String) -> String? {
        var kept = String.UnicodeScalarView()
        for s in raw.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars
        where ("a"..."z").contains(s) || ("0"..."9").contains(s) {
            kept.append(s)
        }
        return kept.count >= 2 ? String(kept) : nil
    }

    /// Mirrors `Bookmark.isPlaceholderAuthor` for social links (Bookmark is
    /// SwiftData and can't join a swiftc build).
    private static func isPlaceholder(_ author: String, url: URL) -> Bool {
        let raw = FilingParity.trim(author)
        guard !raw.isEmpty else { return true }
        if Platform.isSiteName(raw) { return true }
        func bare(_ host: String) -> String {
            let lower = host.lowercased()
            return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
        }
        if let host = url.host, bare(raw) == bare(host) { return true }
        // "instagram.com" on a link from "m.instagram.com": any social
        // platform's host is a site, not a person.
        guard raw.contains("."), !raw.contains(" "), !raw.hasPrefix("@"),
              let asURL = URL(string: "https://\(bare(raw))/") else { return false }
        return Platform.detect(from: asURL) != .web
    }
}

// MARK: - Snapshot for the Share Extension

/// A custom topic, as much of it as the Share Extension needs to draw.
struct SnapshotTopic: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var hue: Double

    var asTopic: Topic { Topic(id: id, name: name, hue: hue, subs: []) }
}

/// What the app leaves in the App Group so the Share Extension can rank
/// without opening SwiftData: the memory, plus your custom topics and
/// subtopics so it can draw and offer them. Written by the app, read by the
/// extension, rebuilt whenever the app likes; losing it costs one share's
/// worth of personal suggestions, nothing more.
struct FilingSnapshot: Codable, Sendable {
    var version = 1
    var memory: FilingMemory
    var customTopics: [SnapshotTopic]
    /// Custom subtopic names by topic id.
    var customSubs: [String: [String]]

    /// `<AppGroup>/quickfile/snapshot-v1.json`. The group id is spelled out
    /// rather than read from `Store.appGroupID` because Store imports
    /// SwiftData, and this file has to build with plain swiftc.
    static var sharedURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.jpwilson.borkmarkr")?
            .appendingPathComponent("quickfile", isDirectory: true)
            .appendingPathComponent("snapshot-v1.json")
    }

    static func loadShared() -> FilingSnapshot? {
        guard let url = sharedURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(FilingSnapshot.self, from: data),
              snapshot.version == 1
        else { return nil }
        return snapshot
    }

    func writeShared() throws {
        guard let url = Self.sharedURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

// MARK: - Parity helpers

/// The few text and time operations Quick File's Swift and JS must perform
/// identically. Each is defined on Unicode scalars (JS code points) so neither
/// language's own idea of a character, a space or an ordering can creep in.
enum FilingParity {
    static let day = 86_400

    /// Whole seconds since 1970, rounded down.
    static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// Code-point order.
    static func less(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
    }

    /// Code-point order with nil first.
    static func less(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return less(a, b)
        case (nil, _?): return true
        default: return false
        }
    }

    /// Trims the union of what Swift's `.whitespacesAndNewlines` and JS's
    /// `trim()` call space, so both trim the same.
    static func trim(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var start = 0, end = scalars.count
        while start < end, isSpace(scalars[start]) { start += 1 }
        while end > start, isSpace(scalars[end - 1]) { end -= 1 }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    static func isSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }
}
