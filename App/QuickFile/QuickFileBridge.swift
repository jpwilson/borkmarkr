import Foundation
import SwiftData
import UIKit

/// Where Quick File meets the app's own data.
///
/// The ranking (`FilingSuggest`) and its memory (`FilingMemory`) are pure
/// Foundation in Core so the Share Extension can run them. This is the app's
/// half: reading your filing history out of SwiftData, turning a bookmark into
/// a ranking input, and leaving the Share Extension everything it needs in the
/// App Group, because it may never open SwiftData itself:
///
/// - the **snapshot** (`<AppGroup>/quickfile/snapshot-v1.json`): your memory,
///   plus your own topics and subtopics so it can draw and offer them;
/// - a **240 px thumbnail** of every topic's clay scene
///   (`<AppGroup>/quickfile/art/<id>.jpg`), so its dial's hub has the art
///   without the asset catalogue or a full-size decode.
///
/// There is no history table. History is the bookmarks themselves: your own
/// filings (`filingSource == "user"`) and when they last changed.
@MainActor
enum QuickFileBridge {

    // MARK: History and memory

    /// Your own filings, as the ranking reads them. A guess the app made is
    /// not evidence of what you want, so only `"user"` filings count.
    static func historyItems(_ bookmarks: [Bookmark]) -> [FilingHistoryItem] {
        bookmarks.compactMap { bookmark in
            guard bookmark.deletedAt == nil, bookmark.filingSource == "user",
                  let id = bookmark.categoryID, !id.isEmpty else { return nil }
            return FilingHistoryItem(categoryID: id, subcategory: bookmark.subcategory,
                                     author: bookmark.author, url: bookmark.url, at: bookmark.updatedAt)
        }
    }

    /// Memory from the library. Rebuilt only when the library changes (its
    /// size or its newest edit) or the day turns, so opening the Add sheet or
    /// triage never pays for it twice.
    static func memory(_ bookmarks: [Bookmark], now: Date = .now) -> FilingMemory {
        var newest = Date.distantPast
        for bookmark in bookmarks where bookmark.updatedAt > newest { newest = bookmark.updatedAt }
        let key = MemoKey(count: bookmarks.count, newest: newest,
                          day: FilingParity.seconds(now) / FilingParity.day)
        if let memo, memo.key == key { return memo.memory }
        let built = FilingMemory.build(from: historyItems(bookmarks), now: now)
        memo = (key, built)
        return built
    }

    private struct MemoKey: Equatable {
        let count: Int
        let newest: Date
        let day: Int
    }

    private static var memo: (key: MemoKey, memory: FilingMemory)?

    // MARK: Ranking inputs

    /// What the ranking reads about a saved bork. `ocr` is on-screen text
    /// already through `FilingSuggest.cleanOCR` (`ThumbnailText`).
    static func input(for bookmark: Bookmark, ocr: String?) -> FilingInput {
        FilingInput(url: bookmark.url ?? blank, title: bookmark.title, text: bookmark.text,
                    description: nil, author: bookmark.author, ocrText: ocr)
    }

    private static let blank = URL(string: "about:blank")!

    /// Built-in topics in taxonomy order, then yours by id. The ranking drops
    /// any topic missing from this list, which is how a custom topic you
    /// deleted stops being suggested.
    static func taxonomyOrder(customIDs: [String]) -> [String] {
        Taxonomy.all.map(\.id) + customIDs.sorted { FilingParity.less($0, $1) }
    }

    /// The filing a save already has, to lead the ring: yours if you chose it
    /// (or it predates the distinction), our guess if the app did.
    static func pin(for bookmark: Bookmark) -> FilingPin? {
        guard let id = bookmark.categoryID, Taxonomy.category(id: id) != nil else { return nil }
        return FilingPin(categoryID: id, subcategory: bookmark.subcategory,
                         reason: bookmark.filingSource == "automatic" ? .guess : .yours)
    }

    // MARK: Snapshot for the Share Extension

