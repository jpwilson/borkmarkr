import SwiftUI
import SwiftData
import StoreKit
import UIKit

/// Three steps: paste → reading → details.
///
/// **Engineering deviation.** The prototype fakes a 950ms delay to make the
/// categoriser look like it's thinking. Ours is genuinely instant, so there is
/// nothing to wait for — a fabricated spinner is a lie that costs a second of
/// the user's time on every single save. The reading step stays in the flow
/// because real link unfurling (fetching title/thumbnail/duration) will need
/// it; until that ships it passes straight through.
struct AddSheet: View {
    var initialURL: URL?
    let onSaved: (String) -> Void
    /// The signed-out limit was reached before this save could land. Hands the
    /// link back so the wall can raise and, after sign-up, the sheet can reopen
    /// with it already pasted. See `SaveLimit`.
    var onLimitReached: (URL) -> Void = { _ in }
    /// Only used to reach AI categorisation, which needs a signed-in session.
    /// Optional so the sheet still works in previews and when signed out.
    var account: Account?

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil })
    private var allBookmarks: [Bookmark]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    enum Step { case paste, reading, details }

    @State private var step = Step.paste
    @State private var urlText = ""
    @State private var title = ""
    @State private var author: String?
    @State private var categoryID: String?
    @State private var subcategory: String?
    @State private var tags: [String] = []
    @State private var userFiled = false
    @State private var userTagsEdited = false
    @State private var tagDraft = ""
    @State private var noteOpen = false
    @State private var note = ""
    @State private var noteDate = Date.now
    @State private var showingPicker = false
    @State private var error: String?
    @State private var imageURL: URL?
    @State private var duration: Int?
    @State private var postedAt: Date?
    /// Whether the title came from the page or was generated. Drives whether we
    /// present it as a fact or as something to fill in.
    @State private var titleWasFetched = false
    /// `og:description` — the full caption on Instagram and TikTok. Read for
    /// filing, shown nowhere, saved nowhere.
    @State private var pageDescription: String?
    /// How sure the filing is, and what it was, so the header above the topic
    /// chip can say "Sorted for you" only when that is true — and can tell a
    /// topic the user picked from one we suggested.
    @State private var evidence: Categorizer.Suggestion.Evidence = .none
    @State private var suggestedCategoryID: String?
    @State private var suggestedSubcategory: String?
    @State private var editingTitle = false
    @State private var selectedJourneyIDs: Set<String> = []
    @State private var showingNewJourney = false
    /// Whether the pasteboard holds text or a URL. Drives whether the paste
    /// card is on screen at all; see `refreshClipboard`.
    @State private var clipboardHasContent = false
    /// Set by "Save again anyway". The save that follows enriches the bork in
    /// place exactly as it always has; this is only so the card does not come
    /// straight back if that save is refused (the limit wall) rather than
    /// dismissing the sheet.
    @State private var saveAnyway = false
    /// The bork the duplicate card's "Open it" is showing.
    @State private var openingDuplicate: Bookmark?
    @FocusState private var urlFocused: Bool

    /// Borks that count against the signed-out limit. `allBookmarks` also
    /// feeds tag suggestions, where a waiting bork's tags are perfectly good
    /// history — so the filter lives here rather than in the query.
    private var liveCount: Int {
        allBookmarks.count { !$0.isWaiting }
    }

    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .paste: pasteStep
                case .reading: readingStep
                case .details: detailsStep
                }
            }
            .background(Tokens.paper)
            .navigationTitle(step == .details ? "Save to bookmarker" : "Add a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .sheet(isPresented: $showingPicker) {
            TopicPickerSheet(categoryID: Binding(get: { categoryID }, set: { categoryID = $0; userFiled = true }),
                subcategory: Binding(get: { subcategory }, set: { subcategory = $0; userFiled = true }))
                .environment(\.accent, accent)
        }
        .sheet(isPresented: $showingNewJourney) {
            NewMissionSheet().environment(\.accent, accent)
        }
        // Where they change the topic, add a note, or delete it — the sheet
        // they would have opened from the Library, opened from here instead.
        .sheet(item: $openingDuplicate) { bork in
            DetailSheet(bookmark: bork).environment(\.accent, accent)
        }
        .onAppear {
            if let initialURL, urlText.isEmpty {
                urlText = initialURL.absoluteString
                submit()
            }
            #if DEBUG
            // Let this sheet finish presenting first; SwiftUI drops a
            // presentation raised into another sheet's transition.
            if ScreenshotDefaults.pickerQuery != nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    showingPicker = true
                }
            }
            #endif
        }
    }

    // MARK: Step 1 — paste

    /// No "Fetch preview" button. Paste a link and it just goes — a button
    /// that only ever has one sensible outcome is a step, not a choice.
    ///
    /// Never read `UIPasteboard` ourselves. A custom Button that peeks at it
    /// is what produced "bookmarker would like to paste from Chimoco" on every
    /// tap — and users would get the same dialog from Instagram, Safari, etc.
    /// `PasteButton` is a system control; iOS grants paste without asking.
    /// Long-press in the field, or the keyboard paste key, also never prompts.
    ///
    /// `hasURLs`, `hasStrings` and `detectPatterns` are the one exception, and
    /// they are not an exception to the rule so much as the reason it can be
    /// kept: they report which *types* and which *patterns* are on the
    /// pasteboard without exposing a single byte of the value, which is
    /// precisely what the paste alert is gated on. They are how the card below
    /// knows whether to exist at all. See `refreshClipboard`.
    private var pasteStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Paste any link", text: $urlText, axis: .vertical)
                    .font(Typo.mono(13.5))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($urlFocused)
                    .padding(14)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(parsedURL != nil ? accent.base.opacity(0.5) : Tokens.hairline,
                                    lineWidth: parsedURL != nil ? 1.5 : 1)
                    )

                if urlText.isEmpty && clipboardHasContent {
                    HStack(spacing: 12) {
                        Text("Paste the link you copied")
                            .font(Typo.ui(13, .semibold))
                            .foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        PasteButton(payloadType: PastedLink.self) { links in
                            applyPasted(links.first)
                        }
                        .labelStyle(.titleAndIcon)
                        .tint(accent.base)
                        .buttonBorderShape(.capsule)
                        // The control sizes itself from its own label, and it
                        // re-renders when the pasteboard changes underneath it.
                        // A floor under that keeps the card the same shape
                        // through the re-render instead of twitching; a floor
                        // rather than a fixed size so a longer system label in
                        // another language is never clipped.
                        .frame(minWidth: 104, minHeight: 36, alignment: .trailing)
                        .accessibilityLabel("Paste the link you copied")
                    }
                    .padding(13)
                    .cardSurface(radius: 16)
                }

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                    Text("Saving from another app? Use the share sheet.")
                        .font(Typo.ui(12.5, .medium))
                }
                .foregroundStyle(Tokens.inkSecondary)
            }
            .padding(18)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            urlFocused = true
        }
        .onAppear(perform: refreshClipboard)
        // `changedNotification` only fires for changes this process can see, so
        // it catches a copy made inside the app and nothing else. Coming back
        // from Instagram is the case that matters and it arrives as a scene
        // phase change instead — both are needed, neither is enough.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            refreshClipboard()
        }
        // Debounced so it fires once you've finished pasting, not on every
        // character of a typed URL.
        .task(id: urlText) {
            guard parsedURL != nil, step == .paste else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, step == .paste else { return }
            submit()
        }
    }

    /// Is there a link on the pasteboard worth offering to paste?
    ///
    /// The old card was unconditional, so an empty clipboard got "Have a link
    /// copied?" over a control that could not be tapped — a prompt to do
    /// something the app had already decided was impossible. Now the card is
    /// simply absent unless there is a link to paste.
    ///
    /// Three questions, none of which reads a byte or raises the "would like
    /// to paste from…" dialog:
    ///
    /// - `hasURLs` — a URL-typed item, which is what "Copy link" writes. Free
    ///   and synchronous; it is the common case and it ends here.
    /// - `hasStrings` — is there any text at all. Note that an *empty* string
    ///   still counts, which is why this cannot be the last word: pasteboards
    ///   in that state are common and the card would be back to lying.
    /// - `detectPatterns(for: [.probableWebURL])` — is there a link somewhere
    ///   *inside* that text. This is the API Apple added for exactly this
    ///   question; it reports the pattern, never the value, and so does not
    ///   notify the user. It is asynchronous, hence the `Task`.
    ///
    /// If detection fails the card is shown. A failure is not evidence that
    /// there is no link, and hiding the only paste affordance on a maybe is
    /// worse than offering one that turns out to have nothing behind it.
    private func refreshClipboard() {
        let board = UIPasteboard.general
        if board.hasURLs {
            clipboardHasContent = true
            return
        }
        guard board.hasStrings else {
            clipboardHasContent = false
            return
        }
        Task { @MainActor in
            clipboardHasContent = await Self.pasteboardHasProbableLink()
        }
    }

    /// `detectPatterns` is callback-shaped; this is the same call as an await.
    ///
    /// The handler is `@Sendable` on purpose. UIKit delivers it on its own
    /// pasteboard queue, and a closure written inside a `@MainActor` member
    /// otherwise inherits that isolation and traps the moment it runs.
    @MainActor
    private static func pasteboardHasProbableLink() async -> Bool {
        let board = UIPasteboard.general
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            board.detectPatterns(for: [.probableWebURL]) { @Sendable result in
                continuation.resume(returning: (try? result.get())?.contains(.probableWebURL) ?? true)
            }
        }
    }

    private func applyPasted(_ link: PastedLink?) {
        guard let url = link?.url else { return }
        urlText = url.absoluteString
    }

    // MARK: Step 2 — reading

    private var readingStep: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Reading the link…")
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(Tokens.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Step 3 — details

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let duplicate {
                    duplicateCard(duplicate)
                } else {
                    previewRow
                    sortedForYou
                    journeyAttach
                    titleField
                    noteSection
                    saveButton
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
    }

    // MARK: Already saved

    /// The bork this link would land on, if it is already in the library.
    ///
    /// `allBookmarks` is already filtered to `deletedAt == nil`, so a bork you
    /// deleted and are saving again reads as new — which is the right answer;
    /// `DuplicateSave.match` checks the tombstone again anyway, because that
    /// rule is the one worth being sure of.
    private var duplicate: Bookmark? {
        guard !saveAnyway, let url = parsedURL else { return nil }
        return DuplicateSave.match(
            stableID: Bookmark.stableID(for: url),
            in: allBookmarks,
            id: \.id,
            deletedAt: \.deletedAt
        )
    }

    /// Save over the bork that is already there.
    ///
    /// Their filing wins. `Store.save` takes any topic the draft carries, and
    /// the draft carries the categoriser's guess for this link — so without
    /// this, "save again" would quietly re-file a bork the user had already
    /// put somewhere on purpose, which is a worse version of the bug this
    /// whole card exists for. Everything else — a title that reads now, a
    /// cover, a duration, new tags — enriches exactly as it always has.
    private func saveAgain(over bork: Bookmark) {
        if let existing = bork.categoryID {
            categoryID = existing
            subcategory = bork.subcategory
        }
        saveAnyway = true
        save()
    }

    /// Not a warning and not a wall — a fact and two ways forward.
    ///
    /// Re-saving used to merge into the existing bork with nothing on screen to
    /// say it had, so the two things someone actually wants here are the two
    /// buttons: go and look at the one you have (and change where it's filed,
    /// which is what people usually meant), or go ahead and save over it.
    /// "Bork it" is gone in this state rather than disabled: a live button that
    /// does something you weren't told about is what caused this.
    @ViewBuilder
    private func duplicateCard(_ bork: Bookmark) -> some View {
        let topic = Taxonomy.category(id: bork.categoryID)
        let palette = topic?.palette ?? NeutralPalette.value
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: bork.savedAt),
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0
        let when = DuplicateSave.savedPhrase(daysAgo: days) ?? "saved \(RelativeDate.calendar(bork.savedAt))"
        let filed = DuplicateSave.filedPhrase(topic: topic?.name, subtopic: bork.subcategory)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Already in your library")
                    .font(Typo.display(16, .semibold))
                    .foregroundStyle(Tokens.ink)
                Text("\(filed) · \(when)")
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                CoverImage(url: bork.imageURL, palette: palette)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(bork.title.isEmpty ? "Untitled" : bork.title)
                        .font(Typo.display(14, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(bork.author ?? bork.url?.host ?? bork.platform.name)
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 9) {
                Button { openingDuplicate = bork } label: {
                    Text("Open it")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { saveAgain(over: bork) } label: {
                    Text("Save again anyway")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous)
                                .stroke(Tokens.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .cardSurface(radius: 18)
    }

    /// The actual card you're about to save — thumbnail, real title, author.
    /// This is the confirmation: you see the thing, not a form about the thing.
    @ViewBuilder
    private var previewRow: some View {
        if let url = parsedURL {
            let platform = Platform.detect(from: url)
            let palette = Taxonomy.category(id: categoryID)?.palette ?? NeutralPalette.value

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    CoverImage(url: imageURL, palette: palette)
                        .frame(height: 150)
                        .clipped()
                    HStack(alignment: .top) {
                        PlatformBadge(platform: platform, size: 24, pageURL: url)
                        Spacer()
                        if let duration {
                            let label = String(format: "%d:%02d", duration / 60, duration % 60)
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                                Text(label).font(Typo.ui(10.5, .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                        }
                    }
                    .padding(10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(Typo.display(15, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(author ?? url.host ?? platform.name)
                            .font(Typo.ui(11.5, .medium))
                            .foregroundStyle(Tokens.inkMeta)
                            .lineLimit(1)
                        if !titleWasFetched {
                            Text("· couldn't read the page")
                                .font(Typo.ui(11))
                                .foregroundStyle(Tokens.inkFaint)
                        }
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardSurface(radius: 18)
        }
    }

    /// What the header above the topic chip should claim.
    ///
    /// Seb's two saves were shown as "✨ Sorted for you" over a wrong topic.
    /// The block now says exactly as much as the evidence supports: a real
    /// match is sorted, a thin one is a guess and says so, nothing is a
    /// question, and a topic you picked yourself is yours.
    private enum FilingState { case sorted, guess, unknown, yours }

    private var filingState: FilingState {
        if let categoryID, categoryID != suggestedCategoryID || subcategory != suggestedSubcategory {
            return .yours
        }
        switch evidence {
        case .strong: return .sorted
        case .thin: return .guess
        case .none: return .unknown
        }
    }

    private var filingHeader: (icon: String, copy: String) {
        switch filingState {
        case .sorted: ("sparkles", "Sorted for you")
        case .guess: ("sparkle", "Our best guess — tap to change")
        case .unknown: ("questionmark.circle", "Where does this go?")
        case .yours: ("checkmark.circle", "Filed by you")
        }
    }

    private var sortedForYou: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: filingHeader.icon).font(.system(size: 12, weight: .bold))
                Text(filingHeader.copy)
                    .font(Typo.ui(13, .bold))
                Spacer()
            }
            .foregroundStyle(accent.deep)
            .animation(.easeOut(duration: 0.2), value: filingHeader.copy)

            Button { showingPicker = true } label: {
                HStack(spacing: 6) {
                    if let category = Taxonomy.category(id: categoryID) {
                        Text(subcategory.map { "\(category.name) › \($0)" } ?? category.name)
                            .font(Typo.ui(13.5, .semibold))
                            .foregroundStyle(category.palette.deep)
                    } else {
                        Text("Pick a topic")
                            .font(Typo.ui(13.5, .semibold))
                            .foregroundStyle(Tokens.inkSecondary)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tokens.inkMeta)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Taxonomy.category(id: categoryID)?.palette.tint ?? Tokens.mutedControl, in: Capsule())
            }
            .buttonStyle(.plain)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                                userTagsEdited = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("#\(tag)").font(Typo.ui(11.5, .semibold))
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .foregroundStyle(accent.deep)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(accent.tint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("+ tag", text: $tagDraft)
                    .font(Typo.ui(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitTag)
                Button("Add", action: commitTag)
                    .font(Typo.ui(12.5, .semibold))
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Tokens.surface, in: Capsule())
            .overlay(Capsule().stroke(Tokens.hairline, lineWidth: 1))

            if !tagSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagSuggestions, id: \.self) { suggestion in
                            Button {
                                tagDraft = suggestion
                                commitTag()
                            } label: {
                                Text("#\(suggestion)")
                                    .font(Typo.ui(11.5, .semibold))
                                    .foregroundStyle(Tokens.inkSecondary)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Tokens.mutedControl, in: Capsule())
                            }
                            .buttonStyle(ChipStyle())
                        }
                    }
                }
            }

            // When a tag clearly belongs somewhere in the taxonomy and nothing
            // is chosen yet, offer it rather than silently filing it.
            if let placement = tagPlacement {
                Button {
                    categoryID = placement.categoryID
                    userFiled = true
                    subcategory = placement.subcategory
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .bold))
                        Text("File under \(placement.label)?")
                            .font(Typo.ui(12, .semibold))
                        Spacer()
                    }
                    .foregroundStyle(accent.deep)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same tinted card in every state; only a settled answer gets the
        // full tint. A guess and a question sit a shade quieter.
        .background(accent.tint.opacity(filingState == .sorted || filingState == .yours ? 0.55 : 0.4),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.base.opacity(0.25), lineWidth: 1)
        )
    }

    private var journeyAttach: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALSO ON A SIDE QUEST")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            Text("Optional. Topics file what this is. A side quest is why you kept it.")
                .font(Typo.ui(12))
                .foregroundStyle(Tokens.inkMeta)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(journeys) { journey in
                        let on = selectedJourneyIDs.contains(journey.id)
                        Button {
                            if on { selectedJourneyIDs.remove(journey.id) }
                            else { selectedJourneyIDs.insert(journey.id) }
                        } label: {
                            Text(journey.title)
                                .font(Typo.ui(12, .semibold))
                                .foregroundStyle(on ? .white : Tokens.inkSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(on ? accent.base : Tokens.mutedControl, in: Capsule())
                        }
                        .buttonStyle(ChipStyle())
                    }
                    Button { showingNewJourney = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text(Copy.newSideQuest)
                                .font(Typo.ui(12, .semibold))
                        }
                        .foregroundStyle(accent.deep)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Collapsed by default. The whole point is that you don't type — this is
    /// here for the times the fetched title is wrong, not as a step in the flow.
    @ViewBuilder
    private var titleField: some View {
        if editingTitle {
            titleEditor
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { editingTitle = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                    Text(titleWasFetched ? "Edit title" : "Write a title")
                        .font(Typo.ui(13, .semibold))
                    Spacer()
                }
                .foregroundStyle(Tokens.inkSecondary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TITLE")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            TextField("What is this?", text: $title, axis: .vertical)
                .font(Typo.ui(14.5))
                .padding(14)
                .cardSurface(radius: 16)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: $noteOpen.animation(.easeOut(duration: 0.18))) {
                Text("Add a note")
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            if noteOpen {
                TextField("Why does this matter?", text: $note, axis: .vertical)
                    .font(Typo.ui(14.5))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(
                        LinearGradient(colors: [Tokens.noteTop, Tokens.noteBottom],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Tokens.noteBorder, lineWidth: 1)
                    )
                DatePicker("Note date", selection: $noteDate, displayedComponents: .date)
                    .font(Typo.ui(12.5, .medium))
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(Copy.saveVerb)
                .font(Typo.ui(15, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                .shadow(color: accent.base.opacity(0.34), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// One tap. Paste the link, we read the page, everything comes back filled
    /// in — you only touch it if you disagree.
    private func submit() {
        guard let url = parsedURL else { return }
        step = .reading

        Task { @MainActor in
            // Real fetch: oEmbed for YouTube, Open Graph for most of the web.
            let preview = await LinkPreview.fetch(for: url)

            imageURL = preview.imageURL
            duration = preview.durationSeconds
            postedAt = preview.publishedAt
            author = preview.author ?? Categorizer.fallbackAuthor(for: url)
            pageDescription = preview.description

            // A real page title, or nothing — never a routing word dressed up
            // as a description.
            let fetchedTitle = preview.title
            title = fetchedTitle ?? Categorizer.fallbackTitle(for: url)
            titleWasFetched = fetchedTitle != nil

            // Categorise against the real title when we have one; a genuine
            // headline is a far better signal than a URL slug. The description
            // carries the caption and its hashtags — the author's own filing.
            let suggestion = Categorizer.suggest(
                url: url, title: title, description: preview.description, author: preview.author
            )
            categoryID = suggestion.categoryID
            subcategory = suggestion.subcategory
            tags = suggestion.tags
            evidence = suggestion.evidence
            suggestedCategoryID = suggestion.categoryID
            suggestedSubcategory = suggestion.subcategory

            withAnimation(.easeOut(duration: 0.22)) { step = .details }

            // The offline answer is already on screen and editable. If it came
            // back empty or thin, ask the model — but never make the user wait
            // for it, and never let it overwrite a choice they've since made.
            await refineCategory(url: url, offline: suggestion)
        }
    }

    /// Second-pass categorisation for the links keyword matching can't place.
    ///
    /// Runs after the sheet is already interactive, so the cost is a chip
    /// changing under a thumb that hasn't moved yet rather than a spinner.
    /// Silent on every failure: signed out, offline, quota spent, server down —
    /// all of them just leave the offline answer where it is.
    private func refineCategory(url: URL, offline: Categorizer.Suggestion) async {
        guard !offline.isConfident else { return }
        guard let account, let session = await account.currentSession() else { return }

        let context = SmartCategorizer.Context(
            url: url,
            title: title,
            author: author,
            description: pageDescription,
            userTags: tags.filter { !offline.tags.contains($0) }
        )
        guard let better = await SmartCategorizer.suggest(context, session: session) else { return }

        // The user may have picked a topic themselves while this was in
        // flight. Their choice wins — always.
        guard !userFiled, categoryID == offline.categoryID, subcategory == offline.subcategory else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            categoryID = better.categoryID
            subcategory = better.subcategory
            evidence = better.evidence
            suggestedCategoryID = better.categoryID
            suggestedSubcategory = better.subcategory
            // Merge rather than replace: tags the user typed in the meantime stay.
            for tag in better.tags where !userTagsEdited && !tags.contains(tag) && !Platform.isSiteName(tag) {
                tags.append(tag)
            }
        }
    }

    /// Tags you've used on this category + subcategory, newest first — not
    /// the library's global greatest hits. Platform names stay out because
    /// the source is already on the card.
    private var tagSuggestions: [String] {
        TagRecency.suggestions(
            in: allBookmarks.map {
                .init(categoryID: $0.categoryID, subcategory: $0.subcategory, tags: $0.tags, at: $0.updatedAt)
            },
            categoryID: categoryID,
            subcategory: subcategory,
            excluding: Set(tags),
            prefix: tagDraft
        )
    }

    /// Where the tags you've added would place this in the taxonomy — e.g.
    /// "fighting" lands on Sports › Combat sports. Uses the same offline
    /// classifier as the URL, run over the tag words instead.
    private var tagPlacement: (categoryID: String, subcategory: String?, label: String)? {
        guard categoryID == nil, !tags.isEmpty else { return nil }
        guard let url = parsedURL else { return nil }
        let suggestion = Categorizer.suggest(url: url, title: tags.joined(separator: " "))
        guard let id = suggestion.categoryID, let topic = Taxonomy.category(id: id) else { return nil }
        let label = suggestion.subcategory.map { "\(topic.name) › \($0)" } ?? topic.name
        return (id, suggestion.subcategory, label)
    }

    private func commitTag() {
        let cleaned = tagDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { tagDraft = ""; return }
        tags.append(cleaned)
        userTagsEdited = true
        tagDraft = ""
    }

    private func save() {
        guard let url = parsedURL else { return }

        // The button still works — it just does something else. Disabling it
        // would leave someone tapping a dead control with no idea why, which
        // is the one outcome worse than a sheet. Nothing typed is lost: the
        // URL goes back to `RootView`, and after sign-up the sheet reopens
        // with it already in the field.
        //
        // This is the last line of defence rather than the usual path — the +
        // button raises the wall before the sheet ever opens. It fires when
        // the limit is reached *while* this sheet is up: a share draining in
        // the background, or a second device syncing.
        if SaveLimit.shouldWall(liveCount: liveCount, signedIn: account?.isSignedIn ?? false) {
            onLimitReached(url)
            dismiss()
            return
        }

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Categorizer.fallbackTitle(for: url)
            : title

        var draft = BookmarkDraft(
            url: url, title: finalTitle, author: author,
            platform: Platform.detect(from: url), kind: nil,
            categoryID: categoryID, subcategory: subcategory, tags: tags,
            text: SavedContent.excerpt(pageDescription),
            durationSeconds: duration,
            noteText: noteOpen && !note.isEmpty ? note : nil,
            noteDate: noteOpen && !note.isEmpty ? noteDate : nil
        )

        draft.imageURLString = imageURL?.absoluteString
        draft.postedAt = postedAt
        draft.previewFetched = true
        draft.filingSource = userFiled ? "user" : "automatic"
        draft.tagsEdited = userTagsEdited
        draft.titleEdited = editingTitle

        do {
            let saved = try Store.save(draft, in: context)
            if !selectedJourneyIDs.isEmpty {
                for journey in journeys where selectedJourneyIDs.contains(journey.id) {
                    journey.attach(saved.id)
                }
                try? context.save()
            }
            let where_ = Taxonomy.category(id: categoryID).map { category in
                subcategory.map { "\(category.name) › \($0)" } ?? category.name
            } ?? "your library"
            dismiss()
            onSaved("Saved to \(where_)")
            ReviewPrompter.reached(.borkSaved, requestReview)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
