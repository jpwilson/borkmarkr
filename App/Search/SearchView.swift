import SwiftUI
import SwiftData

/// "You should be able to search all of them" — live filtering across titles,
/// tags, notes, authors and category names, with source and category filters
/// stacked on top.
struct SearchView: View {
    @Environment(\.brandAccent) private var accent

    @Query(sort: \Bookmark.savedAt, order: .reverse)
    private var all: [Bookmark]

    @State private var query = ""
    @State private var sourceFilter: Platform?
    @State private var categoryFilter: String?

    private var results: [Bookmark] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()

        return all.filter { bookmark in
            guard !bookmark.isArchived else { return false }
            if let sourceFilter, bookmark.platform != sourceFilter { return false }
            if let categoryFilter, bookmark.categoryID != categoryFilter { return false }
            guard !needle.isEmpty else { return true }

            if bookmark.title.lowercased().contains(needle) { return true }
            if bookmark.tags.contains(where: { $0.contains(needle) }) { return true }
            if let note = bookmark.note, note.lowercased().contains(needle) { return true }
            if let author = bookmark.author, author.lowercased().contains(needle) { return true }
            if let name = bookmark.category?.name.lowercased(), name.contains(needle) { return true }
            if let sub = bookmark.subcategory?.lowercased(), sub.contains(needle) { return true }
            if bookmark.urlString.lowercased().contains(needle) { return true }
            return false
        }
    }

    private var presentPlatforms: [Platform] {
        let used = Set(all.filter { !$0.isArchived }.map(\.platform))
        return Platform.allCases.filter { used.contains($0) }
    }

    private var presentCategories: [Category] {
        let used = Set(all.filter { !$0.isArchived }.compactMap(\.categoryID))
        return Taxonomy.all.filter { used.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !presentPlatforms.isEmpty {
                        pillRow(title: "Source") {
                            HStack(spacing: 8) {
                                ForEach(presentPlatforms, id: \.self) { platform in
                                    togglePill(platform.label, symbol: platform.symbol,
                                               tint: Color(hex: platform.tintHex),
                                               active: sourceFilter == platform) {
                                        sourceFilter = sourceFilter == platform ? nil : platform
                                    }
                                }
                            }
                        }
                    }

                    if !presentCategories.isEmpty {
                        pillRow(title: "Category") {
                            HStack(spacing: 8) {
                                ForEach(presentCategories) { category in
                                    togglePill(category.name, symbol: category.symbol,
                                               tint: Color(hex: category.tintHex),
                                               active: categoryFilter == category.id) {
                                        categoryFilter = categoryFilter == category.id ? nil : category.id
                                    }
                                }
                            }
                        }
                    }

                    if results.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Theme.inkSoft.opacity(0.5))
                            Text(query.isEmpty ? "Search everything you've saved" : "No matches")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 16)

                        LazyVStack(spacing: 8) {
                            ForEach(results) { bookmark in
                                NavigationLink {
                                    DetailView(bookmark: bookmark)
                                } label: {
                                    BookmarkCard(bookmark: bookmark, compact: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(Theme.background)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Titles, tags, notes, people")
        }
    }

    private func pillRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSoft.opacity(0.7))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                content().padding(.horizontal, 16)
            }
        }
    }

    private func togglePill(_ label: String, symbol: String, tint: Color,
                            active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? .white : tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(active ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
