import SwiftUI
import SwiftData
import StoreKit

/// The IA spine: two browse axes that cross. Topics lead to a topic page with
/// source chips; Sources lead to a source page with topic chips. Either axis
/// can lead and the other is always available as a secondary filter.
struct BrowseView: View {
    let interests: [String]
    @Binding var pendingTopic: String?
    /// Set by the Library's search row: switch to Browse *and* put the caret
    /// in the field, so the tap lands where the user was aiming.
    @Binding var focusSearch: Bool
    var account: Account? = nil

    @Environment(\.accent) private var accent
    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var context
    @AppStorage("browseAxis") private var axisRaw = Axis.topics.rawValue
    // One per segment. Ordering topics by count while ordering sources A–Z is
    // a perfectly reasonable thing to want, and a single shared setting would
    // make picking one silently repick the others.
    @AppStorage(BrowseSort.Key.topics) private var topicSortRaw = BrowseSort.fallback.rawValue
    @AppStorage(BrowseSort.Key.sources) private var sourceSortRaw = BrowseSort.fallback.rawValue
    @AppStorage(BrowseSort.Key.journeys) private var questSortRaw = BrowseSort.fallback.rawValue
    @State private var path = NavigationPath()
    /// `-topic <id>` is consumed once, not on every reappearance.
    @State private var openedLaunchTopic = false
    /// Zooms the tapped tile into the topic page's hero band on iOS 18+.
    @Namespace private var tileZoom

    // Search, hosted here since 1.1 — see `BrowseSearch.swift`.
    @State private var query = ScreenshotDefaults.searchQuery
    @State private var debounced = ScreenshotDefaults.searchQuery
    @State private var scopes: SearchScope = ScreenshotDefaults.searchScopes
    @State private var sources: Set<Platform> = []
    @State private var detail: Bookmark?
    @FocusState private var searchFocused: Bool
    @StateObject private var semantic = SemanticIndex()
    @State private var related: [SemanticIndex.Hit] = []

    enum Axis: String, CaseIterable {
        case topics, sources, journeys
        var title: String {
            switch self {
            case .topics: "Topics"
            case .sources: "Sources"
            case .journeys: "Side quests"
            }
        }
    }

    private var axis: Axis {
        get { Axis(rawValue: axisRaw) ?? .topics }
        nonmutating set { axisRaw = newValue.rawValue }
    }

    /// The sort for whichever segment is showing. Reading and writing through
    /// one property is what keeps the chip row from having to know which of
    /// the three defaults keys it is editing.
    private var sort: BrowseSort {
        get {
            switch axis {
            case .topics: BrowseSort.named(topicSortRaw)
            case .sources: BrowseSort.named(sourceSortRaw)
            case .journeys: BrowseSort.named(questSortRaw)
            }
        }
        nonmutating set {
            switch axis {
            case .topics: topicSortRaw = newValue.rawValue
            case .sources: sourceSortRaw = newValue.rawValue
            case .journeys: questSortRaw = newValue.rawValue
            }
        }
    }

    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var bookmarks: [Bookmark]

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    @State private var showingPicker = false
    @State private var pickerCategory: String?
    @State private var pickerSub: String?

    private var merged: MergedTaxonomy {
        MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
    }

    private enum Route: Hashable {
        case topic(String)
        case source(Platform)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("Browse")
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.top, 4)

                BrowseSearchBar(
                    query: $query,
                    scopes: $scopes,
                    focus: $searchFocused,
                    isSearching: isSearching,
                    onCancel: clearSearch
                )
                .padding(.top, 16)

