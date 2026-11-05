import Foundation
import SwiftData

/// Fills in real titles and thumbnails for brks that don't have them yet —
/// and, once it can read the page, files the ones the share sheet couldn't.
///
/// Runs from the Library screen rather than at save time on purpose: saving must
/// stay instant and offline (the core product rule), and the Share Extension is
/// memory-capped and gone in seconds — signed in, it reads the page and asks the
/// model only while its dial is up (`QuickFileShareSession.enrich`). So a brk
/// lands immediately with a slug title, and the card upgrades itself moments later.
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
/// **A share made by hand is asked whatever the evidence.** Every save made
/// by hand gets the model's judgement once. A share the share sheet didn't
/// settle (no session to borrow, Quick File turned off, the Shortcut, or a
/// question the sheet closed on) is asked here instead, however confident
/// the offline pass is, ahead of the rest, and its answer is weighed the way
/// the sheet's dial weighs it: one more piece of evidence (`FilingSuggest`),
/// so sure keywords or your history with the creator can still win. It is
/// told apart by `isUnread`, which only the share sheet and the Shortcut set,
/// and by nothing having read its page yet. Imports, syncs and backfills
/// never carry that, and keep the rule above; so does a share the Library
/// has already marked read.
///
/// Concurrency is capped and results are written on the main actor, because
/// SwiftData contexts are not safe to touch from arbitrary threads.
@MainActor
final class PreviewFetcher: ObservableObject {

    private var inFlight: Set<String> = []
    private var revisions: [String: Date] = [:]
    /// Small enough not to look like a crawler, big enough that a fresh import
    /// fills in quickly.
    private let maxConcurrent = 4
    /// Model calls per pass. The daily quota (`ai_quota_consume`, 200) is
    /// shared with every other AI feature, and a big import must not spend it
    /// in one scroll: the rest stay on their offline answer.
    private let maxModelCalls = 8
    /// Thumbnails read for on-screen text per pass: a download (usually from
    /// the cover cache) and a quick Vision pass each. Four keeps up with a
    /// normal day's saves without making a pass feel heavy.
    private let maxThumbnailReads = 4

    /// A brk whose metadata just landed and that the model is asked about:
    /// its filing is still in doubt, or it is a share the share sheet didn't
    /// settle.
    private struct Candidate {
        let id: String
        let context: SmartCategorizer.Context
        /// `updatedAt` after the metadata write. Any change after this is the
        /// user's, and the model's answer must not overwrite it.
        let stamp: Date
        /// A share the share sheet didn't settle: asked whatever the
        /// evidence, ahead of the rest, and its answer weighed like the
        /// sheet's.
        let share: Bool
    }

