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
            VStack(alignment: .leading, spacing: 14) {
                hero
                if !presentSubs.isEmpty { subRow }
                if presentSources.count > 1 { sourceRow }
                if !refineTags.isEmpty { refineRow }
                list
            }
            .padding(.bottom, 120)
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

    // MARK: Hero band

    /// The tile you tapped, opened out.
    ///
    /// The old header was a flat tint gradient with the name on it, which
    /// meant every topic page looked like every other topic page and none of
    /// them looked like the tile that got you there. This is the tile's own
    /// composition at full width — clay scene on top, name and count on the
    /// topic's tint underneath — so arriving feels like a continuation rather
    /// than a jump. Deliberately compact: two chip rows' worth, which keeps
    /// the first bork above the fold on the smallest phone we support.
    ///
    /// The text block is below the art, not over it, so Dynamic Type grows the
    /// band instead of overflowing a fixed-height image, and nothing ever sits
    /// on top of a busy scene at a contrast we can't predict.
    private var hero: some View {
        VStack(spacing: 0) {
            TopicClayArt(
                categoryID: category.id,
                remote: customEntry?.imageURL,
                fallbackTint: category.palette.tint
            )
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .clipped()
            .overlay(alignment: .topTrailing) {
                shareControl
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(currentName)
                        .font(Typo.display(26, .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(category.palette.deep)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if let entry = customEntry {
                        Button {
                            renameDraft = entry.name
                            renaming = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(category.palette.deep.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rename this topic")
                    }
                    Spacer(minLength: 0)
                }
                Text(Copy.countedBorks(inCategory.count))
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(category.palette.deep.opacity(0.75))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(category.palette.tint)
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
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                Text("Share").font(Typo.ui(12.5, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Tokens.ink, in: Capsule())
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

    private var subRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                pill("All", active: sub == nil, tint: category.palette) {
                    sub = nil; tag = nil
                }
                ForEach(presentSubs, id: \.name) { entry in
                    pill("\(entry.name) \(entry.count)", active: sub == entry.name, tint: category.palette) {
                        // Picking a subcategory clears the tag — the tag was
                        // scoped to the previous slice and would filter to zero.
                        sub = sub == entry.name ? nil : entry.name
                        tag = nil
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FROM")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    pill("All", active: source == nil, tint: category.palette) { source = nil }
                    ForEach(presentSources, id: \.self) { platform in
                        pill(platform.name, active: source == platform, tint: category.palette) {
                            source = source == platform ? nil : platform
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var refineRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REFINE")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(refineTags, id: \.self) { candidate in
                        let active = tag == candidate
                        Button {
                            tag = active ? nil : candidate
                        } label: {
                            Text("#\(candidate)")
                                .font(Typo.ui(12, .semibold))
                                .foregroundStyle(active ? .white : category.palette.deep)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(active ? category.palette.deep : .clear, in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        category.palette.deep.opacity(active ? 0 : 0.45),
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                    )
                                )
                                .tappableChip()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Tokens.inkFaint)
                Text("Nothing in this slice")
                    .font(Typo.ui(14, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
        } else {
            LazyVStack(spacing: 9) {
                ForEach(visible) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func pill(_ label: String, active: Bool, tint: CategoryPalette, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(Typo.ui(12.5, .semibold))
                .foregroundStyle(active ? .white : tint.deep)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? tint.deep : tint.tint, in: Capsule())
                .tappableChip()
        }
        .buttonStyle(.plain)
    }
}

/// Saves with no category. Reachable so they don't become the exact black hole
/// the app exists to prevent.
struct UncategorisedPage: View {
    @Environment(\.accent) private var accent
    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @State private var detail: Bookmark?

    private var visible: [Bookmark] { all.filter { $0.categoryID == nil } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                ForEach(visible) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .background(Tokens.paper)
        .navigationTitle("Not filed yet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
    }
}
