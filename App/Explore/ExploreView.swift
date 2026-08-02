import SwiftUI
import SwiftData

/// Colourful category tiles → drill into subcategories. Only categories you've
/// actually saved into appear, so the grid grows with you instead of showing
/// sixteen empty boxes on day one.
struct ExploreView: View {
    @Query(sort: \Bookmark.savedAt, order: .reverse)
    private var bookmarks: [Bookmark]

    private var counts: [String: Int] {
        Dictionary(grouping: bookmarks.filter { !$0.isArchived && $0.categoryID != nil }) {
            $0.categoryID!
        }.mapValues(\.count)
    }

    private var used: [Category] {
        Taxonomy.all.filter { counts[$0.id, default: 0] > 0 }
    }

    private var uncategorised: [Bookmark] {
        bookmarks.filter { !$0.isArchived && $0.categoryID == nil }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if used.isEmpty && uncategorised.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Theme.inkSoft.opacity(0.5))
                        Text("Categories appear as you save")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(used) { category in
                            NavigationLink {
                                CategoryDetailView(category: category)
                            } label: {
                                CategoryTile(category: category, count: counts[category.id] ?? 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    if !uncategorised.isEmpty {
                        NavigationLink {
                            UncategorisedView()
                        } label: {
                            HStack {
                                Image(systemName: "tray")
                                Text("Uncategorised")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(uncategorised.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Theme.inkSoft)
                            .padding(16)
                            .card(radius: 18)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
            }
            .padding(.bottom, 110)
            .background(Theme.background)
            .navigationTitle("Explore")
        }
    }
}

private struct CategoryTile: View {
    let category: Category
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: category.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(hex: category.tintHex), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            Text(category.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("\(count) saved")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: category.tintHex).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: category.tintHex).opacity(0.18), lineWidth: 1)
        )
    }
}

/// Subcategory drill-down — "Fitness → Mobility/Running" from the design.
struct CategoryDetailView: View {
    let category: Category

    @Query(sort: \Bookmark.savedAt, order: .reverse)
    private var all: [Bookmark]

    @State private var selectedSub: String?

    private var inCategory: [Bookmark] {
        all.filter { !$0.isArchived && $0.categoryID == category.id }
    }

    private var visible: [Bookmark] {
        guard let selectedSub else { return inCategory }
        return inCategory.filter { $0.subcategory == selectedSub }
    }

    private var presentSubs: [String] {
        let used = Set(inCategory.compactMap(\.subcategory))
        return category.subcategories.filter { used.contains($0) }
    }

    var body: some View {
        ScrollView {
            if !presentSubs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        subPill("All", active: selectedSub == nil) { selectedSub = nil }
                        ForEach(presentSubs, id: \.self) { sub in
                            subPill(sub, active: selectedSub == sub) {
                                selectedSub = (selectedSub == sub) ? nil : sub
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
            }

            LazyVStack(spacing: 12) {
                ForEach(visible) { bookmark in
                    NavigationLink {
                        DetailView(bookmark: bookmark)
                    } label: {
                        BookmarkCard(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .background(Theme.background)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    /// "Sharing a set with someone" — a plain-text list is the format that
    /// survives being pasted into any messaging app.
    private var shareText: String {
        let lines = visible.prefix(50).map { "• \($0.title)\n  \($0.urlString)" }
        return "My \(category.name) saves from borkmarkr\n\n" + lines.joined(separator: "\n\n")
    }

    private func subPill(_ label: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? .white : Theme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? Color(hex: category.tintHex) : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Saves that never got a category — reachable so they don't become a black
/// hole, which is exactly the problem the app exists to solve.
struct UncategorisedView: View {
    @Query(sort: \Bookmark.savedAt, order: .reverse)
    private var all: [Bookmark]

    private var visible: [Bookmark] {
        all.filter { !$0.isArchived && $0.categoryID == nil }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(visible) { bookmark in
                    NavigationLink {
                        DetailView(bookmark: bookmark)
                    } label: {
                        BookmarkCard(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .background(Theme.background)
        .navigationTitle("Uncategorised")
        .navigationBarTitleDisplayMode(.inline)
    }
}
