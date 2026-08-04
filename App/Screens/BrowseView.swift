import SwiftUI
import SwiftData

/// The IA spine: two browse axes that cross. Topics lead to a topic page with
/// source chips; Sources lead to a source page with topic chips. Either axis
/// can lead and the other is always available as a secondary filter.
struct BrowseView: View {
    let interests: [String]
    @Binding var pendingTopic: String?

    @Environment(\.accent) private var accent
    @State private var axis = Axis.topics
    @State private var path = NavigationPath()

    enum Axis: String, CaseIterable {
        case topics, sources
        var title: String { self == .topics ? "Topics" : "Sources" }
    }

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var bookmarks: [Bookmark]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Browse")
                        .font(Typo.display(32, .heavy))
                        .tracking(-0.8)
                        .foregroundStyle(Tokens.ink)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    segmented

                    if axis == .topics { topicsGrid } else { sourcesList }
                }
                .padding(.bottom, 120)
            }
            .background(Tokens.paper)
            .navigationDestination(for: String.self) { categoryID in
                if let category = Taxonomy.category(id: categoryID) {
                    TopicPage(category: category)
                }
            }
            .navigationDestination(for: Platform.self) { platform in
                SourcePage(platform: platform)
            }
        }
        .onChange(of: pendingTopic) { _, value in
            guard let value else { return }
            axis = .topics
            path.append(value)
            pendingTopic = nil
        }
    }

    private var segmented: some View {
        HStack(spacing: 3) {
            ForEach(Axis.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { axis = option }
                } label: {
                    Text(option.title)
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(axis == option ? Tokens.ink : Tokens.inkMeta)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(axis == option ? Tokens.surface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Tokens.segmentTrack, in: Capsule())
        .padding(.horizontal, 18)
    }

    // MARK: Topics

    private var topicCounts: [String: Int] {
        Dictionary(grouping: bookmarks.compactMap(\.categoryID)) { $0 }.mapValues(\.count)
    }

    /// User's onboarding interests (that have saves) first, then count desc.
    private var usedCategories: [Topic] {
        let counts = topicCounts
        let interestSet = Set(interests)
        return Taxonomy.all
            .filter { (counts[$0.id] ?? 0) > 0 }
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
            emptyAxis(symbol: "square.grid.2x2", text: "Topics appear as you save")
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(usedCategories) { category in
                    NavigationLink(value: category.id) {
                        TopicTile(category: category, count: topicCounts[category.id] ?? 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            if uncategorisedCount > 0 {
                NavigationLink(value: "__uncategorised__") {
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
        let used = Platform.ordered.filter { (counts[$0] ?? 0) > 0 }

        if used.isEmpty {
            emptyAxis(symbol: "square.stack", text: "Sources appear as you save")
        } else {
            VStack(spacing: 10) {
                ForEach(used, id: \.self) { platform in
                    NavigationLink(value: platform) {
                        SourceRow(
                            platform: platform,
                            count: counts[platform] ?? 0,
                            topCategories: topCategories(for: platform),
                            swatches: swatches(for: platform)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
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
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(category.palette.deep.opacity(0.10))
                .frame(width: 84, height: 84)
                .offset(x: 26, y: -26)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(count)")
                    .font(Typo.display(23, .heavy))
                    .foregroundStyle(category.palette.deep)
                Text(count == 1 ? "save" : "saves")
                    .font(Typo.ui(10.5, .semibold))
                    .foregroundStyle(category.palette.deep.opacity(0.7))
                Text(category.name)
                    .font(Typo.ui(14.5, .bold))
                    .foregroundStyle(category.palette.deep)
                    .lineLimit(2)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .frame(height: 128, alignment: .topLeading)
        .background(category.palette.tint, in: RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.tileRadius, style: .continuous))
    }
}

private struct SourceRow: View {
    let platform: Platform
    let count: Int
    let topCategories: String
    let swatches: [CategoryPalette]

    var body: some View {
        HStack(spacing: 12) {
            PlatformBadge(platform: platform, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .font(Typo.ui(15, .bold))
                    .foregroundStyle(Tokens.ink)
                Text("\(count) save\(count == 1 ? "" : "s") · \(topCategories)")
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tokens.inkFaint)
        }
        .padding(13)
        .cardSurface(radius: 18)
    }
}
