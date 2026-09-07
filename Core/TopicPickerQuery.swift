import Foundation

/// Matching and ordering for the topic picker. Kept out of SwiftUI so it can
/// be compiled with `swiftc` on macOS.
///
/// Search is token-prefix, not mid-word `contains`. "run" should hit Running
/// under Fitness, not Speedruns under Gaming.
enum TopicPickerQuery {
    static func tokens(_ name: String) -> [String] {
        name.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Crude stem so "game" hits Gaming (the e drops before -ing) without
    /// also letting "run" hit Speedruns.
    static func stem(_ word: String) -> String {
        var w = word
        if w.count > 4, w.hasSuffix("ing") { w.removeLast(3) }
        if w.count > 3, w.hasSuffix("e") { w.removeLast() }
        return w
    }

    static func tokenMatches(_ token: String, needle: String) -> Bool {
        if token.hasPrefix(needle) { return true }
        let needleStem = stem(needle)
        let tokenStem = stem(token)
        if needleStem.count >= 3, token.hasPrefix(needleStem) { return true }
        if needleStem.count >= 3, tokenStem.count >= 3, tokenStem == needleStem { return true }
        return false
    }

    /// Lower is better. `nil` means no match.
    /// 0 topic token/name prefix, 1 topic name contains, 2 sub token prefix.
    static func matchRank(topicName: String, subs: [String], needle: String) -> Int? {
        let needle = needle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        guard !needle.isEmpty else { return 0 }

        let topicTokens = tokens(topicName)
        let topicLower = topicName.lowercased()
        if topicTokens.contains(where: { tokenMatches($0, needle: needle) }) { return 0 }
        if topicLower.hasPrefix(needle) { return 0 }
        if topicLower.contains(needle) { return 1 }

        for sub in subs {
            if tokens(sub).contains(where: { tokenMatches($0, needle: needle) }) { return 2 }
        }
        return nil
    }

    /// The filtered topic list, **best match first**.
    ///
    /// This used to sort by name alone and throw the rank away, which put the
    /// wrong row on top of the one case people actually search: typing "runn"
    /// listed Fitness above the user's own Running topic, because Fitness has
    /// a Running subtopic and F sorts before R. A topic whose *own name*
    /// matches is what you meant; a topic that matches only through one of its
    /// forty subtopics is a second-best guess, and second-best guesses do not
    /// go first.
    ///
    /// So: sort by `matchRank` (0 name prefix, 1 name contains, 2 subtopic
    /// only), then A–Z inside each tier. Custom topics are ranked by exactly
    /// the same rule as the built-ins — being yours is not a tier. An empty
    /// filter ranks everything 0, so the unsearched list is still plain A–Z.
    static func shown(topics: [Topic], subs: (Topic) -> [String], filter: String) -> [Topic] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return topics.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let ranked = topics.compactMap { topic -> (Topic, Int)? in
            guard let rank = matchRank(topicName: topic.name, subs: subs(topic), needle: needle)
            else { return nil }
            return (topic, rank)
        }
        return ranked.sorted { left, right in
            if left.1 != right.1 { return left.1 < right.1 }
            return left.0.name.localizedStandardCompare(right.0.name) == .orderedAscending
        }.map(\.0)
    }

    /// Subtopics read A–Z — built-ins and the ones you added yourself in one
    /// list, not two.
    ///
    /// The taxonomy's own order is authored: Fitness opens with Running,
    /// Strength, Mobility because that is roughly how popular they are. That
    /// is useful to whoever wrote the list and useless to whoever is looking
    /// for "Yoga" among forty pills — the only order you can *search with your
    /// eyes* is alphabetical. Appending a user's own subtopics after the
    /// built-ins made it worse again: their entries, the ones they care most
    /// about, ended up furthest down.
    ///
    /// `localizedStandardCompare` is the Finder comparison: locale-aware,
    /// case-insensitive, and numeric, so "Zone 2" sorts before "Zone 10". The
    /// web app's picker sorts the same way.
    static func alphabetical(_ subs: [String]) -> [String] {
        subs.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func matchingSubs(_ subs: [String], needle: String) -> Set<String> {
        let needle = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return Set(subs.filter { tokens($0).contains(where: { tokenMatches($0, needle: needle) }) })
    }

    static func canAddName(_ raw: String, to existing: [String]) -> Bool {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard candidate.count >= 2 else { return false }
        return !existing.contains { $0.lowercased() == candidate }
    }
}
