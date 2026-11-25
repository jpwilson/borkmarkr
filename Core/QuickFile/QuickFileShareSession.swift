import Foundation

/// The Share Extension's half of Quick File as plain logic, so the extension's
/// controller and the app's DEBUG harness run exactly the same thing.
///
/// Tap 1 has already happened by the time this exists: `saved` is the draft
/// the extension enqueued, exactly as it always has. From there:
///
/// - The ranking comes from the snapshot the app leaves in the App Group
///   (`FilingSnapshot`), never from SwiftData or OCR.
/// - When the dial's preselected guess differs from the one `saved` carries
///   (your history with this creator outranks the keywords, say), the inbox
///   file is rewritten once with the dial's guess, still unconfirmed. So
///   "Not now", the drain, or a sheet swiped away all keep what was shown.
/// - Signed in, `enrich` reads the page and asks the model while the dial is
///   up, by the Add sheet's rules. Each answer re-ranks the dial, and the
///   guess that stays follows it, still unconfirmed.
/// - Tap 2 chooses: the inbox file is rewritten with the chosen topic as
///   `"user"`, which `Store.save` lets win over any guess, and the sheet
///   stays for the refine panel. Another topic, a subtopic chip or a tag
///   rewrites it again. Late answers keep coming while it is up; they never
///   move a choice, but their subtopics and tags reach the panel.
///
/// Every write replaces the same inbox file (`Store.enqueue` names it after
/// the bookmark's identity), so the inbox only ever holds the latest answer.
/// Each one is composed whole (`current()`): what stays, the choice over it,
/// and the tags.
@MainActor
final class QuickFileShareSession {
    let saved: BookmarkDraft
    /// What stays if nothing is filed: `saved`, or `saved` with the dial's
    /// guess, and then whatever the page and the model added.
    private(set) var kept: BookmarkDraft
    private(set) var input: FilingInput
    let model: QuickFileModel
    /// The save's tags while the sheet is up: the Categorizer's, then the
    /// model's, and whatever the person turns on, off or types.
    let tags: QuickFileTags
    /// What was chosen on the dial, if anything. It wins over `kept`'s filing.
    private(set) var chosen: FilingCandidate?
    /// Where the refine panel's lists come from: the snapshot.
    let refineSource: QuickFileRefineSource
    /// Every topic for More…: the built-ins, then yours A–Z.
    let topics: [Topic]
    /// The sheet has gone. Nothing more is written.
    private(set) var closed = false
    private let memory: FilingMemory
    private let order: [String]
    /// Every ranking on this sheet is made as of this moment, so a re-deal
    /// only ever reflects what arrived.
    private let rankedAt: Date
    private let customSubs: [String: [String]]
    private let enqueue: (BookmarkDraft) throws -> Void
    /// The last draft written, so closing writes only if something changed.
    private var written: BookmarkDraft?
    private var enriching: Task<Void, Never>?

    init(saved: BookmarkDraft, snapshot: FilingSnapshot?, now: Date = .now,
         enqueue: @escaping (BookmarkDraft) throws -> Void) {
        let custom = (snapshot?.customTopics ?? []).map(\.asTopic)
        if !custom.isEmpty { Taxonomy.installCustomTopics(custom) }
        let order = Taxonomy.all.map(\.id) + custom.map(\.id).sorted { FilingParity.less($0, $1) }
        let memory = snapshot?.memory ?? .empty
        let input = FilingInput(url: saved.url, title: saved.title, text: saved.text,
                                description: nil, author: saved.author, ocrText: nil)
        let ranking = FilingSuggest.rank(input, memory: memory, taxonomyOrder: order, now: now)

        // Tap 1 enqueued `saved` already.
        var kept = saved
        if let guess = Self.refiled(saved, by: ranking) {
            kept = guess
            try? enqueue(kept)
        }

        self.saved = saved
        self.kept = kept
        self.input = input
        self.memory = memory
        self.order = order
        self.rankedAt = now
        self.topics = Taxonomy.all + custom.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let customSubs = snapshot?.customSubs ?? [:]
        self.customSubs = customSubs
        self.enqueue = enqueue
        self.written = kept
        self.model = QuickFileModel(ranking: ranking, input: input, mode: .refine)
        self.tags = QuickFileTags(chosen: saved.tags, suggested: saved.tags)
        let subUse = snapshot?.subUse ?? [:]
        let recent = snapshot?.recentTags ?? [:]
        self.refineSource = QuickFileRefineSource(
            subs: { id in Self.subs(of: id, custom: customSubs) },
            used: { subUse[$0] ?? [] },
            recentTags: { QuickFileRefine.recentTags(in: recent, categoryID: $0, subcategory: $1) }
        )

        QuickFileArt.preload(ranking.candidates.map(\.categoryID))
        model.onConfirm = { [weak self] candidate in self?.file(candidate) }
        tags.onChange = { [weak self] in self?.write() }
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
        Self.subs(of: topic, custom: customSubs)
    }

