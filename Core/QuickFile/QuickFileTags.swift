import Foundation
import Observation

/// The tags on one Quick File save while the refine panel is up.
///
/// `chosen` is what gets written. `suggested` is this link's own (the
/// Categorizer at tap 1, then the page and the model as they answer), in the
/// order they arrived. A suggestion joins `chosen` by itself only until the
/// person touches a tag (`edited`); after that, what they left is what they
/// meant. A tag they turn off goes into `removed`, so the Share Extension,
/// which can't see the bork's existing tags, can still take it off
/// (`BookmarkDraft.tagsRemoved`).
///
/// `onChange` fires for the person's actions only. `suggest` says whether it
/// changed `chosen` instead, so a host writes once per late answer.
@MainActor @Observable
final class QuickFileTags {
    private(set) var chosen: [String]
    private(set) var suggested: [String]
    private(set) var edited: Bool
    private(set) var removed: [String] = []
    /// The inline "+ Tag" field.
    var draft = ""

    @ObservationIgnored var onChange: () -> Void = {}

    init(chosen: [String], suggested: [String] = [], edited: Bool = false) {
        self.chosen = Self.unique(chosen.map(Self.key).filter { !$0.isEmpty })
        self.suggested = Self.unique(suggested.map(Self.key).filter { !$0.isEmpty && !Platform.isSiteName($0) })
        self.edited = edited
    }

    func isOn(_ tag: String) -> Bool { chosen.contains(Self.key(tag)) }

    /// A chip: on or off.
    func toggle(_ tag: String) {
        let tag = Self.key(tag)
        guard !tag.isEmpty else { return }
        if chosen.contains(tag) {
            chosen.removeAll { $0 == tag }
            if !removed.contains(tag) { removed.append(tag) }
        } else {
            chosen.append(tag)
            removed.removeAll { $0 == tag }
        }
        edited = true
        onChange()
    }

    /// A typed tag, cleaned (`QuickFileRefine.cleanTag`) and turned on. False
    /// when nothing was left or it was on already.
    @discardableResult
    func add(_ raw: String) -> Bool {
        guard let tag = QuickFileRefine.cleanTag(raw), !chosen.contains(tag) else { return false }
        chosen.append(tag)
        removed.removeAll { $0 == tag }
        edited = true
        onChange()
        return true
    }

    /// Whatever is in the field becomes a tag, and the field empties.
    func commitDraft() {
        let raw = draft
        if !draft.isEmpty { draft = "" }
        add(raw)
    }

    /// A late answer's tags. They join the suggestions, and `chosen` too
    /// while the person hasn't touched a tag. Site names stay out. True when
    /// `chosen` changed, so the host writes.
    @discardableResult
    func suggest(_ incoming: [String]) -> Bool {
        var changed = false
        for raw in incoming {
            let tag = Self.key(raw)
            guard !tag.isEmpty, !Platform.isSiteName(tag) else { continue }
            if !suggested.contains(tag) { suggested.append(tag) }
            if !edited, !chosen.contains(tag), !removed.contains(tag) {
                chosen.append(tag)
                changed = true
            }
        }
        return changed
    }

    private static func key(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}
