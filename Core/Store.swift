import Foundation
import SwiftData

/// The single SwiftData container, living in the App Group so the Share
/// Extension and the app are reading and writing the same file.
///
/// If the App Group isn't provisioned yet (fresh clone, no Team ID set), we
/// fall back to a local store so the app still runs in the Simulator — saves
/// from the share sheet just won't show up until signing is sorted.
enum Store {
    static let appGroupID = "group.com.jpwilson.borkmarkr"

    @MainActor
    static let shared: ModelContainer = make()

    static func make() -> ModelContainer {
        let schema = Schema([Bookmark.self])

        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil {
            let config = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroupID))
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return container
            }
        }

        let local = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            // A container we cannot open at all is unrecoverable — every screen
            // depends on it, so failing loudly here beats a silently empty app.
            fatalError("Could not open the borkmarkr store: \(error)")
        }
    }

    /// Insert-or-update used by both the app's Add flow and the Share
    /// Extension. Re-saving a link you already have updates it in place rather
    /// than creating a second copy.
    @discardableResult
    static func save(
        url: URL,
        title: String,
        author: String? = nil,
        categoryID: String? = nil,
        subcategory: String? = nil,
        tags: [String] = [],
        note: String? = nil,
        noteDate: Date? = nil,
        isUnread: Bool = false,
        in context: ModelContext
    ) throws -> Bookmark {
        let id = Bookmark.stableID(for: url)
        let existing = try context.fetch(
            FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        ).first

        if let existing {
            if !title.isEmpty { existing.title = title }
            if let author { existing.author = author }
            if let categoryID { existing.categoryID = categoryID }
            if let subcategory { existing.subcategory = subcategory }
            if !tags.isEmpty {
                existing.tags = Array(Set(existing.tags + tags)).sorted()
            }
            if let note { existing.note = note }
            if let noteDate { existing.noteDate = noteDate }
            existing.isArchived = false
            if isUnread { existing.isUnread = true }
            try context.save()
            return existing
        }

        let bookmark = Bookmark(
            url: url, title: title, author: author,
            categoryID: categoryID, subcategory: subcategory,
            tags: tags, note: note, noteDate: noteDate, isUnread: isUnread
        )
        context.insert(bookmark)
        try context.save()
        return bookmark
    }
}
