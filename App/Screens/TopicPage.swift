import SwiftUI
import SwiftData

/// Topic page: tinted header, subcategory chips, cross-axis source chips, and
/// "Refine" tag chips that act as the third taxonomy level.
struct TopicPage: View {
    let category: Topic

    @Environment(\.accent) private var accent
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
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

    @State private var sub: String?
    @State private var source: Platform?
    @State private var tag: String?
    @State private var detail: Bookmark?

    private var inCategory: [Bookmark] {
        all.filter { $0.categoryID == category.id }
    }

    private var visible: [Bookmark] {
        inCategory.filter { item in
            if let sub, item.subcategory != sub { return false }
            if let source, item.platform != source { return false }
            if let tag, !item.tags.contains(tag) { return false }
            return true
        }
    }

    /// Includes subtopics you added yourself, so a custom one you filed into
    /// shows up here rather than vanishing from the chips.
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
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map(\.key)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(customTopics.first(where: { $0.id == category.id })?.name ?? category.name)
                            .font(Typo.display(28, .heavy))
                            .tracking(-0.6)
                            .foregroundStyle(category.palette.deep)
                        if let entry = customTopics.first(where: { $0.id == category.id }) {
                            Button {
                                renameDraft = entry.name
                                renaming = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(category.palette.deep.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(Copy.countedBorks(inCategory.count))
                        .font(Typo.ui(12.5, .medium))
                        .foregroundStyle(category.palette.deep.opacity(0.75))
                }
                Spacer()
                ShareLink(item: shareText) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                        Text("Share").font(Typo.ui(12.5, .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Tokens.ink, in: Capsule())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [category.palette.tint, category.palette.tint.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    /// Shares the current slice, named for where you are: "Fitness › Mobility".
    private var shareText: String {
        let title = sub.map { "\(category.name) › \($0)" } ?? category.name
        let lines = visible.prefix(50).map { "• \($0.title)\n  \($0.urlString)" }
        return "\(title) — from bookmarker\n\n" + lines.joined(separator: "\n\n")
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
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
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
