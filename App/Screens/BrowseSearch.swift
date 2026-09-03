import SwiftUI

/// Search, as it lives at the top of Browse.
///
/// **Why Search stopped being a tab.** It was one of five, and it was the only
/// one that opened onto nothing — an empty field, a recents list most people
/// never had, and no library in sight. Meanwhile Browse *is* the screen you are
/// on when you are looking for something, and it made you leave it to type. So
/// the field moved to where the looking happens: results replace the topic
/// grid, clearing the field puts the grid back, and the dock got the slot back
/// for a tab that had something to show (Revisit).
///
/// **Engineering deviations carried over from the old Search tab.** Matching
/// still runs against the precomputed `searchBlob` rather than re-scanning six
/// fields per keystroke, and input is still debounced so a fast typist triggers
/// one pass rather than one per character.
///
/// Two things the old tab had are deliberately gone. **Recents** had no home
/// once the empty state became the topic grid — there is no longer a screen
/// whose default content was a list of words you typed. And the **Topic and
/// Side quest filter axes** are replaced by the scope chips: filtering to a
/// topic is what Browse's grid already does, and a second, differently-shaped
/// filter system stacked above it made one screen look like two apps.

// MARK: - Field

/// The field and its scope chips. Always visible at the top of Browse, whether
/// or not anything is typed — a search box you have to reveal is a search box
/// people forget exists.
struct BrowseSearchBar: View {
    @Binding var query: String
    @Binding var scopes: SearchScope
    var focus: FocusState<Bool>.Binding
    let isSearching: Bool
    let onCancel: () -> Void

    @Environment(\.accent) private var accent

    private var active: Bool { focus.wrappedValue || !query.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                field
                if isSearching || focus.wrappedValue {
                    Button("Cancel", action: onCancel)
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(accent.deep)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.snap, value: active)

            chips
        }
        .padding(.horizontal, 18)
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? accent.base : Tokens.inkFaint)
            TextField(Copy.searchPlaceholder, text: $query)
                .font(Typo.ui(14.5))
                .foregroundStyle(Tokens.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused(focus)
                // Hardware keyboards exist — on iPad, on a Mac, and on anyone's
                // desk with a phone propped next to it. Escape means cancel.
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Tokens.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(active ? accent.base.opacity(0.55) : Tokens.hairline,
                        lineWidth: active ? 1.5 : 1)
        )
    }

    /// Topics · Subtopics · Tags. None selected is the old behaviour — every
    /// field at once — so the row reads as "narrow this", never as "pick one
    /// before I can search".
    private var chips: some View {
        HStack(spacing: 7) {
            ForEach(SearchScope.ordered, id: \.rawValue) { scope in
                SearchChip(label: scope.label, active: scopes.contains(scope)) {
                    if scopes.contains(scope) { scopes.remove(scope) } else { scopes.insert(scope) }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Search scope")
    }
}

/// One filter chip. Shared by the scope row and the source row so the two can
/// never drift into looking like different controls.
struct SearchChip: View {
    let label: String
    let active: Bool
    let tap: () -> Void

    var body: some View {
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
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - Results

/// What replaces the topic grid while a query is active.
struct BrowseSearchResults: View {
    let results: [Bookmark]
    let query: String
    let scopes: SearchScope
    @Binding var sources: Set<Platform>
    let presentPlatforms: [Platform]
    let related: [SemanticIndex.Hit]
    let onOpen: (Bookmark) -> Void
    let onClearScopes: () -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !presentPlatforms.isEmpty { sourceRow }

            if results.isEmpty {
                empty
            } else {
                Text(SearchCopy.resultsHeadline(count: results.count, query: query, scopes: scopes))
                    .font(Typo.ui(11.5, .semibold))
                    .foregroundStyle(Tokens.inkMeta)
                    .padding(.horizontal, 18)

                LazyVStack(spacing: 9) {
                    ForEach(results) { bookmark in
                        Button { onOpen(bookmark) } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 18)

                relatedSection
            }
        }
    }

    private var sourceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                SearchChip(label: "All sources", active: sources.isEmpty) { sources = [] }
                ForEach(presentPlatforms, id: \.self) { platform in
                    SearchChip(label: platform.name, active: sources.contains(platform)) {
                        if sources.contains(platform) { sources.remove(platform) }
                        else { sources.insert(platform) }
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No matches")
                .font(Typo.ui(15, .bold))
                .foregroundStyle(Tokens.ink)
            Text(SearchCopy.emptyDetail(scopes: scopes))
                .font(Typo.ui(13))
                .foregroundStyle(Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if !scopes.isEmpty {
                Button(action: onClearScopes) {
                    Text(SearchCopy.clearScopes)
                        .font(Typo.ui(13.5, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Meaning-matched items the keyword pass missed. Additive on purpose —
    /// exact matches stay on top, where someone searching a remembered word
    /// expects them.
    @ViewBuilder
    private var relatedSection: some View {
        let exact = Set(results.map(\.id))
        let extras = related.filter { !exact.contains($0.id) }

        if !extras.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                    Text("RELATED")
                        .font(Typo.ui(10, .heavy)).tracking(0.6)
                }
                .foregroundStyle(accent.deep)
                .padding(.top, 18)

                Text("Close in meaning, even though the words don't match.")
                    .font(Typo.ui(12))
                    .foregroundStyle(Tokens.inkSecondary)

                ForEach(extras) { hit in
                    Button { onOpen(hit.bookmark) } label: {
                        BookmarkRow(bookmark: hit.bookmark)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 18)
        }
    }
}
