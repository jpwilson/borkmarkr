import Foundation
import SwiftData

/// A subtopic you added yourself.
///
/// The built-in taxonomy is 50 topics and ~612 subtopics, which covers most of
/// what people save — but it will never cover everyone. Somebody's into
/// bouldering, or Warhammer, or sourdough hydration ratios, and finding your
/// thing simply absent is the moment an app stops feeling like yours.
///
/// Stored separately from `Taxonomy` rather than mutating it, for two reasons:
/// the built-in list stays a stable, shippable constant (and can be improved in
/// an update without clobbering your additions), and custom entries are rows —
/// so they sync, and they can be deleted without leaving a hole in the
/// built-ins.
@Model
final class CustomSubtopic {
    @Attribute(.unique) var id: String
    /// Which built-in topic this hangs under.
    var categoryID: String
    var name: String
    var createdAt: Date
    var deletedAt: Date?

    init(categoryID: String, name: String) {
        // Content-derived so adding "Bouldering" to Fitness twice — on two
        // devices, or twice by accident — is one subtopic, not two.
        self.id = "\(categoryID)|\(name.lowercased())"
        self.categoryID = categoryID
        self.name = name
        self.createdAt = .now
    }
}

/// A topic you added yourself. Same idea as `CustomSubtopic`: the shipped
/// 50 stay a constant, your additions are rows that can be renamed, deleted
/// and synced without a migration of the built-in list.
@Model
final class CustomTopic {
    @Attribute(.unique) var id: String
    var name: String
    var hue: Double
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(name: String, hue: Double) {
        self.id = Self.makeID(from: name)
        self.name = name
        self.hue = hue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var asTopic: Topic { Topic(id: id, name: name, hue: hue, subs: []) }

    static func makeID(from name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let collapsed = slug.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = collapsed.isEmpty ? "topic" : collapsed
        return "custom.\(base)"
    }

    /// First unused hue, walking in steps of 7° so a new topic doesn't land
    /// on top of a built-in neighbour.
    static func nextHue(existing: [CustomTopic]) -> Double {
        let taken = Taxonomy.all.map(\.hue) + existing.filter { $0.deletedAt == nil }.map(\.hue)
        for step in 0..<52 {
            let candidate = Double((step * 7) % 360)
            if taken.allSatisfy({ abs($0 - candidate) >= 3 }) { return candidate }
        }
        return Double((existing.count * 13) % 360)
    }
}

enum TaxonomyName {
    /// "trail running" → "Trail running", matching the built-in style.
    static func formatted(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = name.first else { return name }
        return String(first).uppercased() + name.dropFirst()
    }
}

/// Merges the built-in taxonomy with a user's own topics and subtopics.
///
/// Everything that displays a topic or subtopic list goes through here, so a
/// custom entry shows up everywhere the built-ins do — picker, Browse, Search,
/// topic-page chips — without each screen knowing custom ones exist.
struct MergedTaxonomy {
    private let extraTopics: [Topic]
    private let customTopicIDs: Set<String>
    /// categoryID -> extra subtopic names.
    private let custom: [String: [String]]

    init(topics: [CustomTopic] = [], subtopics: [CustomSubtopic] = []) {
        let liveTopics = topics.filter { $0.deletedAt == nil }
        extraTopics = liveTopics.map(\.asTopic)
        customTopicIDs = Set(liveTopics.map(\.id))

        var grouped: [String: [String]] = [:]
        for entry in subtopics where entry.deletedAt == nil {
            grouped[entry.categoryID, default: []].append(entry.name)
        }
        custom = grouped.mapValues { $0.sorted() }

        Taxonomy.installCustomTopics(extraTopics)
    }

    init(custom subtopics: [CustomSubtopic]) {
        self.init(topics: [], subtopics: subtopics)
    }

    /// Built-ins first (stable order), then your topics alphabetically.
    var allTopics: [Topic] {
        Taxonomy.all + extraTopics.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func topic(id: String?) -> Topic? {
        guard let id else { return nil }
        return Taxonomy.category(id: id) ?? extraTopics.first { $0.id == id }
    }

    func isCustomTopic(_ id: String) -> Bool { customTopicIDs.contains(id) }

    /// Built-ins first (familiar order), then your additions.
    func subs(for topic: Topic) -> [String] {
        topic.subs + (custom[topic.id] ?? []).filter { name in
            // Guard against a custom entry duplicating a built-in that was
            // added to the app after the user created theirs.
            !topic.subs.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    func isCustom(_ name: String, in topic: Topic) -> Bool {
        (custom[topic.id] ?? []).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
