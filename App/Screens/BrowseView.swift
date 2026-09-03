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
    @AppStorage("browseAxis") private var axisRaw = Axis.topics.rawValue
    @State private var path = NavigationPath()

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

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
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
                Text("Browse")
                    .font(Typo.display(34, .heavy))
                    .tracking(-1.0)
                    .foregroundStyle(Tokens.ink)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                BrowseSearchBar(
                    query: $query,
                    scopes: $scopes,
                    focus: $searchFocused,
                    isSearching: isSearching,
                    onCancel: clearSearch
                )
                .padding(.top, 14)

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
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                    }
                    .scrollDismissesKeyboard(.immediately)
                } else {
                    segmented
                        .padding(.top, 16)
                        .padding(.bottom, 14)

                    ScrollView {
                        Group {
                            switch axis {
                            case .topics: topicsGrid
                            case .sources: sourcesList
                            case .journeys: MissionsView(account: account)
                            }
                        }
                        .padding(.bottom, 120)
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
        .onAppear(perform: consumeFocusRequest)
        .onChange(of: focusSearch) { _, _ in consumeFocusRequest() }
        .task(id: query) {
            // Debounce: wait out the typist, then commit.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            debounced = query
            updateRelated()
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

    private var segmented: some View {
        HStack(spacing: 3) {
            ForEach(Axis.allCases, id: \.self) { option in
                Button {
                    path = NavigationPath()
                    withAnimation(.easeOut(duration: 0.18)) { axis = option }
                } label: {
                    Text(option.title)
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(axis == option ? Tokens.ink : Tokens.inkMeta)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .background(axis == option ? Tokens.surface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Tokens.segmentTrack, in: Capsule())
        .padding(.horizontal, 18)
        .zIndex(1)
    }

    // MARK: Topics

    private var topicCounts: [String: Int] {
        Dictionary(grouping: bookmarks.compactMap(\.categoryID)) { $0 }.mapValues(\.count)
    }

    /// User's onboarding interests (that have saves) first, then count desc.
    /// Custom topics you created show even when empty, so they don't vanish
    /// the moment you add them.
    private var usedCategories: [Topic] {
        let counts = topicCounts
        let interestSet = Set(interests)
        return merged.allTopics
            .filter { (counts[$0.id] ?? 0) > 0 || merged.isCustomTopic($0.id) }
            .sorted { a, b in
                let ai = interestSet.contains(a.id), bi = interestSet.contains(b.id)
                if ai != bi { return ai }
                return (counts[a.id] ?? 0) > (counts[b.id] ?? 0)
            }
    }

    private var uncategorisedCount: Int {
        bookmarks.filter { $0.categoryID == nil }.count
    }

    @ViewBuilder
    private var topicsGrid: some View {
        if usedCategories.isEmpty && uncategorisedCount == 0 {
            VStack(spacing: 18) {
                emptyAxis(symbol: "square.grid.2x2", text: "Topics appear as you save")
                Button {
                    pickerCategory = nil
                    pickerSub = nil
                    showingPicker = true
                } label: {
                    Text("Or add a topic now")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(accent.deep)
                }
                .buttonStyle(.plain)
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(usedCategories) { category in
                    Button {
                        path.append(Route.topic(category.id))
                    } label: {
                        TopicTile(category: category, count: topicCounts[category.id] ?? 0)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    pickerCategory = nil
                    pickerSub = nil
                    showingPicker = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                        Text("New topic")
                            .font(Typo.ui(14.5, .bold))
                    }
                    .foregroundStyle(accent.deep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .frame(height: 168, alignment: .topLeading)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            if uncategorisedCount > 0 {
                Button {
                    path.append(Route.topic("__uncategorised__"))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Not filed yet")
                            .font(Typo.ui(14, .semibold))
                        Spacer()
                        Text("\(uncategorisedCount)")
                            .font(Typo.ui(13, .bold))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(15)
                    .cardSurface(radius: 18)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: Sources

    private var sourceCounts: [Platform: Int] {
        Dictionary(grouping: bookmarks.map(\.platform)) { $0 }.mapValues(\.count)
    }

    @ViewBuilder
    private var sourcesList: some View {
        let counts = sourceCounts
        VStack(spacing: 10) {
            ForEach(Platform.ordered, id: \.self) { platform in
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
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    private func topCategories(for platform: Platform) -> String {
        let names = Dictionary(grouping: bookmarks.filter { $0.platform == platform }
            .compactMap(\.category)) { $0.id }
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
            .compactMap { $0.value.first?.name }
        return names.isEmpty ? "No topics yet" : names.joined(separator: ", ")
    }

    private func swatches(for platform: Platform) -> [CategoryPalette] {
        bookmarks.filter { $0.platform == platform }
            .prefix(3)
            .map { $0.category?.palette ?? NeutralPalette.value }
    }

    private func emptyAxis(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Tokens.inkFaint)
            Text(text)
                .font(Typo.ui(14.5, .semibold))
                .foregroundStyle(Tokens.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

private struct TopicTile: View {
    let category: Topic
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ClayArt(name: TopicMotif.asset(for: category.id))
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(Typo.ui(14.5, .bold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                Text(Copy.countedBorks(count))
                    .font(Typo.ui(11, .medium))
                    .foregroundStyle(Tokens.inkMeta)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(category.palette.tint)
        }
        .frame(height: 168, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous)
                .stroke(category.palette.deep.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SourceRow: View {
    let platform: Platform
    let count: Int
    let topCategories: String
    let swatches: [CategoryPalette]
    var empty: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            PlatformBadge(platform: platform, size: 44)
                .opacity(empty ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .font(Typo.ui(15, .bold))
                    .foregroundStyle(empty ? Tokens.inkSecondary : Tokens.ink)
                Text(empty ? "Nothing saved yet" : "\(Copy.countedBorks(count)) · \(topCategories)")
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !empty {
                HStack(spacing: -6) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, palette in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [palette.coverTop, palette.coverBottom],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(.white, lineWidth: 1.5)
                            )
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tokens.inkFaint)
        }
        .padding(13)
        .cardSurface(radius: 18)
        .opacity(empty ? 0.92 : 1)
    }
}
