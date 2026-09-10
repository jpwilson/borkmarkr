import Foundation
import SwiftData

/// Fills in real titles and thumbnails for brks that don't have them yet —
/// and, once it can read the page, files the ones the share sheet couldn't.
///
/// Runs from the Library screen rather than at save time on purpose: saving must
/// stay instant and offline (the core product rule), and the Share Extension is
/// memory-capped and has no business doing network work. So a brk lands
/// immediately with a slug title, and the card upgrades itself moments later.
///
/// **Filing after the fact.** A reel shared from Instagram arrives as a bare
/// URL: the extension's offline pass has only `@reel on Instagram` to go on and
/// files nothing, and until now nothing ever came back to it. Now, once the
/// page's title and description have landed, the offline pass runs again on the
/// real caption and hashtags; if that is confident it is applied, and if it is
/// not, the model is asked — once per brk, a handful per pass, only when
/// signed in, and only for brks whose filing is still the machine's. A topic
/// the user picked in the meantime wins: the brk's `updatedAt` is snapshotted
/// before the request and the answer is dropped if it moved.
///
/// Concurrency is capped and results are written on the main actor, because
/// SwiftData contexts are not safe to touch from arbitrary threads.
@MainActor
final class PreviewFetcher: ObservableObject {

    private var inFlight: Set<String> = []
    /// Small enough not to look like a crawler, big enough that a fresh import
    /// fills in quickly.
    private let maxConcurrent = 4
    /// Model calls per pass. The daily quota (`ai_quota_consume`, 200) is
    /// shared with every other AI feature, and a big import must not spend it
    /// in one scroll: the rest stay on their offline answer.
    private let maxModelCalls = 8

    /// A brk whose metadata just landed and whose filing is still in doubt.
    private struct Candidate {
        let id: String
        let context: SmartCategorizer.Context
        /// `updatedAt` after the metadata write. Any change after this is the
        /// user's, and the model's answer must not overwrite it.
        let stamp: Date
    }

    /// - Parameter account: for the second-pass filing. `nil` (signed out,
    ///   previews) means metadata only, exactly as before.
    func fetchMissing(for bookmarks: [Bookmark], in context: ModelContext, account: Account? = nil) async {
        let pending = bookmarks
            .filter { ($0.needsPreview || $0.needsPostedDate) && !inFlight.contains($0.id) }
            .prefix(24)

        guard !pending.isEmpty else { return }

        var candidates: [Candidate] = []

        await withTaskGroup(of: (String, LinkPreview.Result)?.self) { group in
            var running = 0

            for bookmark in pending {
                guard let url = bookmark.url else { continue }
                let id = bookmark.id
                inFlight.insert(id)

                if running >= maxConcurrent {
                    if let finished = await group.next(), let candidate = apply(finished, in: context) {
                        candidates.append(candidate)
                    }
                    running -= 1
                }

                group.addTask {
                    let result = await LinkPreview.fetch(for: url)
                    return (id, result)
                }
                running += 1
            }

            for await finished in group {
                if let candidate = apply(finished, in: context) { candidates.append(candidate) }
            }
        }

        try? context.save()

        guard !candidates.isEmpty, let account, let session = await account.currentSession() else { return }
        for candidate in candidates.prefix(maxModelCalls) {
            guard let better = await SmartCategorizer.suggest(candidate.context, session: session) else { continue }
            file(better, on: candidate, in: context)
        }
        try? context.save()
    }

    /// Writes the metadata and says whether the brk still needs filing.
    private func apply(_ finished: (String, LinkPreview.Result)?, in context: ModelContext) -> Candidate? {
        guard let (id, result) = finished else { return nil }
        inFlight.remove(id)

        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let bookmark = try? context.fetch(descriptor).first, let url = bookmark.url else { return nil }

        // Is the current filing the machine's, or a person's? The extension
        // files from the pre-metadata inputs, so re-running that same pass is
        // the test: a match means nobody has touched it since. Computed before
        // the title is replaced below, or the answer would be to a different
        // question.
        let machineFiled = bookmark.categoryID == nil || {
            let before = Categorizer.suggest(url: url, title: bookmark.title, text: bookmark.text)
            return before.categoryID == bookmark.categoryID && before.subcategory == bookmark.subcategory
        }()

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
        if let posted = result.publishedAt {
            bookmark.postedAt = posted
        }
        if bookmark.canHavePostedDate {
            bookmark.publishedDateChecked = true
        }

        // Only replace a title we invented from the URL slug. A title the user
        // typed, or a caption the share sheet gave us, is better than anything
        // Open Graph will return.
        if let fetched = result.title, Self.isDerivedTitle(bookmark.title, url: bookmark.url) {
            bookmark.title = fetched
        }

        bookmark.touch()

        // Nothing new to read, or a filing that is someone's decision: done.
        guard machineFiled, result.title != nil || result.description != nil else { return nil }

        let after = Categorizer.suggest(
            url: url, title: bookmark.title, text: bookmark.text,
            description: result.description, author: result.author
        )
        if after.isConfident {
            // The caption and hashtags settle it; no model needed.
            bookmark.categoryID = after.categoryID
            bookmark.subcategory = after.subcategory
            bookmark.tags = Self.merged(bookmark.tags, after.tags)
            bookmark.touch()
            return nil
        }
        return Candidate(
            id: id,
            context: .init(url: url, title: bookmark.title, author: result.author ?? bookmark.author,
                           text: bookmark.text, description: result.description),
            stamp: bookmark.updatedAt
        )
    }

    /// Applies the model's answer, unless the brk moved since it was asked.
    private func file(_ better: Categorizer.Suggestion, on candidate: Candidate, in context: ModelContext) {
        let id = candidate.id
        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let bookmark = try? context.fetch(descriptor).first,
              bookmark.updatedAt == candidate.stamp,
              bookmark.deletedAt == nil
        else { return }

        bookmark.categoryID = better.categoryID
        bookmark.subcategory = better.subcategory
        bookmark.tags = Self.merged(bookmark.tags, better.tags)
        bookmark.touch()
    }

    /// Existing tags stay; new ones join. Nothing the user typed is dropped.
    private static func merged(_ existing: [String], _ incoming: [String]) -> [String] {
        var out = existing
        for tag in incoming where !out.contains(tag) && !Platform.isSiteName(tag) { out.append(tag) }
        return out
    }

    /// True when the current title is one we generated from the path, e.g.
    /// "Status" from `/user/status/123`.
    private static func isDerivedTitle(_ title: String, url: URL?) -> Bool {
        guard let url else { return true }
        let derived = Categorizer.fallbackTitle(for: url)
        return title == derived || title.isEmpty
    }
}
