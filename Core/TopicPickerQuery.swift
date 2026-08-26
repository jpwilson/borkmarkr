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

    static func shown(topics: [Topic], subs: (Topic) -> [String], filter: String) -> [Topic] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [Topic]
        if needle.isEmpty {
            filtered = topics
        } else {
            filtered = topics.filter {
                matchRank(topicName: $0.name, subs: subs($0), needle: needle) != nil
            }
        }
        return filtered.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