                if isSearching {
                    ScrollView {
                        BrowseSearchResults(
                            results: results,
                            query: debounced,
                            scopes: scopes,
                            sources: $sources,
                            presentPlatforms: presentPlatforms,
                            related: related,
                            onOpen: open,
                            onClearScopes: { scopes = [] }
                        )
                        .padding(.top, 6)
                        .padding(.bottom, Tokens.sectionGap)
                    }
                    .scrollDismissesKeyboard(.immediately)
                } else {
                    segmented
                        .padding(.top, 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            listHeader
                            switch axis {
                            case .topics: topicsGrid
                            case .sources: sourcesList
                            case .journeys: MissionsView(account: account, sort: sort)
                            }
                        }
                        .padding(.top, 14)
                        .padding(.bottom, Tokens.sectionGap)
                    }
                }
            }
            .background(Tokens.paper)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .topic("__uncategorised__"):
                    UncategorisedPage()
                case .topic(let categoryID):
                    if let category = merged.topic(id: categoryID) {
                        TopicPage(category: category)
                            .zoomedFrom(id: categoryID, in: tileZoom)
                    }
                case .source(let platform):
                    SourcePage(platform: platform)
                }
            }
            .sheet(isPresented: $showingPicker) {
                TopicPickerSheet(categoryID: $pickerCategory, subcategory: $pickerSub)
                    .environment(\.accent, accent)
            }
            .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
        }
        .onChange(of: pendingTopic) { _, value in
            guard let value else { return }
            axis = .topics
            clearSearch()
            path.append(Route.topic(value))
            pendingTopic = nil
        }
        // Both, deliberately. Switching tabs *replaces* this view rather than
        // revealing it, so a request made in the same gesture as the tab
        // change arrives already-true and `onChange` never fires; a request
        // made while Browse is already on screen never appears again.
        .onAppear {
            consumeFocusRequest()
            consumeLaunchTopic()
        }
        .onChange(of: focusSearch) { _, _ in consumeFocusRequest() }
        .task(id: query) {
            // Debounce: wait out the typist, then commit.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            debounced = query
            updateRelated()
        }
        // Keyed on which topics exist, not on which have art. Creating a
        // topic re-fires this — which is what makes a brand new topic draw
        // itself immediately, from any of the four sheets that can create
        // one, without threading an Account through all of them. Art landing
        // does not change the key, so the task doesn't restart itself.
        .task(id: customTopics.map(\.id).joined(separator: ",")) {
            await fillMissingTopicArt()
        }
    }

    /// Draw the topics that never got a scene.
    ///
    /// A few at a time, oldest first — see `TopicArt.backfillBatch`. The
    /// server refuses to spend twice on the same topic, so the cost of being
    /// wrong here is a wasted round trip, not a wasted image. Nothing on
    /// screen waits for this: tiles render as paper meanwhile, exactly as
    /// they do today, and each one fills in as its URL lands.
    private func fillMissingTopicArt() async {
        let wanted = TopicArt.backfillOrder(
            customTopics,
            id: \.id, hasArt: { $0.imageURLString != nil },
            requestedAt: \.artRequestedAt, created: \.createdAt
        )
        guard !wanted.isEmpty else { return }

        let session = await account?.currentSession()
        guard session != nil else { return }

        for topic in wanted {
            guard !Task.isCancelled else { return }
            let outcome = await TopicArt.fetchOutcome(id: topic.id, name: topic.name, session: session)
            // Stamped whether or not it worked — that is what stops a topic
            // the server has given up on being asked again every visit. A
            // failure that can recover comes back within the hour.
            topic.artRequestedAt = TopicArt.requestStamp(reason: outcome.reason)
            if let url = outcome.url { topic.imageURLString = url.absoluteString }
            try? context.save()
        }
    }

    // MARK: Search

    private var isSearching: Bool {
        !debounced.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var presentPlatforms: [Platform] {
        let used = Set(bookmarks.map(\.platform))
        return Platform.ordered.filter { used.contains($0) }
    }

    /// Matching lives in `Core/SearchScope.swift` and is tested there. This is
    /// only the two filters the view owns: the source chips, and — unscoped
    /// only — finding a bork by the name of a side quest it is on. Scoped means
    /// *these fields and no others*, and a quest title is not one of them.
    private var results: [Bookmark] {
        guard isSearching else { return [] }

        let questHits: Set<String> = {
            guard scopes.isEmpty else { return [] }
            let needle = SearchText.fold(debounced)
            return Set(
                journeys
                    .filter { SearchText.fold($0.title).contains(needle) }
                    .flatMap(\.bookmarkIDs)
            )
        }()

        return bookmarks.filter { item in
            if !sources.isEmpty && !sources.contains(item.platform) { return false }
            if questHits.contains(item.id) { return true }
            return item.searchSubject.matches(query: debounced, scopes: scopes)
        }
    }

    private func consumeFocusRequest() {
        guard focusSearch else { return }
        path = NavigationPath()
        searchFocused = true
        focusSearch = false
    }

    /// `-topic <id>` lands straight on a topic page. Screenshots only: there
    /// is no other way to capture the topic page reproducibly, since getting
    /// there otherwise means a person tapping a tile.
    ///
    /// `-topic unfiled` opens "Not filed yet"; `-source tiktok` opens that
    /// platform's Source page.
    private func consumeLaunchTopic() {
        guard !openedLaunchTopic else { return }
        if let id = ScreenshotDefaults.openTopic {
            openedLaunchTopic = true
            axis = .topics
            path.append(Route.topic(id == "unfiled" ? Self.unfiledRoute : id))
        } else if let raw = ScreenshotDefaults.openSource,
                  let platform = Platform(rawValue: raw.lowercased()) {
            openedLaunchTopic = true
            axis = .sources
            path.append(Route.source(platform))
        }
    }

    /// The "Not filed yet" page's route id.
    private static let unfiledRoute = "__uncategorised__"

    private func open(_ bookmark: Bookmark) {
        detail = bookmark
        ReviewPrompter.reached(.searchResultOpened, requestReview)
    }

    /// Cancel, Escape and the ✕ all mean the same thing: put the grid back.
    private func clearSearch() {
        query = ""
        debounced = ""
        scopes = []
        sources = []
        related = []
        searchFocused = false
    }

    /// The embedding index is built the first time someone actually types
    /// something worth searching, not when Browse appears — Browse is now one
    /// of four tabs and most visits to it never search.
    private func updateRelated() {
        let needle = debounced.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 3 else { related = []; return }
        semantic.refresh(bookmarks)
        related = semantic.search(needle, in: bookmarks, limit: 8)
    }

    /// Topics / Sources / Side quests — the one segmented control.
    private var segmented: some View {
        ClaySegmented(
            selection: Binding(
                get: { axis },
                set: { option in
                    path = NavigationPath()
                    axis = option
                }
            ),
            options: Axis.allCases.map { ($0, $0.title) }
        )
        .padding(.horizontal, Tokens.gutter)
        .zIndex(1)
    }

    /// The list's header: what is listed, and how it is ordered.
    ///
    /// The order (Most borks · Most recent · A–Z) is a small menu at the
    /// right of the header (1.4), not a row of pills above the list: one
    /// control where there were three, and the same menu on every segment,
    /// because "how is this list ordered" is one question.
    @ViewBuilder
    private var listHeader: some View {
        // An empty grid has its own heading in the empty state.
        if !(axis == .topics && usedCategories.isEmpty && uncategorisedCount == 0) {
            SectionHeader(listTitle) {
                // Nothing to order on an empty segment.
                if listIsSortable { sortMenu }
            }
            .padding(.horizontal, Tokens.gutter)
        }
    }

    private var listIsSortable: Bool {
        switch axis {
        case .topics: usedCategories.count > 1
        case .sources: true
        case .journeys: journeys.count > 1
        }
    }

    private var listTitle: String {
        switch axis {
        case .topics:
            let n = usedCategories.count
            return n == 0 ? "Your topics" : "\(n) topic\(n == 1 ? "" : "s")"
        case .sources:
            return "Where you save from"
        case .journeys:
            let n = journeys.count
            return n == 0 ? "Side quests" : Copy.countedSideQuests(n)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort \(axis.title.lowercased())", selection: Binding(
                get: { sort },
                set: { sort = $0 }
            )) {
                ForEach(BrowseSort.allCases, id: \.rawValue) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(sort.title)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
            .foregroundStyle(accent.deep)
            .frame(minHeight: Tokens.minTapTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sort \(axis.title.lowercased()), \(sort.title)")
    }

    // MARK: Topics

    private var topicCounts: [String: Int] {
        Dictionary(grouping: bookmarks.compactMap(\.categoryID)) { $0 }.mapValues(\.count)
    }

    /// Newest bork per topic. `bookmarks` is already savedAt descending, so
    /// the first sighting of a topic is its most recent one.
    private var topicRecency: [String: Date] {
        var newest: [String: Date] = [:]
        for item in bookmarks {
            guard let id = item.categoryID, newest[id] == nil else { continue }
            newest[id] = item.savedAt
        }
        return newest
    }

    /// The grid, in the order the sort chips ask for. Custom topics you
    /// created show even when empty, so they don't vanish the moment you add
    /// them — under "Most recent" they sit at the bottom until they have a
    /// bork to be recent about.
    private var usedCategories: [Topic] {
        let counts = topicCounts
        let recency = topicRecency
        let interestSet = Set(interests)
        let candidates = merged.allTopics
            .filter { (counts[$0.id] ?? 0) > 0 || merged.isCustomTopic($0.id) }

        let entries = candidates.enumerated().map { index, topic in
            BrowseSortEntry(
                id: topic.id,
                name: topic.name,
                count: counts[topic.id] ?? 0,
                recent: recency[topic.id],
                pinned: interestSet.contains(topic.id),
                rank: index
            )
        }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return sort.orderedIDs(entries).compactMap { byID[$0] }
    }

    private var uncategorisedCount: Int {
        bookmarks.filter { $0.categoryID == nil }.count
    }

    /// Generated scenes, by topic id. Empty for a library with no topics of
    /// its own, which is most of them.
    private var topicArt: [String: URL] {
        Dictionary(uniqueKeysWithValues: customTopics.compactMap { topic in
            topic.imageURL.map { (topic.id, $0) }
        })
    }

    @ViewBuilder
    private var topicsGrid: some View {
        if usedCategories.isEmpty && uncategorisedCount == 0 {
            emptyTopics
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Tokens.gridGap, alignment: .top),
                                GridItem(.flexible(), spacing: Tokens.gridGap, alignment: .top)],
                      spacing: Tokens.gridGap) {
                // First, not last. At the end of the grid it was one scroll
                // away, and the first outside tester never scrolled. A dashed
                // tile exactly the size of a topic tile (it is laid out on an
                // invisible one), so the grid reads as your topics plus a slot
                // for the next one.
                TopicTile.skeleton
                    .hidden()
                    .overlay {
                        DashedTile(title: "New topic", symbol: "plus", action: newTopic)
                    }

                ForEach(usedCategories) { category in
                    Button {
                        path.append(Route.topic(category.id))
                    } label: {
                        TopicTile(category: category, count: topicCounts[category.id] ?? 0,
                                  artURL: topicArt[category.id])
                    }
                    .buttonStyle(PressableStyle())
                    .zoomSource(id: category.id, in: tileZoom)
                }
            }
            .padding(.horizontal, Tokens.gutter)

            if uncategorisedCount > 0 {
                Button {
                    path.append(Route.topic(Self.unfiledRoute))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.sandInk)
                            .frame(width: 36, height: 36)
                            .background(Tokens.sand, in: RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Not filed yet").textRole(.cardTitle, color: Tokens.ink)
                            Text(Copy.countedBorks(uncategorisedCount)).textRole(.meta)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tokens.inkSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: Tokens.slimRowHeight)
                    .cardSurface()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.99))
                .accessibilityElement(children: .combine)
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 4)
            }
        }
    }

    private func newTopic() {
        pickerCategory = nil
        pickerSub = nil
        showingPicker = true
    }

    /// No topics yet: the clay art a first topic would wear, and the way to
    /// make one now.
    private var emptyTopics: some View {
        VStack(spacing: 0) {
            ClayArtImage(source: .quest(.compass))
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
                .padding(.bottom, 18)
            Text("Topics appear as you save")
                .textRole(.sectionTitle, color: Tokens.ink)
                .multilineTextAlignment(.center)
            Text("Every bork is filed under one. You can make your own, too.")
                .textRole(.body, color: Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 24)
            Button("Add a topic", action: newTopic)
                .buttonStyle(.claySecondary)
                .fixedSize()
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tokens.gutter)
        .padding(.top, 36)
    }

    // MARK: Sources

    private var sourceCounts: [Platform: Int] {
        Dictionary(grouping: bookmarks.map(\.platform)) { $0 }.mapValues(\.count)
    }

    /// Every platform, still — a source you have never used is a suggestion,
    /// not a gap — but ordered by the chips. Under "Most borks" the empty ones
    /// sink to the bottom instead of sitting in the middle of the list.
    private var sortedSources: [Platform] {
        let counts = sourceCounts
        var newest: [Platform: Date] = [:]
        for item in bookmarks where newest[item.platform] == nil {
            newest[item.platform] = item.savedAt
        }
        let entries = Platform.ordered.enumerated().map { index, platform in
            BrowseSortEntry(
                id: platform.rawValue,
                name: platform.name,
                count: counts[platform] ?? 0,
                recent: newest[platform],
                rank: index
            )
        }
        return sort.orderedIDs(entries).compactMap(Platform.init(rawValue:))
    }

    @ViewBuilder
    private var sourcesList: some View {
        let counts = sourceCounts
        VStack(spacing: 8) {
            ForEach(sortedSources, id: \.self) { platform in
                let count = counts[platform] ?? 0
                Button {
                    path.append(Route.source(platform))
                } label: {
                    SourceRow(
                        platform: platform,
                        count: count,
                        topCategories: count == 0 ? "Nothing saved yet" : topCategories(for: platform),
                        swatches: swatches(for: platform),
                        empty: count == 0
                    )
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
        }
        .padding(.horizontal, Tokens.gutter)
    }

    private func topCategories(for platform: Platform) -> String {
        let names = Dictionary(grouping: bookmarks.filter { $0.platform == platform }
            .compactMap(\.category)) { $0.id }
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
            .compactMap { $0.value.first?.name }
        return names.isEmpty ? "No topics yet" : names.joined(separator: ", ")
    }

    /// The topics of the newest few borks from this app, one dot each.
    private func swatches(for platform: Platform) -> [CategoryPalette] {
        var seen = Set<String>()
        return bookmarks.filter { $0.platform == platform }
            .filter { seen.insert($0.categoryID ?? "").inserted }
            .prefix(3)
            .map { $0.category?.palette ?? NeutralPalette.value }
    }
}

private struct TopicTile: View {
    let category: Topic
    let count: Int
    /// Set only for a topic the user made: built-ins resolve to a bundled
    /// imageset and never consult this.
    var artURL: URL? = nil

    /// SYSTEM.md's topic tile: the clay art 4:3 on its own sand ground, then
    /// on white the 8 pt dot, the name 15/600 and "10 borks". No colour block.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Tokens.clayGround
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { TopicClayArt(categoryID: category.id, remote: artURL) }
                .clipped()
            Self.footer(name: category.name, count: count, palette: category.palette)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.name), \(Copy.countedBorks(count))")
        .accessibilityAddTraits(.isButton)
    }

    private static func footer(name: String, count: Int, palette: CategoryPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TopicDot(palette: palette)
                Text(name)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(Copy.countedBorks(count))
                .textRole(.meta)
                .lineLimit(1)
        }
        .padding(.top, 9)
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tile's exact shape with nothing in it, for the "New topic" slot to
    /// be laid out on, so the two are the same size at every text size.
    static var skeleton: some View {
        VStack(spacing: 0) {
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
            footer(name: "New topic", count: 0, palette: NeutralPalette.value)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SourceRow: View {
    let platform: Platform
    let count: Int
    let topCategories: String
    let swatches: [CategoryPalette]
    var empty: Bool = false

    /// A flat row: the platform's mark, its name and what you save from it,
    /// a dot per topic, a chevron.
    var body: some View {
        HStack(spacing: 12) {
            PlatformBadge(platform: platform, size: 36)
                .opacity(empty ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(platform.name)
                    .textRole(.cardTitle, color: empty ? Tokens.inkSecondary : Tokens.ink)
                Text(empty ? "Nothing saved yet" : "\(Copy.countedBorks(count)) · \(topCategories)")
                    .textRole(.meta)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !empty {
                HStack(spacing: 4) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, palette in
                        TopicDot(palette: palette)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.inkSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: Tokens.slimRowHeight)
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tile → topic page transition

/// The topic page opens out of the tile you tapped rather than sliding in from
/// the right — the hero band *is* that tile, enlarged, so the system zoom is
/// the honest animation for it.
///
/// iOS 18 and up. On 17 both of these are no-ops and the push is the standard
/// one, which is exactly what shipped before.
private extension View {
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomedFrom(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
