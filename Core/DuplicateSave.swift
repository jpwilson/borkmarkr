import Foundation

/// Saving a link you already have.
///
/// `Store.save` is insert-or-update: re-saving a URL enriches the bork that is
/// already there rather than making a second one, which is right and is what
/// `Bookmark.stableID` exists for. What was wrong is that the Add sheet never
/// said so. You pasted a link, watched a preview appear, picked a topic, tapped
/// Bork it — and the app quietly merged all of it into a bork you saved three
/// weeks ago and filed somewhere else. Nothing was lost and nothing looked like
/// it had happened.
///
/// So the sheet checks first and shows what it found. The share sheet is
/// deliberately **not** changed: it must stay one tap over someone else's app
/// and has no screen to ask on, and merging silently is the right answer there.
///
/// Pure over the id — no store, no `Bookmark`, no SwiftData — so the rule can
/// be exercised in `Scripts/test_save_limit.swift` alongside the other gate
/// that decides whether a save happens.
enum DuplicateSave {

    /// The live bork this id would land on, if there is one.
    ///
    /// A **tombstoned** match is not a duplicate. Deleting a bork and saving
    /// the link again is someone changing their mind, and the answer to it is
    /// a fresh save — telling them it is already in a library they can't see
    /// it in would be a lie with no way out of it.
    static func match<Item>(
        stableID: String,
        in items: [Item],
        id: (Item) -> String,
        deletedAt: (Item) -> Date?
    ) -> Item? {
        items.first { id($0) == stableID && deletedAt($0) == nil }
    }

    /// "saved today" · "saved yesterday" · "saved 3 days ago".
    ///
    /// `nil` past a fortnight, where a count of days stops being how anyone
    /// thinks about it and the caller prints the date instead. Days are a
    /// calendar difference at the call site, for the reason in `RelativeDate`:
    /// anchoring to noon and dividing drifts across DST.
    static func savedPhrase(daysAgo: Int) -> String? {
        switch daysAgo {
        case ..<1: return "saved today"
        case 1: return "saved yesterday"
        case 2...13: return "saved \(daysAgo) days ago"
        default: return nil
        }
    }

    /// "filed under Fitness › Running", or where it isn't filed at all.
    static func filedPhrase(topic: String?, subtopic: String?) -> String {
        guard let topic else { return "not filed yet" }
        guard let subtopic else { return "filed under \(topic)" }
        return "filed under \(topic) › \(subtopic)"
    }
}
