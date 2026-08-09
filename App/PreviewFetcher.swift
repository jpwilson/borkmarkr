import Foundation
import SwiftData

/// Fills in real titles and thumbnails for brks that don't have them yet.
///
/// Runs from the Library screen rather than at save time on purpose: saving must
/// stay instant and offline (the core product rule), and the Share Extension is
/// memory-capped and has no business doing network work. So a brk lands
/// immediately with a slug title, and the card upgrades itself moments later.
///
/// Concurrency is capped and results are written on the main actor, because
/// SwiftData contexts are not safe to touch from arbitrary threads.
@MainActor
final class PreviewFetcher: ObservableObject {

    private var inFlight: Set<String> = []
    /// Small enough not to look like a crawler, big enough that a fresh import
    /// fills in quickly.
    private let maxConcurrent = 4

    func fetchMissing(for bookmarks: [Bookmark], in context: ModelContext) async {
        let pending = bookmarks
            .filter { $0.needsPreview && !inFlight.contains($0.id) }
            .prefix(24)

        guard !pending.isEmpty else { return }

        await withTaskGroup(of: (String, LinkPreview.Result)?.self) { group in
            var running = 0

            for bookmark in pending {
                guard let url = bookmark.url else { continue }
                let id = bookmark.id
                inFlight.insert(id)

                if running >= maxConcurrent {
                    if let finished = await group.next() { apply(finished, in: context) }
                    running -= 1
                }

                group.addTask {
                    let result = await LinkPreview.fetch(for: url)
                    return (id, result)
                }
                running += 1
            }

            for await finished in group { apply(finished, in: context) }
        }

        try? context.save()
    }

    private func apply(_ finished: (String, LinkPreview.Result)?, in context: ModelContext) {
        guard let (id, result) = finished else { return }
        inFlight.remove(id)

        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let bookmark = try? context.fetch(descriptor).first else { return }

        // Always stamp the attempt, so a page with no metadata isn't retried
        // on every single scroll.
        bookmark.previewFetchedAt = .now

        if let image = result.imageURL {
            bookmark.imageURLString = image.absoluteString
        }
        if let author = result.author, bookmark.author == nil || bookmark.author == bookmark.url?.host {
            bookmark.author = author
        }
        if let duration = result.durationSeconds, bookmark.durationSeconds == nil {
            bookmark.durationSeconds = duration
        }

        // Only replace a title we invented from the URL slug. A title the user
        // typed, or a caption the share sheet gave us, is better than anything
        // Open Graph will return.
        if let fetched = result.title, Self.isDerivedTitle(bookmark.title, url: bookmark.url) {
            bookmark.title = fetched
        }

        bookmark.touch()
    }

    /// True when the current title is one we generated from the path, e.g.
    /// "Status" from `/user/status/123`.
    private static func isDerivedTitle(_ title: String, url: URL?) -> Bool {
        guard let url else { return true }
        let derived = Categorizer.fallbackTitle(for: url)
        return title == derived || title.isEmpty
    }
}
