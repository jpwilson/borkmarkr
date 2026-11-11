import SwiftUI
import SwiftData

/// Topic page: hero band, subcategory chips, cross-axis source chips, and
/// "Refine" tag chips that act as the third taxonomy level.
struct TopicPage: View {
    let category: Topic

    @Environment(\.accent) private var accent
    /// Injected by RootView; this page is pushed by Browse and has no
    /// `account` of its own. Only "Share as a web page" needs it.
    @Environment(\.account) private var account
    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]
    @Environment(\.modelContext) private var context
    @State private var renameDraft = ""
    @State private var renaming = false
    @State private var collecting = false

    @State private var sub: String?
    @State private var source: Platform?
    @State private var tag: String?
    @State private var detail: Bookmark?
    /// The rendered share card. Built off the main flow when the slice
    /// changes, so the share menu never waits on `ImageRenderer`.
    @State private var cardImage: Image?

    private var inCategory: [Bookmark] {
        all.filter { $0.categoryID == category.id }
    }

    /// The row behind a topic you made yourself, if this is one.
    private var customEntry: CustomTopic? {
        customTopics.first { $0.id == category.id }
    }

    /// A custom topic can have been renamed since `category` was built.
    private var currentName: String { customEntry?.name ?? category.name }

    private var visible: [Bookmark] {
        inCategory.filter { item in
            if let sub, item.subcategory != sub { return false }
            if let source, item.platform != source { return false }
            if let tag, !item.tags.contains(tag) { return false }
            return true
        }
    }

    /// Includes subtopics you added yourself, so a custom one you filed into
    /// shows up here rather than vanishing from the chips. A–Z, in one list
    /// with the built-ins — `MergedTaxonomy.subs(for:)` does the ordering, so
    /// these chips and the picker's pills can never disagree. (The counts on
    /// the chips are information, not the sort key: ordering *by* count would
    /// make the row jump around as you save.)
    private var presentSubs: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: inCategory.compactMap(\.subcategory)) { $0 }.mapValues(\.count)
        let merged = MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
        return merged.subs(for: category).compactMap { name in
            counts[name].map { (name, $0) }
        }
    }

    private var presentSources: [Platform] {
        let used = Set(inCategory.map(\.platform))
        return Platform.ordered.filter { used.contains($0) }
    }

    /// Tags with ≥2 items in the current subcategory slice, top 6 — the spec's
    /// rule for when Refine is worth showing.
    private var refineTags: [String] {
        guard sub != nil else { return [] }
        let scope = inCategory.filter { $0.subcategory == sub }
        let counts = Dictionary(grouping: scope.flatMap(\.tags)) { $0 }.mapValues(\.count)
        return counts.filter { $0.value >= 2 }
            .sorted {
                $0.value == $1.value
                    ? $0.key.localizedStandardCompare($1.key) == .orderedAscending
                    : $0.value > $1.value
            }
            .prefix(6)
            .map(\.key)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                titleRow
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.top, 16)
                if !presentSubs.isEmpty {
                    subRow.padding(.top, 12)
                }
                if presentSources.count > 1 {
                    sourceRow.padding(.top, 8)
                }
                if !refineTags.isEmpty {
                    refineRow.padding(.top, 8)
                }
                list
                    .padding(.top, 12)
            }
            .padding(.bottom, Tokens.sectionGap)
        }
        .background(Tokens.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { EmptyView() }
        }
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
        .sheet(isPresented: $collecting) {
            CollectSheet(
                bookmarks: visible,
                presetName: shareHeading,
                categoryID: category.id,
                account: account
            )
            .environment(\.accent, accent)
        }
        .task(id: cardKey) { await buildShareCard() }
        .alert("Rename topic", isPresented: $renaming) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                if let entry = customTopics.first(where: { $0.id == category.id }) {
                    Store.renameTopic(entry, to: renameDraft, in: context)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Banner and title

    /// The tile you tapped, opened out: its clay scene as a short banner on
    /// the clay ground, about 120 pt — enough to say which topic this is and
    /// keep the first bork above the fold on the smallest phone.
    ///
    /// No colour band (1.4). The name sits under the art on paper, so Dynamic
    /// Type grows the page instead of overflowing an image, and nothing ever
    /// sits on top of a busy scene at a contrast we can't predict.
    private var banner: some View {
        Tokens.clayGround
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .overlay {
                TopicClayArt(categoryID: category.id, remote: customEntry?.imageURL)
            }
            .clipped()
            .accessibilityHidden(true)
    }

    /// Bricolage title and the count, with Share (and Rename, for a topic you
    /// made) at the right.
    private var titleRow: some View {
        ScreenHeader(currentName, subtitle: Copy.countedBorks(inCategory.count)) {
            HStack(spacing: 4) {
                if let entry = customEntry {
                    Button {
                        renameDraft = entry.name
                        renaming = true
                    } label: {
                        BrowseRoundIcon(symbol: "pencil")
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Rename this topic")
                }
                shareControl
            }
            .padding(.trailing, -4)
        }
    }

    // MARK: Share

    /// Three ways to hand this topic to somebody, on the button that was
    /// always here. Links for a person who will tap them; a picture for a
    /// story or a group chat, where nothing is tappable and the job is to be
    /// worth asking about; and one link to a page with the whole slice on it,
    /// for when ten titles in a message is not the point and all of it is.
    /// The card is only offered once it has rendered — a share sheet that
    /// stalls on an image is worse than one that offers a link.
    private var shareControl: some View {
        Menu {
            ShareLink(item: shareMessage, subject: Text(shareHeading)) {
                Label("Share links", systemImage: "link")
            }
            if let cardImage {
                ShareLink(
                    item: cardImage,
                    subject: Text(shareHeading),
                    preview: SharePreview(shareHeading, image: cardImage)
                ) {
                    Label("Share as image", systemImage: "photo")
                }
            }
            Divider()
            // "Share as a web page", not "Share as a link": "Share links" is
            // two items up, and two entries with "link" in them say nothing
            // about the difference. This one makes bookmarker.lol/c/… — a page.
            Button { collecting = true } label: {
                Label("Share as a web page…", systemImage: "link.badge.plus")
            }
            .disabled(visible.isEmpty)
        } label: {
            BrowseRoundIcon(symbol: "square.and.arrow.up")
        }
        .accessibilityLabel("Share this topic")
    }

    /// Named for where you are: "Fitness › Mobility".
    private var shareHeading: String {
        TopicShare.heading(topic: currentName, subtopic: sub)
    }

    /// The current slice as share items. Titles and URLs only — a bork's
    /// `text` (an X thread's body, an Instagram caption) never leaves here.
    private var shareItems: [TopicShare.Item] {
        visible.map {
            TopicShare.Item(title: $0.displayTitle, url: $0.urlString, savedAt: $0.savedAt)
        }
    }

    private var shareMessage: String {
        TopicShare.message(topic: currentName, subtopic: sub, items: shareItems)
    }

    /// Re-render when the slice, the name or the size of the topic changes —
    /// not on every redraw.
    private var cardKey: String {
        "\(currentName)|\(sub ?? "")|\(source?.rawValue ?? "")|\(tag ?? "")|\(visible.count)"
    }

    @MainActor
    private func buildShareCard() async {
        let titles = TopicShare.newestFirst(shareItems)
            .prefix(TopicShare.cardLimit)
            .map { TopicShare.shortTitle($0.title, limit: 52) }

        var art = UIImage(named: TopicMotif.asset(for: category.id))
        if art == nil, let url = customEntry?.imageURL {
            // Almost always a URLCache hit: the hero band above has already
            // asked for the same image. A miss just means a card with the
            // topic's tint instead of its scene.
            art = await Self.loadArt(url)
        }

        let renderer = ImageRenderer(content: TopicShareCard(
            topic: category,
            name: currentName,
            subtopic: sub,
            count: visible.count,
            titles: titles,
            art: art
        ))
        renderer.scale = TopicShareCard.scale
        renderer.proposedSize = ProposedViewSize(TopicShareCard.size)

        guard let rendered = renderer.uiImage else { return }
        cardImage = Image(uiImage: rendered)

        #if DEBUG
        // `-dumpShareCard <path>`: the only way to capture the card, since it
        // is a rendered image rather than a screen. See ScreenshotDefaults.
        if let path = ScreenshotDefaults.shareCardDumpPath, let data = rendered.pngData() {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        #endif
    }

    private static func loadArt(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    /// Subtopics in the topic's own tint and deep; the chosen one filled.
    private var subRow: some View {
        BrowseChipRow {
            TopicChip("All", palette: category.palette, isOn: sub == nil) {
                sub = nil; tag = nil
            }
            ForEach(presentSubs, id: \.name) { entry in
                TopicChip("\(entry.name) \(entry.count)", palette: category.palette, isOn: sub == entry.name) {
                    // Picking a subcategory clears the tag — the tag was
                    // scoped to the previous slice and would filter to zero.
                    sub = sub == entry.name ? nil : entry.name
                    tag = nil
                }
            }
        }
    }

    /// Where they came from — neutral filter chips, so the topic's colour
    /// stays the topic's.
    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            BrowseChipLabel("From")
            BrowseChipRow {
                FilterChip("All", isOn: source == nil) { source = nil }
                ForEach(presentSources, id: \.self) { platform in
                    FilterChip(platform.name, isOn: source == platform) {
                        source = source == platform ? nil : platform
                    }
                }
            }
        }
    }

    private var refineRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            BrowseChipLabel("Refine")
            BrowseChipRow {
                ForEach(refineTags, id: \.self) { candidate in
                    let active = tag == candidate
                    TagChip(candidate, isOn: active, size: .filter) {
                        tag = active ? nil : candidate
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            Text("Nothing in this slice")
                .textRole(.body, color: Tokens.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(visible) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .borkActions(bookmark)
                }
            }
            .padding(.horizontal, Tokens.gutter)
        }
    }
}

// MARK: - Shared bits (topic, unfiled and source pages)

/// A sideways-scrolling row of chips that starts at the gutter and runs to
/// the screen's edge.
struct BrowseChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
                .padding(.horizontal, Tokens.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// The small-caps label over a chip row ("FROM", "REFINE").
struct BrowseChipLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textRole(.label, color: Tokens.inkSecondary)
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A 36 pt white circle with a hairline and an ink glyph, in a 44 pt
/// target: Share and Rename beside a page title.
struct BrowseRoundIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Tokens.ink)
            .frame(width: 36, height: 36)
            .background(Tokens.surface, in: Circle())
            .overlay(Circle().strokeBorder(Tokens.hairline, lineWidth: 1))
            .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
            .contentShape(Rectangle())
    }
}