    /// - Parameter account: for the second-pass filing. `nil` (signed out,
    ///   previews) means metadata only, exactly as before.
    func fetchMissing(for bookmarks: [Bookmark], in context: ModelContext, account: Account? = nil) async {
        let pending = bookmarks
            .filter { $0.needsPreview && !inFlight.contains($0.id) }
            .prefix(24)

        guard !pending.isEmpty else {
            await readThumbnails(of: bookmarks)
            return
        }

        var candidates: [Candidate] = []

        await withTaskGroup(of: (String, LinkPreview.Result)?.self) { group in
            var running = 0

            for bookmark in pending {
                guard let url = bookmark.url else { continue }
                let id = bookmark.id
                inFlight.insert(id)
                revisions[id] = bookmark.updatedAt

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

        if !candidates.isEmpty, let account, let session = await account.currentSession() {
            // Shares first: each is one save made by hand, and the cap is
            // there for imports.
            let queue = candidates.filter(\.share) + candidates.filter { !$0.share }
            // What a share's answer is weighed against, as on the dial.
            let weighing = queue.contains(where: \.share)
                ? (memory: QuickFileBridge.memory(bookmarks), order: Self.taxonomyOrder(in: context))
                : nil
            for candidate in queue.prefix(maxModelCalls) {
                guard let better = await SmartCategorizer.suggest(candidate.context, session: session) else { continue }
                file(better, on: candidate, in: context, weighing: weighing)
            }
            try? context.save()
        }

        await readThumbnails(of: bookmarks)
    }

    /// On-screen text for the saves still waiting on a topic — none yet, or
    /// only the app's guess — so the Quick File dial and triage have it to
    /// hand. Read quickly (`.fast`), newest first, a few a pass, and never for
    /// a filing that is someone's decision. It stays on this device
    /// (`ThumbnailText`), is never synced and never sent anywhere.
    private func readThumbnails(of bookmarks: [Bookmark]) async {
        var due: [(id: String, image: URL)] = []
        for bookmark in bookmarks {
            if due.count == maxThumbnailReads { break }
            guard bookmark.deletedAt == nil, !bookmark.isWaiting, let image = bookmark.imageURL,
                  Taxonomy.category(id: bookmark.categoryID) == nil
                    || EnrichmentPolicy.mayFile(source: bookmark.filingSource),
                  !ThumbnailText.hasRead(bookmark.id, accurate: false) else { continue }
            due.append((bookmark.id, image))
        }
        for entry in due {
            _ = await ThumbnailText.read(entry.id, imageURL: entry.image, accurate: false)
        }
    }

    /// Writes the metadata and says whether the brk still needs filing.
    private func apply(_ finished: (String, LinkPreview.Result)?, in context: ModelContext) -> Candidate? {
        guard let (id, result) = finished else { return nil }
        inFlight.remove(id)
        let revision = revisions.removeValue(forKey: id)

        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let bookmark = try? context.fetch(descriptor).first, let url = bookmark.url,
              bookmark.deletedAt == nil, bookmark.updatedAt == revision else { return nil }

        // Explicit provenance only. Legacy choices cannot safely be inferred
        // by rerunning a categorizer whose rules may since have changed.
        let machineFiled = EnrichmentPolicy.mayFile(source: bookmark.filingSource)
        // A share the share sheet didn't settle: still unread, and nothing
        // has read its page. Noted before the attempt is stamped below.
        let share = bookmark.isUnread && bookmark.previewFetchedAt == nil && (bookmark.enrichmentAttempts ?? 0) == 0

        // Always stamp the attempt, so a page with no metadata isn't retried
        // on every single scroll.
        bookmark.previewFetchedAt = .now
        bookmark.enrichmentAttempts = (bookmark.enrichmentAttempts ?? 0) + 1
        if SavedContent.excerpt(result.description) != nil ||
            (result.title != nil && !Self.isDerivedTitle(result.title!, url: url) &&
             result.title?.range(of: #" on (X|Instagram|Threads)$"#, options: .regularExpression) == nil) {
            bookmark.enrichmentVersion = EnrichmentPolicy.version
        }

        if let image = result.imageURL {
            bookmark.imageURLString = image.absoluteString
        }
        if SavedContent.excerpt(bookmark.text) == nil,
           let excerpt = SavedContent.excerpt(result.description) {
            bookmark.text = excerpt
        }
        // Replace only a stand-in ("instagram.com", a platform name). The
        // old test compared against `url.host`, which keeps its "www." while
        // the stored stand-in drops it — so for most links a real creator
        // never landed.
        if let author = result.author,
           !Bookmark.isPlaceholderAuthor(author, url: url, platform: bookmark.platform),
           Bookmark.isPlaceholderAuthor(bookmark.author, url: url, platform: bookmark.platform) {
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
        if bookmark.titleEdited != true, let fetched = result.title, Self.isDerivedTitle(bookmark.title, url: bookmark.url) {
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
            // The caption and hashtags settle it; no model needed, except
            // for a share's judgement.
            bookmark.categoryID = after.categoryID
            bookmark.subcategory = after.subcategory
            if bookmark.tagsEdited == false { bookmark.tags = Self.merged(bookmark.tags, after.tags) }
            bookmark.touch()
            guard share else { return nil }
        }
        return Candidate(
            id: id,
            context: .init(url: url, title: bookmark.title, author: result.author ?? bookmark.author,
                           text: bookmark.text, description: result.description),
            stamp: bookmark.updatedAt,
            share: share
        )
    }

    /// Applies the model's answer, unless the brk moved since it was asked.
    /// A share's answer is weighed as the share sheet's dial would have
    /// weighed it, so sure keywords or your history with the creator can
    /// still win; the rest take the answer as it comes.
    private func file(_ better: Categorizer.Suggestion, on candidate: Candidate, in context: ModelContext,
                      weighing: (memory: FilingMemory, order: [String])?) {
        let id = candidate.id
        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let bookmark = try? context.fetch(descriptor).first,
              bookmark.updatedAt == candidate.stamp,
              EnrichmentPolicy.mayFile(source: bookmark.filingSource),
              bookmark.deletedAt == nil
        else { return }

        var filing = (categoryID: better.categoryID, subcategory: better.subcategory)
        if candidate.share, let weighing {
            let input = FilingInput(url: candidate.context.url, title: bookmark.title, text: bookmark.text,
                                    description: candidate.context.description, author: bookmark.author,
                                    ocrText: ThumbnailText.cached(id))
            let ranking = FilingSuggest.rank(input, memory: weighing.memory, ai: better, taxonomyOrder: weighing.order)
            guard ranking.preselect != nil, let best = ranking.candidates.first else { return }
            filing = (best.categoryID, best.subcategory)
        }
        bookmark.categoryID = filing.categoryID
        bookmark.subcategory = filing.subcategory
        if bookmark.tagsEdited == false { bookmark.tags = Self.merged(bookmark.tags, better.tags) }
        bookmark.touch()
    }

    /// The dial's topic order: the built-ins, then yours by id.
    private static func taxonomyOrder(in context: ModelContext) -> [String] {
        let yours = (try? context.fetch(FetchDescriptor<CustomTopic>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        return QuickFileBridge.taxonomyOrder(customIDs: yours.map(\.id))
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