    /// Coalesces bursts (a drain, a foreground, a triage run) into one write.
    static func scheduleSnapshot(context: ModelContext) {
        pendingSnapshot?.cancel()
        pendingSnapshot = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            refreshSnapshot(context: context)
        }
    }

    private static var pendingSnapshot: Task<Void, Never>?

    /// Rewrites the snapshot the Share Extension ranks from. The rows are read
    /// here, on the main actor that owns the context; folding them into memory
    /// and writing the file happen off it. Losing a write costs one share's
    /// worth of personal suggestions, nothing more.
    static func refreshSnapshot(context: ModelContext) {
        let user: String? = "user"
        let filed = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.deletedAt == nil && $0.filingSource == user })
        let rows: [Row] = ((try? context.fetch(filed)) ?? []).compactMap { bookmark in
            guard let id = bookmark.categoryID, !id.isEmpty else { return nil }
            return Row(categoryID: id, subcategory: bookmark.subcategory, author: bookmark.author,
                       url: bookmark.urlString, at: bookmark.updatedAt)
        }
        let topics = ((try? context.fetch(FetchDescriptor<CustomTopic>())) ?? [])
            .filter { $0.deletedAt == nil }
            .map { SnapshotTopic(id: $0.id, name: $0.name, hue: $0.hue) }
        var subs: [String: [String]] = [:]
        for entry in (try? context.fetch(FetchDescriptor<CustomSubtopic>())) ?? [] where entry.deletedAt == nil {
            subs[entry.categoryID, default: []].append(entry.name)
        }

        Task.detached(priority: .utility) {
            let items = rows.map {
                FilingHistoryItem(categoryID: $0.categoryID, subcategory: $0.subcategory,
                                  author: $0.author, url: URL(string: $0.url), at: $0.at)
            }
            let snapshot = FilingSnapshot(memory: .build(from: items, now: .now),
                                          customTopics: topics,
                                          customSubs: subs.mapValues { $0.sorted() })
            try? snapshot.writeShared()
        }
    }

    private struct Row: Sendable {
        let categoryID: String
        let subcategory: String?
        let author: String?
        let url: String
        let at: Date
    }

    // MARK: Topic art for the Share Extension

    nonisolated private static let artBuildKey = "quickFile.artBuild"
    private static var installingArt = false

    /// Copies every topic's clay scene into the App Group as a 240 px square,
    /// once per build (so redrawn art reaches the extension with the update),
    /// and your own topics' scenes whenever their `topic-art` image changes.
    /// Off the main actor: fifty decodes and encodes is most of a second.
    static func installArtIfNeeded(customTopics: [CustomTopic] = []) {
        guard !installingArt else { return }
        installingArt = true
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let custom: [(id: String, url: URL)] = customTopics.compactMap { topic in
            guard topic.deletedAt == nil, let url = topic.imageURL else { return nil }
            return (topic.id, url)
        }
        let builtIns = Taxonomy.all.map(\.id)

        Task.detached(priority: .utility) {
            let defaults = UserDefaults(suiteName: Store.appGroupID)
            let newBuild = defaults?.string(forKey: artBuildKey) != build
            for id in builtIns where newBuild || !QuickFileArt.hasThumbnail(for: id) {
                guard let scene = UIImage(named: TopicMotif.asset(for: id)) else { continue }
                try? QuickFileArt.install(scene, for: id)
            }
            defaults?.set(build, forKey: artBuildKey)

            for topic in custom {
                let key = "quickFile.art." + topic.id
                guard defaults?.string(forKey: key) != topic.url.absoluteString
                        || !QuickFileArt.hasThumbnail(for: topic.id) else { continue }
                guard let (data, _) = try? await URLSession.shared.data(from: topic.url),
                      let scene = UIImage(data: data) else { continue }
                try? QuickFileArt.install(scene, for: topic.id)
                defaults?.set(topic.url.absoluteString, forKey: key)
            }
            await MainActor.run { installingArt = false }
        }
    }
}