    private static func subs(of topic: Topic, custom: [String: [String]]) -> [String] {
        let yours = (custom[topic.id] ?? []).filter { name in
            !topic.subs.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        return TopicPickerQuery.alphabetical(topic.subs + yours)
    }

    private static func subs(of topicID: String, custom: [String: [String]]) -> [String] {
        guard let topic = Taxonomy.category(id: topicID) else {
            return TopicPickerQuery.alphabetical(custom[topicID] ?? [])
        }
        return subs(of: topic, custom: custom)
    }

    // MARK: Late answers

    /// Starts `enrich` behind the dial, once, when there is someone to ask
    /// as (`SessionKeychain.caller`). `close()` stops it.
    func startEnriching(with caller: Supabase.Caller?) {
        guard let caller, enriching == nil, !closed else { return }
        enriching = Task { await enrich(caller: caller) }
    }

    /// The sheet is going: a tag still in the field is kept, then nothing
    /// more is asked or written.
    func close() {
        guard !closed else { return }
        tags.commitDraft()
        write()
        closed = true
        enriching?.cancel()
    }

    /// Behind the dial, signed in: the page (`read`, at most 2.5 seconds),
    /// then, whenever the post has words of its own, the model (`judge`, at
    /// most 6.5 seconds), however sure the ranking already is: every save
    /// made by hand gets its judgement once, as one more piece of evidence.
    /// The Add sheet's rules: every answer reaches the dial through `offer`;
    /// the page changes what stays only while the dial is untouched, the
    /// model's answer touched or not; a choice made meanwhile wins over both
    /// (`current()`), and the answer's tags join the panel's (`QuickFileTags.
    /// suggest`). It keeps asking after a choice, for the panel's subtopics
    /// and tags. The answer settles the save (so does a page
    /// that leaves the ranking sure when there are no words to ask about):
    /// the page's findings go with it, marked as read, so `PreviewFetcher`
    /// doesn't read and ask again as soon as the app opens. A question the
    /// sheet closes on leaves the save unsettled, for `PreviewFetcher` to
    /// ask when the app next opens. No network with no server configured;
    /// signed out, there is no one to call this as.
    func enrich(
        caller: Supabase.Caller,
        read: @Sendable (URL) async -> LinkPreview.Result? = {
            await LinkPreview.fetch(for: $0, within: .milliseconds(2500))
        },
        judge: @Sendable (SmartCategorizer.Context, Supabase.Caller) async -> Categorizer.Suggestion? = {
            await SmartCategorizer.suggest($0, caller: $1, within: .milliseconds(6500))
        }
    ) async {
        guard Supabase.isConfigured, !closed else { return }

        let page = await read(saved.url)
        guard !closed else { return }
        if let page {
            input = Self.input(saved, reading: page)
            let ranking = rank()
            reoffer(ranking)
            let guess = model.touched ? nil : Self.refiled(kept, by: ranking)
            let next = guess ?? kept
            // Nothing for the model to read, sure without it, and that is
            // what stays: settled, and the page goes too.
            if !Self.hasWords(input), ranking.evidence == .strong, Self.refiled(next, by: ranking) == nil {
                return keep(Self.reading(page, into: next))
            }
            if let guess { keep(guess) }
        }

        guard !closed, Self.hasWords(input) else { return }
        let request = SmartCategorizer.Context(url: input.url, title: input.title, author: input.author,
                                               text: input.text, description: input.description)
        model.isAsking = true
        let answer = await judge(request, caller)
        model.isAsking = false
        guard let answer, !closed else { return }
        let answered = rank(ai: answer)
        reoffer(answered)
        var next = Self.refiled(kept, by: answered) ?? kept
        tags.suggest(answer.tags)
        if let page { next = Self.reading(page, into: next) }
        // Settled even when the page ran out of time, or `PreviewFetcher`
        // would ask again as soon as the app opens. Its usual retry reads
        // the page an hour later.
        next.previewFetched = true
        keep(next)
    }

    private func rank(ai: Categorizer.Suggestion? = nil) -> FilingRanking {
        FilingSuggest.rank(input, memory: memory, ai: ai, taxonomyOrder: order, now: rankedAt)
    }

    /// An untouched dial re-deals; a touched one only gains a ✨ or an
    /// "Also likely" chip.
    private func reoffer(_ ranking: FilingRanking) {
        QuickFileArt.preload(ranking.candidates.map(\.categoryID))
        model.offer(ranking, input: input)
    }

    /// What stays becomes `draft`, with any choice over it. Nothing once the
    /// sheet has closed.
    private func keep(_ draft: BookmarkDraft) {
        guard !closed else { return }
        kept = draft
        write()
    }

    // MARK: Filing

    private func file(_ candidate: FilingCandidate) {
        chosen = candidate
        write()
    }

    /// The draft as it stands: what stays, the choice over it as `"user"`,
    /// and the tags. Tags the person touched replace the bork's, less any
    /// they turned off (`tagsRemoved`, since the extension can't see the
    /// bork's own).
    func current() -> BookmarkDraft {
        var draft = kept
        if let chosen {
            draft.categoryID = chosen.categoryID
            draft.subcategory = chosen.subcategory
            draft.filingSource = "user"
        }
        draft.tags = tags.chosen
        if tags.edited {
            draft.tagsEdited = true
            draft.tagsRemoved = tags.removed
        }
        return draft
    }

    /// Rewrites the inbox file, unless nothing changed since the last write.
    private func write() {
        guard !closed else { return }
        let draft = current()
        if let written, Self.same(written, draft) { return }
        try? enqueue(draft)
        written = draft
    }

    // MARK: Rules

    /// `draft` under the ranking's guess; nil when it offers none or `draft`
    /// is already there.
    private static func refiled(_ draft: BookmarkDraft, by ranking: FilingRanking) -> BookmarkDraft? {
        guard ranking.preselect != nil, let best = ranking.candidates.first,
              best.categoryID != draft.categoryID || best.subcategory != draft.subcategory else { return nil }
        var draft = draft
        draft.categoryID = best.categoryID
        draft.subcategory = best.subcategory
        return draft
    }

    /// Words someone wrote about the post (a caption, a post, the page's own
    /// title or description), not just a title made from the link. Instagram
    /// usually has none: a bare link, and a login wall where the page is.
    private static func hasWords(_ input: FilingInput) -> Bool {
        (!Categorizer.isDerivedTitle(input.title, for: input.url) && !Platform.isSiteName(input.title))
            || SavedContent.excerpt(input.text) != nil
            || SavedContent.excerpt(input.description) != nil
    }

    /// What the dial ranks once the page is read: `reading`'s title and
    /// creator, and the page's description.
    private static func input(_ saved: BookmarkDraft, reading page: LinkPreview.Result) -> FilingInput {
        let read = reading(page, into: saved)
        return FilingInput(url: saved.url, title: read.title, text: saved.text,
                           description: page.description, author: read.author, ocrText: nil)
    }

    /// The page's findings on `draft`, by the rules the Add sheet's
    /// `writePreview` saves them under (`Store.save`'s merge): a fetched
    /// title replaces only one made from the link, a real creator only a
    /// placeholder. Marked as read, so `PreviewFetcher` leaves it for now.
    private static func reading(_ page: LinkPreview.Result, into draft: BookmarkDraft) -> BookmarkDraft {
        var draft = draft
        let platform = draft.platform ?? Platform.detect(from: draft.url)
        if let title = page.title, !title.isEmpty, draft.titleEdited != true,
           Categorizer.isDerivedTitle(draft.title, for: draft.url) {
            draft.title = title
        }
        if let author = page.author,
           !Bookmark.isPlaceholderAuthor(author, url: draft.url, platform: platform),
           Bookmark.isPlaceholderAuthor(draft.author, url: draft.url, platform: platform) {
            draft.author = author
        }
        if let text = SavedContent.excerpt(page.description) { draft.text = text }
        if let seconds = page.durationSeconds { draft.durationSeconds = seconds }
        if let image = page.imageURL { draft.imageURLString = image.absoluteString }
        if let posted = page.publishedAt { draft.postedAt = posted }
        draft.previewFetched = true
        return draft
    }

    private static func same(_ a: BookmarkDraft, _ b: BookmarkDraft) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let left = try? encoder.encode(a), let right = try? encoder.encode(b) else { return false }
        return left == right
    }
}
