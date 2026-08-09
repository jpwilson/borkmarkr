import SwiftUI
import SwiftData

/// Source page: full-bleed dark brand header with cross-axis topic chips.
struct SourcePage: View {
    let platform: Platform

    @Environment(\.accent) private var accent
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @State private var topic: String?
    @State private var detail: Bookmark?

    private var inSource: [Bookmark] { all.filter { $0.platform == platform } }

    private var visible: [Bookmark] {
        guard let topic else { return inSource }
        return inSource.filter { $0.categoryID == topic }
    }

    private var presentTopics: [Topic] {
        let counts = Dictionary(grouping: inSource.compactMap(\.categoryID)) { $0 }.mapValues(\.count)
        return Taxonomy.all
            .filter { (counts[$0.id] ?? 0) > 0 }
            .sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !presentTopics.isEmpty { topicRow }
                list
            }
            .padding(.bottom, 120)
        }
        .background(Tokens.paper)
        .navigationBarTitleDisplayMode(.inline)
        // The header is a dark brand gradient, so the status bar and back
        // button need light content or they vanish into it.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(platform.headerColors.first ?? .black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PlatformBadge(platform: platform, size: 46)
                Spacer()
                Text(Copy.countedBorks(inSource.count))
                    .font(Typo.ui(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .font(Typo.display(28, .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                Text(platform.descriptor)
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(18)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: platform.headerColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var topicRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOPIC")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Button { topic = nil } label: {
                        Text("All")
                            .font(Typo.ui(12.5, .semibold))
                            .foregroundStyle(topic == nil ? .white : Tokens.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(topic == nil ? Tokens.ink : Tokens.surface, in: Capsule())
                            .overlay(Capsule().stroke(topic == nil ? .clear : Tokens.hairline, lineWidth: 1))
                            .tappableChip()
                    }
                    .buttonStyle(.plain)

                    // Each chip in its own category tint — the cross-axis link
                    // back to the Topics side.
                    ForEach(presentTopics) { category in
                        let active = topic == category.id
                        Button {
                            topic = active ? nil : category.id
                        } label: {
                            Text(category.name)
                                .font(Typo.ui(12.5, .semibold))
                                .foregroundStyle(active ? .white : category.palette.deep)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(active ? category.palette.deep : category.palette.tint, in: Capsule())
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
                Image(systemName: "tray")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Tokens.inkFaint)
                Text("Nothing here yet")
                    .font(Typo.ui(14, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
        } else {
            LazyVStack(spacing: 9) {
                ForEach(visible) { bookmark in
                    Button { detail = bookmark } label: {
                        // Platform badge omitted — every row here is this
                        // platform, so repeating it is noise.
                        BookmarkRow(bookmark: bookmark, showPlatformBadge: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }
}
