import Foundation
import SwiftData

/// Persistence.
///
/// **Engineering deviation from the handoff.** The obvious design — and what v1
/// did — is to let the Share Extension open the same SwiftData container as the
/// app and write straight into it. That works right up until both processes are
/// alive at once (the app in the background, the extension launched from
/// Instagram), where two independent writers on one SQLite store risks
/// corruption and lost writes. Core Data's multi-process story has always been
/// fragile and SwiftData inherits it.
///
/// So the extension never touches the database. It appends a small JSON file to
/// an **inbox** directory in the App Group, then exits. The app drains that
/// inbox on launch and on foreground. Single writer, atomic file writes, no
/// coordination needed, and a crash mid-save loses at most one pending item —
/// which is still sitting in the inbox to be picked up next launch.
enum Store {
    static let appGroupID = "group.com.jpwilson.borkmarkr"

    @MainActor
    static let shared: ModelContainer = make()

    static func make() -> ModelContainer {
        let schema = Schema([Bookmark.self, BookmarkCollection.self, Mission.self, CustomSubtopic.self, CustomTopic.self])

        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil {
            let config = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroupID))
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return container
            }
        }

        // No App Group yet (fresh clone, signing not set up) — still run, so the
        // app is usable in the Simulator. Shared saves just won't arrive.
        let local = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open the bookmarker store: \(error)")
        }
    }

    // MARK: - Writing

    /// Insert-or-update. Re-saving a link you already have enriches it in place
    /// rather than creating a second copy.
    @discardableResult
    static func save(_ draft: BookmarkDraft, in context: ModelContext) throws -> Bookmark {
        let id = Bookmark.stableID(for: draft.url)
        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            if !draft.title.isEmpty { existing.title = draft.title }
            if let author = draft.author { existing.author = author }
            if let categoryID = draft.categoryID { existing.categoryID = categoryID }
            if let subcategory = draft.subcategory { existing.subcategory = subcategory }
            if !draft.tags.isEmpty {
                existing.tags = Array(Set(existing.tags + draft.tags)).sorted()
            }
            if let text = draft.text { existing.text = text }
            if let duration = draft.durationSeconds { existing.durationSeconds = duration }
            if let note = draft.noteText { existing.noteText = note; existing.noteDate = draft.noteDate }
            if let image = draft.imageURLString { existing.imageURLString = image }
            if let posted = draft.postedAt { existing.postedAt = posted }
            if draft.previewFetched {
                existing.previewFetchedAt = .now
                existing.publishedDateChecked = true
            }
            existing.deletedAt = nil
            if draft.isUnread { existing.isUnread = true }
            existing.touch()
            try context.save()
            return existing
        }

        let bookmark = Bookmark(
            url: draft.url, title: draft.title, author: draft.author,
            platform: draft.platform, kind: draft.kind,
            categoryID: draft.categoryID, subcategory: draft.subcategory,
            tags: draft.tags, text: draft.text, durationSeconds: draft.durationSeconds,
            noteText: draft.noteText, noteDate: draft.noteDate,
            isUnread: draft.isUnread
        )
        bookmark.imageURLString = draft.imageURLString
        bookmark.postedAt = draft.postedAt
        if draft.previewFetched {
            bookmark.previewFetchedAt = .now
            bookmark.publishedDateChecked = true
        }
        bookmark.rebuildSearchBlob()
        context.insert(bookmark)
        try context.save()
        return bookmark
    }

    // MARK: - Share Extension inbox

    private static var inboxURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        return container.appendingPathComponent("inbox", isDirectory: true)
    }

    /// Called by the Share Extension. Writes atomically and returns quickly —
    /// extensions are memory-capped (~120MB) and killed without ceremony, so
    /// this does the least work possible.
    static func enqueue(_ draft: BookmarkDraft) throws {
        guard let inboxURL else { throw StoreError.noAppGroup }
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        // Name by stable ID hash so the same link shared twice before a drain
        // overwrites rather than queuing twice.
        let name = String(Bookmark.stableID(for: draft.url).hashValue.magnitude) + ".json"
        let data = try JSONEncoder().encode(draft)
        try data.write(to: inboxURL.appendingPathComponent(name), options: .atomic)
    }

    /// What one drain did. `waiting` is the subset of `saved` that arrived
    /// over the signed-out limit and is being held (`SaveLimit`).
    struct Drain {
        var saved = 0
        var waiting = 0
    }

    /// Called by the app on launch and foreground. Drains every queued draft
    /// into the store, deleting each file only after its save commits.
    ///
    /// **A drain never refuses a draft.** The extension has already accepted
    /// the share — over the top of Instagram, in a process that is gone by the
    /// time the user looks up — so there is nobody left to tell. Everything is
    /// saved; what changes over the limit is only that the new ones are
    /// flagged *waiting* until there is an account or there is room.
    @discardableResult
    @MainActor
    static func drainInbox(into context: ModelContext, signedIn: Bool) -> Drain {
        guard let inboxURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: inboxURL, includingPropertiesForKeys: [.creationDateKey]
              )
        else { return Drain() }

        var result = Drain()
        var liveCount = self.liveCount(in: context)

        // Oldest share first, so a batch that crosses the limit fills the last
        // free slots in the order they were sent rather than in whatever order
        // the filesystem happened to list them.
        let queued = files
            .filter { $0.pathExtension == "json" }
            .sorted { created($0) < created($1) }

        for file in queued {
            guard
                let data = try? Data(contentsOf: file),
                let draft = try? JSONDecoder().decode(BookmarkDraft.self, from: data)
            else {
                // Unreadable payload will never become readable — drop it
                // rather than retrying forever on every launch.
                try? FileManager.default.removeItem(at: file)
                continue
            }

            // Re-sharing a link that is already live is an edit, not a new
            // save: it must not be demoted to waiting, and it does not consume
            // a slot it is already occupying.
            let wasLive = isLive(Bookmark.stableID(for: draft.url), in: context)

            guard let bookmark = try? save(draft, in: context) else { continue }
            try? FileManager.default.removeItem(at: file)
            result.saved += 1

            guard !wasLive else { continue }

            if bookmark.isWaiting {
                result.waiting += 1
            } else if SaveLimit.mustWait(liveCount: liveCount, signedIn: signedIn) {
                bookmark.waitingSince = .now
                bookmark.touch()
                result.waiting += 1
            } else {
                liveCount += 1
            }
        }
        try? context.save()
        return result
    }

    /// Let waiting borks in — all of them once there is an account, otherwise
    /// oldest-first into whatever room deletes have made. Returns how many.
    ///
    /// Idempotent and cheap when there is nothing waiting, which is the normal
    /// case, so callers can run it on every foreground and every count change
    /// rather than trying to work out when it might matter.
    @discardableResult
    @MainActor
    static func admitWaiting(in context: ModelContext, signedIn: Bool) -> Int {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.deletedAt == nil && $0.waitingSince != nil }
        )
        let waiting: [Bookmark] = (try? context.fetch(descriptor)) ?? []
        // Sorted the same way the policy sorts, so "the first N of these" and
        // "what `admit` returned" are the same borks. Matching on the dates
        // themselves would be wrong: two shares drained in the same loop can
        // carry an identical `waitingSince`, and a Set of dates would let one
        // free slot admit both.
        let queue: [(bork: Bookmark, since: Date)] = waiting
            .compactMap { bork in bork.waitingSince.map { (bork, $0) } }
            .sorted { $0.since < $1.since }
        guard !queue.isEmpty else { return 0 }

        let room = SaveLimit.admit(
            liveCount: liveCount(in: context),
            waiting: queue.map(\.since),
            signedIn: signedIn
        ).count
        guard room > 0 else { return 0 }

        for entry in queue.prefix(room) {
            entry.bork.waitingSince = nil
            // `touch()` restamps `updatedAt`, which is what puts a newly
            // admitted bork into the next push. A waiting bork is deliberately
            // never uploaded.
            entry.bork.touch()
        }
        try? context.save()
        return room
    }

    /// Borks that count against the limit: not deleted, not waiting.
    @MainActor
    static func liveCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.deletedAt == nil && $0.waitingSince == nil }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    @MainActor
    private static func isLive(_ id: String, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil && $0.waitingSince == nil }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    enum StoreError: Error { case noAppGroup }

    // MARK: - Taxonomy edits

    /// Rename a custom topic. The id stays put so every bork filed under it
    /// stays filed; only the label changes. Search blobs refresh because the
    /// category name lives in them.
    static func renameTopic(_ topic: CustomTopic, to raw: String, in context: ModelContext) {
        let name = TaxonomyName.formatted(raw)
        guard !name.isEmpty, name != topic.name else { return }
        topic.name = name
        topic.updatedAt = .now
        retouchBookmarks(categoryID: topic.id, in: context)
        try? context.save()
    }

    /// Soft-delete a custom topic and unfile its borks — they go to
    /// "Not filed yet" rather than pointing at a name that no longer exists.
    static func deleteTopic(_ topic: CustomTopic, in context: ModelContext) {
        topic.deletedAt = .now
        topic.updatedAt = .now
        let id = topic.id
        for bookmark in bookmarks(categoryID: id, in: context) {
            bookmark.categoryID = nil
            bookmark.subcategory = nil
            bookmark.touch()
        }
        try? context.save()
    }

    static func renameSubtopic(_ entry: CustomSubtopic, to raw: String, in context: ModelContext) {
        let name = TaxonomyName.formatted(raw)
        guard !name.isEmpty, name.caseInsensitiveCompare(entry.name) != .orderedSame else { return }
        let old = entry.name
        let topicID = entry.categoryID
        entry.name = name
        for bookmark in bookmarks(categoryID: topicID, in: context) where bookmark.subcategory == old {
            bookmark.subcategory = name
            bookmark.touch()
        }
        try? context.save()
    }

    static func deleteSubtopic(_ entry: CustomSubtopic, in context: ModelContext) {
        entry.deletedAt = .now
        let old = entry.name
        let topicID = entry.categoryID
        for bookmark in bookmarks(categoryID: topicID, in: context) where bookmark.subcategory == old {
            bookmark.subcategory = nil
            bookmark.touch()
        }
        try? context.save()
    }

    private static func bookmarks(categoryID: String, in context: ModelContext) -> [Bookmark] {
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.deletedAt == nil })
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.categoryID == categoryID }
    }

    private static func retouchBookmarks(categoryID: String, in context: ModelContext) {
        for bookmark in bookmarks(categoryID: categoryID, in: context) {
            bookmark.touch()
        }
    }
}

/// What the extension queues and the Add flow submits. Codable so it can cross
/// the process boundary as JSON.
struct BookmarkDraft: Codable, Sendable {
    var url: URL
    var title: String
    var author: String?
    var platform: Platform?
    var kind: ItemKind?
    var categoryID: String?
    var subcategory: String?
    var tags: [String] = []
    var text: String?
    var durationSeconds: Int?
    var noteText: String?
    var noteDate: Date?
    var isUnread: Bool = false
    var imageURLString: String?
    var postedAt: Date?
    /// Set when the Add flow already fetched metadata, so the background
    /// fetcher doesn't immediately go and do it again.
    var previewFetched: Bool = false
}
