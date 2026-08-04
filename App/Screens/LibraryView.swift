import SwiftUI
import SwiftData

/// Home. Wordmark, "Your library" + live stats, search entry, source chips,
/// density toggle, and the masonry feed.
struct LibraryView: View {
    let onAdd: () -> Void

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @AppStorage("feedDensity") private var density = "cards"

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var bookmarks: [Bookmark]

    @State private var sourceFilter: Platform?
    @State private var detail: Bookmark?

    private var visible: [Bookmark] {
        guard let sourceFilter else { return bookmarks }
        return bookmarks.filter { $0.platform == sourceFilter }
    }

    private var presentPlatforms: [Platform] {
        let used = Set(bookmarks.map(\.platform))
        return Platform.ordered.filter { used.contains($0) }
    }

    private var statsLine: String {
        let saves = bookmarks.count
        let apps = Set(bookmarks.map(\.platform)).count
        let topics = Set(bookmarks.compactMap(\.categoryID)).count
        return "\(saves) save\(saves == 1 ? "" : "s") · \(apps) app\(apps == 1 ? "" : "s") · \(topics) topic\(topics == 1 ? "" : "s")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                searchEntry
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
        .onAppear(perform: markRead)
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
                    Text("borkmarkr")
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
                .font(Typo.display(32, .heavy))
                .tracking(-0.8)
                .foregroundStyle(Tokens.ink)
                .padding(.top, 10)

            Text(statsLine)
                .font(Typo.ui(12.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var searchEntry: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.inkFaint)
            Text("Search everything you saved")
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
        .padding(.horizontal, 18)
        .accessibilityHint("Opens the Search tab")
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
        Button(action: tap) {
            Text(label)
                .font(Typo.ui(12.5, .semibold))
                .foregroundStyle(active ? .white : Tokens.inkSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(active ? Tokens.ink : Tokens.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : Tokens.hairline, lineWidth: 1))
                .tappableChip()
        }
        .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        } else {
            GeometryReader { geo in
                let columnWidth = (geo.size.width - 36 - 12) / 2
                MasonryVStack(
                    items: visible,
                    spacing: 12,
                    estimatedHeight: { BookmarkCard.estimatedHeight(for: $0, columnWidth: columnWidth) }
                ) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkCard(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
            }
            .frame(height: masonryHeight)
        }
    }

    /// GeometryReader needs an explicit height inside a ScrollView. Estimate
    /// the taller column and add slack — over-estimating costs empty space,
    /// under-estimating clips cards, so this errs high.
    private var masonryHeight: CGFloat {
        let columnWidth: CGFloat = 170
        let total = visible.reduce(CGFloat.zero) {
            $0 + BookmarkCard.estimatedHeight(for: $1, columnWidth: columnWidth) + 12
        }
        return total / 2 + 240
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
                 : "In Instagram, X, TikTok or YouTube — tap Share, then borkmarkr.")
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
