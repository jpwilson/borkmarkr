import Foundation

/// What the refine panel offers once a topic is chosen: which subtopic chips,
/// which tag chips, in what order, and how a typed tag is cleaned.
///
/// Pure Foundation plus `Platform.isSiteName` and `TagRecency`, so a plain
/// `swiftc` script checks it against the fixture the web's port is checked
/// against too (`Scripts/fixtures/quick_file_refine_cases.json`). Its `_rules`
/// key says the same as the doc comments here; the two ports must agree.
enum QuickFileRefine {
    struct TagChip: Equatable, Sendable {
        let tag: String
        let isOn: Bool
    }

    /// One of your own filings, for `subUse`.
    struct Use: Sendable {
        var categoryID: String
        var subcategory: String?
        var at: Date
    }

    /// The longest tag the "+ Tag" field keeps, as on the web.
    static let tagLength = 30

    /// The subtopic chips for a topic: the ones suggested for this link, then
    /// the ones you use most, then the rest of the topic in the order given
    /// (callers pass it A–Z). Only names the topic has, matched ignoring case
    /// and shown in the topic's own spelling, each once.
    static func subtopicChips(all: [String], suggested: [String], used: [String]) -> [String] {
        var canonical: [String: String] = [:]
        for name in all where canonical[key(name)] == nil { canonical[key(name)] = name }
        var out: [String] = []
        var seen = Set<String>()
        for name in suggested + used + all {
            let k = key(name)
            guard let spelled = canonical[k], seen.insert(k).inserted else { continue }
            out.append(spelled)
        }
        return out
    }

    /// The tag chips: tags you have that neither list offers (typed, or on
    /// the bork already), then this link's suggestions, then the ones you
    /// used lately on this filing. Lowercased and trimmed, each once. A site
    /// name is never offered, but one you already have stays.
    static func tagChips(chosen: [String], suggested: [String], recent: [String]) -> [TagChip] {
        let on = Set(chosen.map(key).filter { !$0.isEmpty })
        let offered = (suggested + recent).map(key).filter { !$0.isEmpty && !Platform.isSiteName($0) }
        let offeredSet = Set(offered)
        let own = chosen.map(key).filter { !$0.isEmpty && !offeredSet.contains($0) }
        var out: [TagChip] = []
        var seen = Set<String>()
        for tag in own + offered where seen.insert(tag).inserted {
            out.append(TagChip(tag: tag, isOn: on.contains(tag)))
        }
        return out
    }

    /// The web's `cleanTag`: every "#" out, trimmed, lowercased, runs of
    /// spaces made one, at most 30 characters. Nil when nothing is left.
    static func cleanTag(_ raw: String) -> String? {
        let words = raw.replacingOccurrences(of: "#", with: "")
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let tag = String(words.joined(separator: " ").prefix(tagLength))
            .trimmingCharacters(in: .whitespaces)
        return tag.isEmpty ? nil : tag
    }

    /// Your most-used subtopics per topic: most filings first, then the most
    /// recent, then A–Z. Feeds the second group of subtopic chips.
    static func subUse(_ uses: [Use], perTopic: Int = 8) -> [String: [String]] {
        var tally: [String: [String: (count: Int, newest: Date)]] = [:]
        for use in uses {
            guard let sub = use.subcategory, !sub.isEmpty else { continue }
            let was = tally[use.categoryID]?[sub]
            tally[use.categoryID, default: [:]][sub] = ((was?.count ?? 0) + 1, max(was?.newest ?? .distantPast, use.at))
        }
        return tally.mapValues { subs in
            Array(subs.sorted { a, b in
                if a.value.count != b.value.count { return a.value.count > b.value.count }
                if a.value.newest != b.value.newest { return a.value.newest > b.value.newest }
                return a.key < b.key
            }.prefix(perTopic).map(\.key))
        }
    }

    /// The `recentTagTable` key for a filing; a topic alone has an empty
    /// subtopic.
    static func tagKey(_ categoryID: String, _ subcategory: String?) -> String {
        "\(categoryID)\u{1F}\(subcategory ?? "")"
    }

    /// `TagRecency.suggestions` worked out ahead for the filings you used
    /// most lately (each topic, and each topic › subtopic), so the Share
    /// Extension can offer recent tags without the library.
    static func recentTagTable(_ items: [TagRecency.Item], pairs: Int = 150, perPair: Int = 12) -> [String: [String]] {
        var byTopic: [String: [TagRecency.Item]] = [:]
        var newest: [String: (categoryID: String, subcategory: String?, at: Date)] = [:]
        for item in items where !item.tags.isEmpty {
            guard let id = item.categoryID, !id.isEmpty else { continue }
            byTopic[id, default: []].append(item)
            for sub in [nil, item.subcategory] {
                let k = tagKey(id, sub)
                if (newest[k]?.at ?? .distantPast) <= item.at { newest[k] = (id, sub, item.at) }
            }
        }
        let latest = newest.values.sorted { a, b in
            a.at != b.at ? a.at > b.at : tagKey(a.categoryID, a.subcategory) < tagKey(b.categoryID, b.subcategory)
        }
        var table: [String: [String]] = [:]
        for pair in latest.prefix(pairs) {
            let tags = TagRecency.suggestions(in: byTopic[pair.categoryID] ?? [], categoryID: pair.categoryID,
                                              subcategory: pair.subcategory, limit: perPair)
            if !tags.isEmpty { table[tagKey(pair.categoryID, pair.subcategory)] = tags }
        }
        return table
    }

    /// A filing's recent tags from the table: its own, else its topic's.
    static func recentTags(in table: [String: [String]], categoryID: String, subcategory: String?) -> [String] {
        table[tagKey(categoryID, subcategory)] ?? table[tagKey(categoryID, nil)] ?? []
    }

    private static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Where a host's refine panel gets the lists `QuickFileRefine` orders. The
/// app reads the library; the Share Extension reads the snapshot.
struct QuickFileRefineSource {
    /// Every subtopic of a topic, built-in and yours, A–Z.
    var subs: (String) -> [String]
    /// Your most-used subtopics of a topic.
    var used: (String) -> [String]
    /// Tags you used lately on a topic › subtopic.
    var recentTags: (String, String?) -> [String]

    /// The built-in subtopics and nothing else.
    static var none: QuickFileRefineSource {
        QuickFileRefineSource(subs: { Taxonomy.category(id: $0)?.subs ?? [] }, used: { _ in [] },
                              recentTags: { _, _ in [] })
    }
}
