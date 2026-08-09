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

/// Merges the built-in taxonomy with a user's own additions.
///
/// Everything that displays a subtopic list goes through here, so a custom
/// subtopic shows up everywhere the built-ins do — picker, topic page chips,
/// filters — without each screen knowing custom ones exist.
struct MergedTaxonomy {
    /// categoryID -> extra subtopic names.
    private let custom: [String: [String]]

    init(custom subtopics: [CustomSubtopic]) {
        var grouped: [String: [String]] = [:]
        for entry in subtopics where entry.deletedAt == nil {
            grouped[entry.categoryID, default: []].append(entry.name)
        }
        self.custom = grouped.mapValues { $0.sorted() }
    }

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
