import Foundation

/// One bork, reduced to what "what should I look at again?" needs.
///
/// Plain values rather than the SwiftData model on purpose — see `Revisit`.
struct RevisitBork: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var platform: Platform
    var topicID: String?
    var topicName: String?
    var savedAt: Date
    var openCount: Int
    var lastOpenedAt: Date?
}

/// A side quest with steps left on it.
struct RevisitQuest: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var remaining: Int
}

/// What to look at again.
///
/// The library answers "what have I got". Browse answers "where is it". Neither
/// answers the question the product is actually for: *everything interesting
/// you scroll past, captured, organised, **revisited**, shared*. Saving is
/// solved; revisiting was, until now, entirely on the user to remember to do.
///
/// **Why this is a pure type and not a view.** Every section here is a
/// perfectly good paragraph of a weekly email — "you saved 14 things, 11 of
/// them you never opened, a month ago you were reading about X". Computing it
/// inside a SwiftUI view would mean writing it all again the day the digest
/// ships. So the screen renders a value, and the value can be built anywhere:
/// from SwiftData on the phone today, from a Postgres row server-side later.
/// `RevisitBork` deliberately carries the topic *name*, not just its id, so the
/// computation never needs the taxonomy either.
///
/// Sections are ordered by how likely they are to send someone back into their
/// library, not by how clever they are. "Saved, never opened" is the one that
/// earns the tab.
enum Revisit {

    /// Below this the screen has nothing honest to say, and says so.
    static let thinFloor = 10

    /// A bork has to be a week old before "never opened" means anything —
    /// saving something and not opening it that afternoon is normal.
    static let neverOpenedAge = 7
    static let neverOpenedCap = 12

    /// "A month ago" is a window, not a day: an exact 30-day-ago lookup is
    /// empty most days, which makes the section feel broken rather than quiet.
    static let monthAgoRange = 28...35
    static let monthAgoCap = 3

    static let comingBackCap = 5

    /// "What's shifting" needs enough data to not be noise.
    static let shiftFloor = 20
    static let shiftWindow = 30
    static let shiftCap = 3
    /// Share changes smaller than this are rounding, not a trend.
    static let shiftThreshold = 0.03

    // MARK: - Value types

    struct PlatformCount: Hashable, Sendable {
        var name: String
        var count: Int
    }