/// Saves with no category. Reachable so they don't become the exact black hole
/// the app exists to prevent.
struct UncategorisedPage: View {
    @Environment(\.accent) private var accent
    /// For the model's help in triage; injected by RootView.
    @Environment(\.account) private var account
    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @State private var detail: Bookmark?
    @State private var sorting = false

    private var visible: [Bookmark] { all.filter { $0.categoryID == nil } }

    /// The topic page's layout on Sand: a title on paper with the count, the
    /// one slim row that sorts them all, then the rows.
    var body: some View {
        let visible = self.visible
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("Not filed yet", subtitle: Copy.countedBorks(visible.count))
                    .padding(.top, 8)
                if !visible.isEmpty {
                    // "Sort these": the whole list, one tap each, instead of
                    // opening every bork to pick its topic.
                    SlimActionRow(
                        art: .quest(.compass),
                        title: "\(visible.count) without a topic",
                        subtitle: "Give each a home in one tap",
                        action: "Sort",
                        perform: { sorting = true }
                    )
                    .padding(.top, 16)
                    LazyVStack(spacing: 8) {
                        ForEach(visible) { bookmark in
                            Button { detail = bookmark } label: {
                                BookmarkRow(bookmark: bookmark)
                            }
                            .buttonStyle(PressableStyle(scale: 0.99))
                            .borkActions(bookmark)
                        }
                    }
                    .padding(.top, 16)
                } else {
                    Text("Everything has a topic.")
                        .textRole(.body, color: Tokens.inkSecondary)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, Tokens.sectionGap)
        }
        .background(Tokens.paper)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
        .sheet(isPresented: $sorting) {
            TriageSheet(deck: .unfiled, account: account)
                .environment(\.accent, accent)
        }
    }
}
