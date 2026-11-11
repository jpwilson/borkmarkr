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

/// The field, always at the top of Browse — a search box you have to reveal
/// is a search box people forget exists. Its scope chips (Topics · Subtopics
/// · Tags) appear only while searching (1.4): over the topic grid they were a
/// second row of controls that did nothing until you typed.
struct BrowseSearchBar: View {
    @Binding var query: String
    @Binding var scopes: SearchScope
    var focus: FocusState<Bool>.Binding
    let isSearching: Bool
    let onCancel: () -> Void

    private var active: Bool { focus.wrappedValue || !query.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                field
                if isSearching || focus.wrappedValue {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.clayQuiet)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.snap, value: active)

            if active || isSearching {
                chips
                    .transition(.opacity)
            }
        }
        .animation(Motion.snap, value: active || isSearching)
        .padding(.horizontal, Tokens.gutter)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Tokens.ink : Tokens.inkSecondary)
                .accessibilityHidden(true)
            TextField(Copy.searchPlaceholder, text: $query)
                .textRole(.body, color: Tokens.ink)
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
                        .font(.system(size: 17))
                        .foregroundStyle(Tokens.inkFaint)
                        .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .accessibilityLabel("Clear the search")
            }
        }
        .searchFieldSurface()
    }

    /// Topics · Subtopics · Tags. None selected is the old behaviour — every
    /// field at once — so the row reads as "narrow this", never as "pick one
    /// before I can search".
    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(SearchScope.ordered, id: \.rawValue) { scope in
                SearchChip(label: scope.label, active: scopes.contains(scope)) {
                    if scopes.contains(scope) { scopes.remove(scope) } else { scopes.insert(scope) }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One filter chip — the shared `FilterChip`, with the tap haptic and the
/// snap. Shared by the scope row and the source row so the two can never
/// drift into looking like different controls.
struct SearchChip: View {
    let label: String
    let active: Bool
    let tap: () -> Void

    var body: some View {
        FilterChip(label, isOn: active) {
            Haptics.tap()
            withAnimation(Motion.snap) { tap() }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            if !presentPlatforms.isEmpty { sourceRow }

            if results.isEmpty {
                empty
            } else {
                Text(SearchCopy.resultsHeadline(count: results.count, query: query, scopes: scopes))
                    .textRole(.meta)
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.top, 4)

                LazyVStack(spacing: 8) {
                    ForEach(results) { bookmark in
                        Button { onOpen(bookmark) } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .buttonStyle(PressableStyle())
                        .borkActions(bookmark)
                    }
                }
                .padding(.horizontal, Tokens.gutter)

                relatedSection
            }
        }
    }

    private var sourceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                SearchChip(label: "All sources", active: sources.isEmpty) { sources = [] }
                ForEach(presentPlatforms, id: \.self) { platform in
                    SearchChip(label: platform.name, active: sources.contains(platform)) {
                        if sources.contains(platform) { sources.remove(platform) }
                        else { sources.insert(platform) }
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No matches")
                .textRole(.sectionTitle, color: Tokens.ink)
            Text(SearchCopy.emptyDetail(scopes: scopes))
                .textRole(.body, color: Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if !scopes.isEmpty {
                Button(SearchCopy.clearScopes, action: onClearScopes)
                    .buttonStyle(.claySecondary)
                    .fixedSize()
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    /// Meaning-matched items the keyword pass missed. Additive on purpose —
    /// exact matches stay on top, where someone searching a remembered word
    /// expects them.
    @ViewBuilder
    private var relatedSection: some View {
        let exact = Set(results.map(\.id))
        let extras = related.filter { !exact.contains($0.id) }

        if !extras.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                    Text("Related").textRole(.label)
                }
                .foregroundStyle(Tokens.inkSecondary)
                .padding(.top, Tokens.sectionGap - 8)

                Text("Close in meaning, even though the words don't match.")
                    .textRole(.meta)
                    .padding(.bottom, 2)

                ForEach(extras) { hit in
                    Button { onOpen(hit.bookmark) } label: {
                        BookmarkRow(bookmark: hit.bookmark)
                    }
                    .buttonStyle(PressableStyle())
                    .borkActions(hit.bookmark)
                }
            }
            .padding(.horizontal, Tokens.gutter)
        }
    }
}
