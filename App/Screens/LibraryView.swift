import SwiftUI
import SwiftData

/// Home. Wordmark, "Your library" + live stats, search entry, source chips,
/// density toggle, and the masonry feed.
struct LibraryView: View {
    let onAdd: () -> Void
    var onSearch: () -> Void = {}
    var onSeeJourneys: () -> Void = {}
    var account: Account? = nil

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @AppStorage("feedDensity") private var density = "cards"

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var bookmarks: [Bookmark]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    @State private var sourceFilter: Platform?
    @State private var detail: Bookmark?
    @State private var openJourney: Mission?
    @State private var creatingJourney = false
    @State private var showingInsights = false
    @StateObject private var previews = PreviewFetcher()

    private var visible: [Bookmark] {
        guard let sourceFilter else { return bookmarks }
        return bookmarks.filter { $0.platform == sourceFilter }
    }

    private var presentPlatforms: [Platform] {
        let used = Set(bookmarks.map(\.platform))
        return Platform.ordered.filter { used.contains($0) }
    }

    private var statsLine: String {
        let borks = bookmarks.count
        let apps = Set(bookmarks.map(\.platform)).count
        let topics = Set(bookmarks.compactMap(\.categoryID)).count
        return "\(borks) \(Copy.borks(borks)) · \(apps) app\(apps == 1 ? "" : "s") · \(topics) topic\(topics == 1 ? "" : "s")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchEntry
                insightsEntry
                JourneyRail(
                    journeys: journeys,
                    bookmarks: bookmarks,
                    onOpen: { openJourney = $0 },
                    onSeeAll: onSeeJourneys,
                    onStart: { creatingJourney = true },
                    onAcceptSeed: acceptSeed,
                    account: account
                )
                if !presentPlatforms.isEmpty { filterRow }
                feed
            }
            .padding(.bottom, 120)
        }
        .background(Tokens.paper)
        .sheet(item: $detail) { bookmark in
            DetailSheet(bookmark: bookmark)
                .environment(\.accent, accent)
        }
        .sheet(item: $openJourney) { journey in
            MissionDetailSheet(mission: journey, account: account).environment(\.accent, accent)
        }
        .sheet(isPresented: $creatingJourney) {
            NewMissionSheet().environment(\.accent, accent)
        }
        .sheet(isPresented: $showingInsights) {
            InsightsSheet(bookmarks: bookmarks, account: account) { title in
                let quest = Mission(title: title)
                context.insert(quest)
                try? context.save()
                openJourney = quest
            }
            .environment(\.accent, accent)
        }
        .onAppear(perform: markRead)
        // Fill in real titles and thumbnails for anything still missing them.
        // Keyed on count so a fresh batch of brks triggers another pass.
        .task(id: bookmarks.count) {
            await previews.fetchMissing(for: bookmarks, in: context)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(accent.base, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("bookmarker")
                        .font(Typo.display(17, .bold))
                        .foregroundStyle(Tokens.ink)
                }
                Spacer()
                Circle()
                    .fill(accent.tint)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("J").font(Typo.ui(14, .bold)).foregroundStyle(accent.deep)
                    )
            }

            Text("Your library")
                .font(Typo.display(34, .heavy))
                .tracking(-1.0)
                .foregroundStyle(Tokens.ink)
                .padding(.top, 12)

            Text(statsLine)
                .font(Typo.ui(12.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var searchEntry: some View {
        Button(action: onSearch) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.inkFaint)
                Text(Copy.searchPlaceholder)
                    .font(Typo.ui(14))
                    .foregroundStyle(Tokens.inkMeta)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Tokens.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .accessibilityHint("Opens the Search tab")
    }

    private var insightsEntry: some View {
        Button { showingInsights = true } label: {
            InsightsEntry(bookmarks: bookmarks)
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, 18)
    }

    private func acceptSeed(_ seed: Mission.Seed) {
        let journey = Mission(title: seed.title, categoryID: seed.categoryID)
        journey.bookmarkIDs = seed.bookmarkIDs
        context.insert(journey)
        try? context.save()
        Haptics.success()
        openJourney = journey
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chip("All", active: sourceFilter == nil) { sourceFilter = nil }
                    ForEach(presentPlatforms, id: \.self) { platform in
                        chip(platform.name, active: sourceFilter == platform) {
                            sourceFilter = sourceFilter == platform ? nil : platform
                        }
                    }
                }
                .padding(.horizontal, 18)
            }

            densityToggle
                .padding(.trailing, 18)
        }
    }

    private func chip(_ label: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snap) { tap() }
        } label: {
            Text(label)
                .font(Typo.ui(12.5, .semibold))
                .foregroundStyle(active ? .white : Tokens.inkSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(active ? Tokens.ink : Tokens.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : Tokens.hairline, lineWidth: 1))
                .tappableChip()
        }
        .buttonStyle(ChipStyle())
    }

    private var densityToggle: some View {
        HStack(spacing: 2) {
            densityButton("square.grid.2x2", value: "cards")
            densityButton("list.bullet", value: "compact")
        }
        .padding(3)
        .background(Tokens.segmentTrack, in: Capsule())
    }

    private func densityButton(_ symbol: String, value: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { density = value }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(density == value ? Tokens.ink : Tokens.inkMeta)
                .frame(width: 32, height: 28)
                .background(density == value ? Tokens.surface : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == "cards" ? "Card view" : "List view")
    }

    @ViewBuilder
    private var feed: some View {
        if visible.isEmpty {
            EmptyFeedState(filtered: sourceFilter != nil, onAdd: onAdd)
                .padding(.top, 50)
        } else if density == "compact" {
            LazyVStack(spacing: 8) {
                ForEach(visible) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(PressableStyle())
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
        } else {
            // No GeometryReader here. An earlier version wrapped this in one
            // with a guessed `.frame(height:)`, which broke the layout outright
            // — GeometryReader claims the whole proposal regardless of content,
            // so with a short feed the cards were drawn over the filter row
            // above them. MasonryVStack is an HStack of two LazyVStacks and
            // already sizes to its content; it just needed to be left alone.
            MasonryVStack(
                items: visible,
                spacing: 12,
                estimatedHeight: { BookmarkCard.estimatedHeight(for: $0, columnWidth: Self.columnWidth) }
            ) { bookmark in
                Button { detail = bookmark } label: {
                    BookmarkCard(bookmark: bookmark)
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(.horizontal, 18)
        }
    }

    /// Only feeds the height *estimate* that balances the two columns, so an
    /// approximation from screen width is plenty — it never sets a real frame.
    private static var columnWidth: CGFloat {
        let screen = UIScreen.main.bounds.width
        return (screen - 36 - 12) / 2
    }

    private func markRead() {
        let unread = bookmarks.filter(\.isUnread)
        guard !unread.isEmpty else { return }
        for bookmark in unread { bookmark.isUnread = false }
        try? context.save()
    }
}

private struct EmptyFeedState: View {
    @Environment(\.accent) private var accent
    let filtered: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: filtered ? "line.3.horizontal.decrease.circle" : "bookmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(accent.base.opacity(0.75))

            Text(filtered ? "Nothing from this app yet" : "Everything you save, in one place")
                .font(Typo.display(18, .bold))
                .foregroundStyle(Tokens.ink)
                .multilineTextAlignment(.center)

            Text(filtered
                 ? "Try another source."
                 : "In Instagram, X, TikTok or YouTube — tap Share, then bookmarker.")
                .font(Typo.ui(13.5))
                .foregroundStyle(Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 46)

            if !filtered {
                Button(action: onAdd) {
                    Text("Paste a link")
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
