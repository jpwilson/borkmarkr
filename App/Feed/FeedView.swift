import SwiftUI
import SwiftData

/// "Scrolling your links" — the other half of the app's core loop.
struct FeedView: View {
    @Environment(\.brandAccent) private var accent
    @Environment(\.modelContext) private var context
    @AppStorage("compactFeed") private var compact = false

    @Query(sort: \Bookmark.savedAt, order: .reverse)
    private var bookmarks: [Bookmark]

    @State private var sourceFilter: Platform?

    private var visible: [Bookmark] {
        bookmarks.filter { !$0.isArchived && (sourceFilter == nil || $0.platform == sourceFilter) }
    }

    /// Only offer filters for platforms actually present — an empty "TikTok"
    /// filter is noise.
    private var presentPlatforms: [Platform] {
        let used = Set(bookmarks.filter { !$0.isArchived }.map(\.platform))
        return Platform.allCases.filter { used.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    EmptyState(hasAnything: !bookmarks.isEmpty)
                } else {
                    ScrollView {
                        LazyVStack(spacing: compact ? 8 : 14) {
                            ForEach(visible) { bookmark in
                                NavigationLink {
                                    DetailView(bookmark: bookmark)
                                } label: {
                                    BookmarkCard(bookmark: bookmark, compact: compact)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("borkmarkr")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        compact.toggle()
                    } label: {
                        Image(systemName: compact ? "rectangle.grid.1x2" : "list.bullet")
                    }
                    .accessibilityLabel(compact ? "Switch to big cards" : "Switch to compact list")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if presentPlatforms.count > 1 {
                    sourceFilterBar
                }
            }
            .onAppear(perform: markAllRead)
        }
    }

    private var sourceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(label: "All", symbol: "square.stack", active: sourceFilter == nil) {
                    sourceFilter = nil
                }
                ForEach(presentPlatforms, id: \.self) { platform in
                    filterPill(label: platform.label, symbol: platform.symbol,
                               active: sourceFilter == platform) {
                        sourceFilter = (sourceFilter == platform) ? nil : platform
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
    }

    private func filterPill(label: String, symbol: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                Text(label).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : Theme.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? accent : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(active ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Anything the Share Extension dropped in while the app was closed stops
    /// being "new" once you've actually looked at the feed.
    private func markAllRead() {
        let unread = bookmarks.filter(\.isUnread)
        guard !unread.isEmpty else { return }
        for bookmark in unread { bookmark.isUnread = false }
        try? context.save()
    }
}

private struct EmptyState: View {
    @Environment(\.brandAccent) private var accent
    let hasAnything: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: hasAnything ? "line.3.horizontal.decrease.circle" : "bookmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(accent.opacity(0.7))
            Text(hasAnything ? "Nothing in this filter" : "Nothing saved yet")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(hasAnything
                 ? "Try a different source."
                 : "Tap + to paste a link, or hit Share in any app and pick borkmarkr.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
