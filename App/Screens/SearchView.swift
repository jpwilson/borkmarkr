import SwiftUI
import SwiftData
import StoreKit

/// Dual-axis search: free text plus multi-select Source and Topic filters.
///
/// **Engineering deviation.** The prototype re-scans every item across six
/// fields on every keystroke. That's fine for 26 items and janks badly at a few
/// thousand. Two changes: matching runs against the precomputed `searchBlob` on
/// the model (one `contains` per item), and input is debounced so a fast typist
/// triggers one pass rather than one per character.
struct SearchView: View {
    @Environment(\.accent) private var accent
    @Environment(\.requestReview) private var requestReview

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @State private var query = ScreenshotDefaults.searchQuery
    @State private var debounced = ScreenshotDefaults.searchQuery
    @State private var sources: Set<Platform> = []
    @State private var topics: Set<String> = []
    @State private var journeyFilter: Set<String> = []
    @AppStorage("searchRecents") private var recentsRaw = ""
    @State private var openAxis: SearchAxis?
    @State private var expandTopics = false
    @State private var detail: Bookmark?

    @StateObject private var semantic = SemanticIndex()
    @State private var related: [SemanticIndex.Hit] = []

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    private enum SearchAxis: String, CaseIterable, Identifiable {
        case source, topic, quest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .source: "Source"
            case .topic: "Topic"
            case .quest: "Side quest"
            }
        }
    }

    private var recents: [String] {
        recentsRaw.split(separator: "\u{1e}").map(String.init).filter { !$0.isEmpty }
    }

    private var isFiltering: Bool {
        !debounced.isEmpty || !sources.isEmpty || !topics.isEmpty || !journeyFilter.isEmpty
    }

    private var results: [Bookmark] {
        guard isFiltering else { return [] }
        let needle = debounced
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        let journeyNameHits: Set<String> = {
            guard !needle.isEmpty else { return [] }
            return Set(
                journeys
                    .filter { $0.title.lowercased().contains(needle) }
                    .flatMap(\.bookmarkIDs)
            )
        }()

        let onSelectedJourneys: Set<String> = {
            guard !journeyFilter.isEmpty else { return [] }
            return Set(
                journeys.filter { journeyFilter.contains($0.id) }.flatMap(\.bookmarkIDs)
            )
        }()

        return all.filter { item in
            if !sources.isEmpty && !sources.contains(item.platform) { return false }
            if !topics.isEmpty {
                guard let id = item.categoryID, topics.contains(id) else { return false }
            }
            if !journeyFilter.isEmpty && !onSelectedJourneys.contains(item.id) { return false }
            guard !needle.isEmpty else { return true }
            return item.searchBlob.contains(needle) || journeyNameHits.contains(item.id)
        }
    }

    /// Every topic, with the ones you actually have borks in first.
    ///
    /// Showing only used topics made Search feel broken: you'd go looking for
    /// "Cars" and it simply wasn't there, with no way to tell whether you had
    /// nothing filed under it or the app had lost it. Browse is the "what do I
    /// have" screen; Search is the "find anything" screen, and it should offer
    /// the whole vocabulary.
    private var presentTopics: [Topic] {
        let used = Set(all.compactMap(\.categoryID))
        let merged = MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
        let mine = merged.allTopics.filter { used.contains($0.id) }
        let rest = merged.allTopics.filter { !used.contains($0.id) }
        return mine + rest
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Search")
                    .font(Typo.display(34, .heavy))
                    .tracking(-1.0)
                    .foregroundStyle(Tokens.ink)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                field
                axisTabs
                if let openAxis {
                    axisPills(openAxis)
                }
                content
            }
            .padding(.bottom, 120)
        }
        .background(Tokens.paper)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
        .task(id: query) {
            // Debounce: wait out the typist, then commit.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            debounced = query
            updateRelated()
        }
        .task {
            // Build the embedding index once the screen is first opened, rather
            // than at launch — most sessions never search.
            semantic.refresh(all)
        }
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.base)
            TextField("Titles, tags, notes, people", text: $query)
                .font(Typo.ui(14.5))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit(rememberQuery)
            if !query.isEmpty {
                Button {
                    query = ""; debounced = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Tokens.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.base.opacity(0.55), lineWidth: 1.5)
        )
        .padding(.horizontal, 18)
    }

    private var axisTabs: some View {
        HStack(spacing: 8) {
            ForEach(SearchAxis.allCases) { axis in
                let on = openAxis == axis
                let count = selectedCount(axis)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        openAxis = on ? nil : axis
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(axis.title)
                        if count > 0 {
                            Text("\(count)")
                                .font(Typo.ui(10, .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.white.opacity(on ? 0.22 : 0.7), in: Capsule())
                        }
                    }
                    .font(Typo.ui(13, .semibold))
                    .foregroundStyle(on ? .white : Tokens.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(on ? Tokens.ink : Tokens.surface, in: Capsule())
                    .overlay(Capsule().stroke(on ? .clear : Tokens.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }

    private func selectedCount(_ axis: SearchAxis) -> Int {
        switch axis {
        case .source: sources.count
        case .topic: topics.count
        case .quest: journeyFilter.count
        }
    }

    @ViewBuilder
    private func axisPills(_ axis: SearchAxis) -> some View {
        switch axis {
        case .source:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Platform.ordered, id: \.self) { platform in
                        toggleChip(platform.name,
                                   active: sources.contains(platform),
                                   tint: Color(hex: "48505C")) {
                            if sources.contains(platform) { sources.remove(platform) }
                            else { sources.insert(platform) }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        case .topic:
            let chips = expandTopics ? presentTopics : Array(presentTopics.prefix(12))
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 7) {
                    ForEach(chips) { topic in
                        toggleChip(topic.name,
                                   active: topics.contains(topic.id),
                                   tint: topic.palette.deep,
                                   bg: topic.palette.tint,
                                   expandHit: false) {
                            if topics.contains(topic.id) { topics.remove(topic.id) }
                            else { topics.insert(topic.id) }
                        }
                    }
                }
                if !expandTopics && presentTopics.count > 12 {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { expandTopics = true }
                    } label: {
                        Text("More topics")
                            .font(Typo.ui(12.5, .semibold))
                            .foregroundStyle(accent.deep)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        case .quest:
            if journeys.isEmpty {
                Text("No side quests yet")
                    .font(Typo.ui(13))
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.horizontal, 18)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(journeys) { journey in
                        toggleChip(journey.title,
                                   active: journeyFilter.contains(journey.id),
                                   tint: (journey.topic?.palette ?? NeutralPalette.value).deep,
                                   bg: (journey.topic?.palette ?? NeutralPalette.value).tint,
                                   expandHit: false) {
                            if journeyFilter.contains(journey.id) { journeyFilter.remove(journey.id) }
                            else { journeyFilter.insert(journey.id) }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func toggleChip(_ label: String, active: Bool, tint: Color,
                            bg: Color? = nil, expandHit: Bool = true,
                            tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(Typo.ui(12.5, .semibold))
                .foregroundStyle(active ? .white : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? tint : (bg ?? Tokens.surface), in: Capsule())
                .overlay(
                    Capsule().stroke(active || bg != nil ? .clear : Tokens.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .modifier(OptionalChipHit(on: expandHit))
    }

    @ViewBuilder
    private var content: some View {
        if !isFiltering {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent")
                    .font(Typo.ui(10, .heavy)).tracking(0.6)
                    .foregroundStyle(Tokens.mutedHeading)

                if recents.isEmpty {
                    Text("Your last searches will show up here.")
                        .font(Typo.ui(13.5))
                        .foregroundStyle(Tokens.inkSecondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recents.enumerated()), id: \.element) { index, term in
                            if index > 0 { Divider().overlay(Tokens.divider) }
                            Button {
                                query = term
                                debounced = term
                            } label: {
                                HStack {
                                    Text(term)
                                        .font(Typo.ui(14.5, .medium))
                                        .foregroundStyle(Tokens.ink)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Tokens.inkFaint)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardSurface(radius: 16)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Text("No matches")
                    .font(Typo.ui(15, .bold))
                    .foregroundStyle(Tokens.ink)
                Text("Try fewer filters, or a different word.")
                    .font(Typo.ui(13))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 46)
        } else {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(Typo.ui(11.5, .semibold))
                .foregroundStyle(Tokens.inkMeta)
                .padding(.horizontal, 18)

            LazyVStack(spacing: 9) {
                ForEach(results) { bookmark in
                    Button {
                        rememberQuery()
                        detail = bookmark
                        ReviewPrompter.reached(.searchResultOpened, requestReview)
                    } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            relatedSection
        }
    }

    /// Meaning-matched items the keyword pass missed. Additive on purpose —
    /// exact matches stay on top, where someone searching a remembered word
    /// expects them.
    @ViewBuilder
    private var relatedSection: some View {
        let exact = Set(results.map(\.id))
        let extras = related.filter { !exact.contains($0.id) }

        if !extras.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                    Text("RELATED")
                        .font(Typo.ui(10, .heavy)).tracking(0.6)
                }
                .foregroundStyle(accent.deep)
                .padding(.top, 18)

                Text("Close in meaning, even though the words don't match.")
                    .font(Typo.ui(12))
                    .foregroundStyle(Tokens.inkSecondary)

                ForEach(extras) { hit in
                    Button { detail = hit.bookmark } label: {
                        BookmarkRow(bookmark: hit.bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func updateRelated() {
        let needle = debounced.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 3 else { related = []; return }
        related = semantic.search(needle, in: all, limit: 8)
    }

    private func rememberQuery() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count > 1 else { return }
        var next = recents.filter { $0 != term }
        next.insert(term, at: 0)
        recentsRaw = Array(next.prefix(8)).joined(separator: "\u{1e}")
    }
}

private struct OptionalChipHit: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.tappableChip()
        } else {
            content
        }
    }
}
