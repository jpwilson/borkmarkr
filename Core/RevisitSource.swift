import Foundation

/// The one place SwiftData meets `Revisit`.
///
/// `Revisit` itself never mentions `Bookmark` or `Mission`, which is what keeps
/// it compilable — and testable — with `swiftc` alone. This file is the adapter
/// that pays for that: it maps the models to plain values and nothing else.
/// A future weekly digest built from Postgres rows writes a second adapter here
/// and reuses every line of the computation.
extension Bookmark {
    var revisitBork: RevisitBork {
        RevisitBork(
            id: id,
            title: displayTitle,
            platform: platform,
            topicID: categoryID,
            topicName: category?.name,
            savedAt: savedAt,
            openCount: openCount,
            lastOpenedAt: lastOpenedAt
        )
    }
}

extension Mission {
    /// "Steps remaining" is the quest's unchecked to-dos. A quest with no
    /// to-dos at all isn't in progress, it's just filed — and a Revisit
    /// section full of every quest you ever made is a list, not a prompt.
    var revisitQuest: RevisitQuest {
        RevisitQuest(id: id, title: title, remaining: todos.filter { !$0.done }.count)
    }
}

extension Revisit {

    /// Model objects in, plain values out. Cheap and main-actor bound: the
    /// caller does this, hands the result to `build(borks:quests:now:)` off the
    /// main actor, and the tab switch never waits on either.
    static func snapshot(
        from bookmarks: [Bookmark], missions: [Mission]
    ) -> (borks: [RevisitBork], quests: [RevisitQuest]) {
        (
            bookmarks.filter { $0.deletedAt == nil }.map(\.revisitBork),
            missions.filter { $0.deletedAt == nil && !$0.isArchived }.map(\.revisitQuest)
        )
    }

    /// The whole computation in one call, for callers that don't care where it
    /// runs (previews, a future digest job).
    static func build(from bookmarks: [Bookmark], missions: [Mission], now: Date = .now) -> Model {
        let input = snapshot(from: bookmarks, missions: missions)
        return build(borks: input.borks, quests: input.quests, now: now)
    }
}