    struct TopicGrowth: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var count: Int
        var previous: Int
        var gain: Int { count - previous }
    }

    struct ThisWeek: Hashable, Sendable {
        var count: Int
        var platforms: [PlatformCount]
        var rising: [TopicGrowth]
        /// "14 borks · 6 Instagram · 5 X · 3 YouTube"
        var headline: String
    }

    struct NeverOpened: Hashable, Sendable {
        /// **All** of them, newest first. The section shows `preview` and
        /// offers the rest behind "and N more", but the model holds the whole
        /// pile: the list screen needs it, and a digest would want the count
        /// rather than "twelve or more".
        var items: [RevisitBork]
        /// "11 things you saved and never looked at."
        var headline: String

        var total: Int { items.count }
        var preview: [RevisitBork] { Array(items.prefix(Revisit.neverOpenedCap)) }
        var overflow: Int { max(0, items.count - Revisit.neverOpenedCap) }
    }

    struct Shift: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var share: Double
        var previousShare: Double
        var isUp: Bool
        var magnitude: Double { abs(share - previousShare) }
    }

    struct Model: Hashable, Sendable {
        var total: Int
        /// Under `thinFloor` borks: one warm card instead of six thin sections.
        var isThin: Bool
        var thisWeek: ThisWeek?
        var comingBack: [RevisitBork]
        var neverOpened: NeverOpened?
        var monthAgo: [RevisitBork]
        var quests: [RevisitQuest]
        var shifts: [Shift]
        /// "More Fitness, less Crypto"
        var shiftSentence: String?

        /// True when every section came back empty — a library that is big
        /// enough to have sections but has nothing due.
        var hasNothing: Bool {
            thisWeek == nil && comingBack.isEmpty && neverOpened == nil
                && monthAgo.isEmpty && quests.isEmpty && shifts.isEmpty
        }

        static let empty = Model(
            total: 0, isThin: true, thisWeek: nil, comingBack: [],
            neverOpened: nil, monthAgo: [], quests: [], shifts: [], shiftSentence: nil
        )
    }

    // MARK: - Build

    static func build(
        borks: [RevisitBork],
        quests: [RevisitQuest],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Model {
        let today = calendar.startOfDay(for: now)
        func daysBack(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }

        let total = borks.count
        let shifts = shifts(borks, now: now, calendar: calendar)

        return Model(
            total: total,
            isThin: total < thinFloor,
            thisWeek: thisWeek(borks, since: daysBack(7), previousFrom: daysBack(14)),
            comingBack: comingBack(borks),
            neverOpened: neverOpened(borks, before: daysBack(neverOpenedAge)),
            // Whole calendar days, inclusive at both ends: the window is
            // "day 28 through day 35", so it ends at the start of day 27.
            monthAgo: monthAgo(
                borks,
                from: daysBack(monthAgoRange.upperBound),
                to: daysBack(monthAgoRange.lowerBound - 1)
            ),
            quests: quests.filter { $0.remaining > 0 },
            shifts: shifts,
            shiftSentence: sentence(for: shifts)
        )
    }

    // MARK: - Sections

    /// 1. Saved this week — the count, where it came from, and which topics
    ///    grew against the week before.
    private static func thisWeek(
        _ borks: [RevisitBork], since: Date, previousFrom: Date
    ) -> ThisWeek? {
        let recent = borks.filter { $0.savedAt >= since }
        guard !recent.isEmpty else { return nil }

        let previous = borks.filter { $0.savedAt >= previousFrom && $0.savedAt < since }

        let platforms = Dictionary(grouping: recent, by: { $0.platform })
            .map { PlatformCount(name: $0.key.name, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }

        var counts: [String: (name: String, now: Int, before: Int)] = [:]
        for bork in recent {
            guard let id = bork.topicID, let name = bork.topicName else { continue }
            counts[id, default: (name, 0, 0)].now += 1
        }
        for bork in previous {
            guard let id = bork.topicID, let name = bork.topicName else { continue }
            counts[id, default: (name, 0, 0)].before += 1
        }

        let rising = counts
            .map { TopicGrowth(id: $0.key, name: $0.value.name, count: $0.value.now, previous: $0.value.before) }
            .filter { $0.gain > 0 }
            .sorted { ($0.gain, $0.count, $1.name) > ($1.gain, $1.count, $0.name) }
            .prefix(3)

        // Four sources is as much as one line can carry legibly; the count is
        // always the whole week regardless.
        let split = platforms.prefix(4).map { "\($0.count) \($0.name)" }
        let headline = ([Copy.countedBorks(recent.count)] + split).joined(separator: " · ")

        return ThisWeek(count: recent.count, platforms: platforms, rising: Array(rising), headline: headline)
    }

    /// 2. You keep coming back to — the honest measure of what mattered.
    private static func comingBack(_ borks: [RevisitBork]) -> [RevisitBork] {
        borks
            .filter { $0.openCount > 0 }
            .sorted { a, b in
                if a.openCount != b.openCount { return a.openCount > b.openCount }
                let left = a.lastOpenedAt ?? .distantPast
                let right = b.lastOpenedAt ?? .distantPast
                if left != right { return left > right }
                return a.id < b.id
            }
            .prefix(comingBackCap)
            .map { $0 }
    }

    /// 3. Saved, never opened. The reason the tab exists: this is the pile
    ///    every other bookmarking app quietly lets you build and never mentions.
    private static func neverOpened(_ borks: [RevisitBork], before cutoff: Date) -> NeverOpened? {
        let stale = borks
            .filter { $0.openCount == 0 && $0.savedAt < cutoff }
            .sorted { $0.savedAt > $1.savedAt }
        guard !stale.isEmpty else { return nil }

        let noun = stale.count == 1 ? "thing" : "things"
        return NeverOpened(
            items: stale,
            headline: "\(stale.count) \(noun) you saved and never looked at."
        )
    }

    /// 4. A month ago today.
    private static func monthAgo(_ borks: [RevisitBork], from: Date, to: Date) -> [RevisitBork] {
        borks
            .filter { $0.savedAt >= from && $0.savedAt < to }
            .sorted { $0.savedAt > $1.savedAt }
            .prefix(monthAgoCap)
            .map { $0 }
    }

    /// 6. What's shifting — share of saves in the last 30 days against the 30
    ///    before. Share rather than raw count, so a quiet month doesn't read as
    ///    "less of everything".
    private static func shifts(_ borks: [RevisitBork], now: Date, calendar: Calendar) -> [Shift] {
        let today = calendar.startOfDay(for: now)
        guard let recentStart = calendar.date(byAdding: .day, value: -shiftWindow, to: today),
              let earlierStart = calendar.date(byAdding: .day, value: -shiftWindow * 2, to: today)
        else { return [] }

        let recent = borks.filter { $0.savedAt >= recentStart }
        let earlier = borks.filter { $0.savedAt >= earlierStart && $0.savedAt < recentStart }
        guard recent.count + earlier.count >= shiftFloor,
              !recent.isEmpty, !earlier.isEmpty else { return [] }

        var names: [String: String] = [:]
        func share(_ items: [RevisitBork]) -> [String: Double] {
            var counts: [String: Int] = [:]
            for item in items {
                guard let id = item.topicID, let name = item.topicName else { continue }
                counts[id, default: 0] += 1
                names[id] = name
            }
            let filed = counts.values.reduce(0, +)
            guard filed > 0 else { return [:] }
            return counts.mapValues { Double($0) / Double(filed) }
        }

        let nowShare = share(recent), beforeShare = share(earlier)

        return Set(nowShare.keys).union(beforeShare.keys)
            .compactMap { id -> Shift? in
                guard let name = names[id] else { return nil }
                let a = nowShare[id] ?? 0, b = beforeShare[id] ?? 0
                guard abs(a - b) >= shiftThreshold else { return nil }
                return Shift(id: id, name: name, share: a, previousShare: b, isUp: a > b)
            }
            .sorted { ($0.magnitude, $1.id) > ($1.magnitude, $0.id) }
            .prefix(shiftCap)
            // Which three is a question of size; what order to *read* them in
            // is a question of copy. "More Fitness, less Crypto" is a better
            // sentence than "Less Crypto, more Fitness", and a headline that
            // opens with what you are doing more of is the one worth reading.
            // Floating-point ties between an equal rise and fall would
            // otherwise decide it, which is no way to pick a sentence.
            .sorted { a, b in
                if a.isUp != b.isUp { return a.isUp }
                if a.magnitude != b.magnitude { return a.magnitude > b.magnitude }
                return a.id < b.id
            }
    }

    /// "More Fitness, less Crypto" — the whole section in one line.
    private static func sentence(for shifts: [Shift]) -> String? {
        guard !shifts.isEmpty else { return nil }
        let parts = shifts.map { $0.isUp ? "more \($0.name)" : "less \($0.name)" }
        let line = parts.joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}
