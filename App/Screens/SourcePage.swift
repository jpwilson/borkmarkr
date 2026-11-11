import SwiftUI
import SwiftData

/// Source page: the platform's own mark and name on paper, cross-axis topic
/// chips in each topic's colours, creator chips, then the rows.
///
/// 1.3 opened on a full-bleed dark brand gradient with a dark navigation bar.
/// 1.4 keeps one world of colour (design/SYSTEM.md): the platform is named by
/// its real mark, not by painting the screen its colours.
struct SourcePage: View {
    let platform: Platform

    @Environment(\.accent) private var accent
    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @State private var topic: String?
    /// A creator picked from the Creator row, as `displayAuthor` shows it.
    @State private var creator: String?
    @State private var detail: Bookmark?

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]

    private var inSource: [Bookmark] { all.filter { $0.platform == platform } }

    private var visible: [Bookmark] {
        inSource.filter { bookmark in
            (topic == nil || bookmark.categoryID == topic)
                && (creator == nil || bookmark.displayAuthor == creator)
        }
    }

    /// Creators with at least two borks here, most first — "that physio on
    /// TikTok" is how people look for a video. One-offs would make the row
    /// as long as the list.
    private var presentCreators: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: inSource.compactMap(\.displayAuthor)) { $0 }.mapValues(\.count)
        return counts.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(20)
            .map { (name: $0.key, count: $0.value) }
    }

    private var presentTopics: [Topic] {
        let counts = Dictionary(grouping: inSource.compactMap(\.categoryID)) { $0 }.mapValues(\.count)
        return MergedTaxonomy(topics: customTopics, subtopics: customSubtopics).allTopics
            .filter { (counts[$0.id] ?? 0) > 0 }
            .sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.top, 8)
                if !presentTopics.isEmpty {
                    topicRow.padding(.top, 10)
                }
                let creators = presentCreators
                if !creators.isEmpty {
                    creatorRow(creators).padding(.top, 4)
                }
                list.padding(.top, 12)
            }
            .padding(.bottom, Tokens.sectionGap)
        }
        .background(Tokens.paper)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
    }

    /// The mark, then the name in Bricolage with the count and what the
    /// platform is for.
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            PlatformBadge(platform: platform, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name)
                    .textRole(.screenTitle, color: Tokens.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("\(Copy.countedBorks(inSource.count)) · \(platform.descriptor)")
                    .textRole(.meta)
            }
            Spacer(minLength: 0)
        }
    }

    private var topicRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            BrowseChipLabel("Topic")
            BrowseChipRow {
                FilterChip("All", isOn: topic == nil) { topic = nil }
                // Each chip in its own topic's colours — the cross-axis link
                // back to the Topics side.
                ForEach(presentTopics) { category in
                    let active = topic == category.id
                    TopicChip(category.name, palette: category.palette, isOn: active) {
                        topic = active ? nil : category.id
                    }
                }
            }
        }
    }

    private func creatorRow(_ creators: [(name: String, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BrowseChipLabel("Creator")
            BrowseChipRow {
                ForEach(creators, id: \.name) { entry in
                    let active = creator == entry.name
                    FilterChip("\(entry.name) \(entry.count)", isOn: active) {
                        creator = active ? nil : entry.name
                    }
                    .accessibilityLabel("\(entry.name), \(Copy.countedBorks(entry.count))")
                }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            Text("Nothing here yet")
                .textRole(.body, color: Tokens.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(visible) { bookmark in
                    Button { detail = bookmark } label: {
                        // Platform badge omitted — every row here is this
                        // platform, so repeating it is noise.
                        BookmarkRow(bookmark: bookmark, showPlatformBadge: false)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .borkActions(bookmark)
                }
            }
            .padding(.horizontal, Tokens.gutter)
        }
    }
}
