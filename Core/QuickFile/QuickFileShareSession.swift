import Foundation

/// The Share Extension's half of Quick File as plain logic, so the extension's
/// controller and the app's DEBUG harness run exactly the same thing.
///
/// Tap 1 has already happened by the time this exists: `saved` is the draft
/// the extension enqueued, exactly as it always has. From there:
///
/// - The ranking comes from the snapshot the app leaves in the App Group
///   (`FilingSnapshot`), never from SwiftData, the network, the model or OCR.
/// - When the dial's preselected guess differs from the one `saved` carries
///   (your history with this creator outranks the keywords, say), the inbox
///   file is rewritten once with the dial's guess, still unconfirmed. So
///   "Not now", the drain, or a sheet swiped away all keep what was shown.
/// - Tap 2 rewrites it with the chosen topic as `"user"`, which `Store.save`
///   lets win over any guess. Undo puts the guess back.
///
/// Every write replaces the same inbox file (`Store.enqueue` names it after
/// the bookmark's identity), so the inbox only ever holds the latest answer.
@MainActor
final class QuickFileShareSession {
    let saved: BookmarkDraft
    /// What stays if nothing is filed: `saved`, or `saved` with the dial's guess.
    let kept: BookmarkDraft
    let input: FilingInput
    let model: QuickFileModel
    /// Every topic for More…: the built-ins, then yours A–Z.
    let topics: [Topic]
    private let customSubs: [String: [String]]
    private let enqueue: (BookmarkDraft) throws -> Void

    init(saved: BookmarkDraft, snapshot: FilingSnapshot?, now: Date = .now,
         enqueue: @escaping (BookmarkDraft) throws -> Void) {
        let custom = (snapshot?.customTopics ?? []).map(\.asTopic)
        if !custom.isEmpty { Taxonomy.installCustomTopics(custom) }
        let order = Taxonomy.all.map(\.id) + custom.map(\.id).sorted { FilingParity.less($0, $1) }
        let input = FilingInput(url: saved.url, title: saved.title, text: saved.text,
                                description: nil, author: saved.author, ocrText: nil)
        let ranking = FilingSuggest.rank(input, memory: snapshot?.memory ?? .empty, taxonomyOrder: order, now: now)

        var kept = saved
        if ranking.preselect != nil, let best = ranking.candidates.first,
           best.categoryID != saved.categoryID || best.subcategory != saved.subcategory {
            kept.categoryID = best.categoryID
            kept.subcategory = best.subcategory
            try? enqueue(kept)
        }

        self.saved = saved
        self.kept = kept
        self.input = input
        self.topics = Taxonomy.all + custom.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        self.customSubs = snapshot?.customSubs ?? [:]
        self.enqueue = enqueue
        self.model = QuickFileModel(ranking: ranking, input: input)

        QuickFileArt.preload(ranking.candidates.map(\.categoryID))
        model.onConfirm = { [weak self] candidate in self?.file(candidate) }
        model.onUndo = { [weak self] _ in self?.unfile() }
    }

    var title: String { saved.title }

    /// "TikTok · @kaylawalks", or the site for a web page.
    var platformName: String {
        let platform = saved.platform ?? Platform.detect(from: saved.url)
        if platform == .web { return FilingKeys.domain(url: saved.url) ?? platform.name }
        guard let creator = FilingKeys.creatorLabel(author: saved.author, url: saved.url) else { return platform.name }
        return "\(platform.name) · \(creator)"
    }

    /// A topic's subtopics as the app's picker lists them: built-in and
    /// yours in one A–Z run (`MergedTaxonomy.subs`, from the snapshot).
    func subs(for topic: Topic) -> [String] {
        let yours = (customSubs[topic.id] ?? []).filter { name in
            !topic.subs.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        return TopicPickerQuery.alphabetical(topic.subs + yours)
    }

    private func file(_ candidate: FilingCandidate) {
        var draft = saved
        draft.categoryID = candidate.categoryID
        draft.subcategory = candidate.subcategory
        draft.filingSource = "user"
        try? enqueue(draft)
    }

    private func unfile() {
        try? enqueue(kept)
    }
}
