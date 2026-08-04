import SwiftUI
import SwiftData

/// Dual-axis search: free text plus multi-select Source and Topic filters.
///
/// **Engineering deviation.** The prototype re-scans every item across six
/// fields on every keystroke. That's fine for 26 items and janks badly at a few
/// thousand. Two changes: matching runs against the precomputed `searchBlob` on
/// the model (one `contains` per item), and input is debounced so a fast typist
/// triggers one pass rather than one per character.
struct SearchView: View {
    @Environment(\.accent) private var accent

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var all: [Bookmark]

    @State private var query = ""
    @State private var debounced = ""
    @State private var sources: Set<Platform> = []
    @State private var topics: Set<String> = []
    @State private var recents: [String] = []
    @State private var detail: Bookmark?

    private var isFiltering: Bool {
        !debounced.isEmpty || !sources.isEmpty || !topics.isEmpty
    }

    private var results: [Bookmark] {
        guard isFiltering else { return [] }
        let needle = debounced
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        return all.filter { item in
            if !sources.isEmpty && !sources.contains(item.platform) { return false }
            if !topics.isEmpty {
                guard let id = item.categoryID, topics.contains(id) else { return false }
            }
            guard !needle.isEmpty else { return true }
            return item.searchBlob.contains(needle)
        }
    }

    private var presentPlatforms: [Platform] {
        let used = Set(all.map(\.platform))
        return Platform.ordered.filter { used.contains($0) }
    }

    private var presentTopics: [Topic] {
        let used = Set(all.compactMap(\.categoryID))
        return Taxonomy.all.filter { used.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Search")
                    .font(Typo.display(32, .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(Tokens.ink)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                field

                if !presentPlatforms.isEmpty {
                    chipRow(title: "SOURCE") {
                        ForEach(presentPlatforms, id: \.self) { platform in
                            toggleChip(platform.name,
                                       active: sources.contains(platform),
                                       tint: Color(hex: "48505C")) {
                                if sources.contains(platform) { sources.remove(platform) }
                                else { sources.insert(platform) }
                            }
                        }
                    }
                }

                if !presentTopics.isEmpty {
                    chipRow(title: "TOPIC") {
                        ForEach(presentTopics) { topic in
                            toggleChip(topic.name,
                                       active: topics.contains(topic.id),
                                       tint: topic.palette.deep,
                                       bg: topic.palette.tint) {
                                if topics.contains(topic.id) { topics.remove(topic.id) }
                                else { topics.insert(topic.id) }
                            }
                        }
                    }
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

    private func chipRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) { content() }
                    .padding(.horizontal, 18)
            }
        }
    }

    private func toggleChip(_ label: String, active: Bool, tint: Color,
                            bg: Color? = nil, tap: @escaping () -> Void) -> some View {
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
                .tappableChip()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if !isFiltering {
            if recents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Tokens.inkFaint)
                    Text("Search everything you've saved")
                        .font(Typo.ui(14.5, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 56)
            } else {
                chipRow(title: "RECENT") {
                    ForEach(recents, id: \.self) { term in
                        toggleChip(term, active: false, tint: Tokens.inkSecondary) {
                            query = term; debounced = term
                        }
                    }
                }
            }
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
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func rememberQuery() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count > 1 else { return }
        recents.removeAll { $0 == term }
        recents.insert(term, at: 0)
        recents = Array(recents.prefix(6))
    }
}
