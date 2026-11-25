import SwiftUI
import SwiftData
import StoreKit
import UIKit

/// Two taps: paste, then file (Quick File).
///
/// **Tap 1 saves.** A paste (the paste card, or a paste-sized jump in the
/// field), Return, or a link handed in (`initialURL`) writes the bork at once,
/// with the best offline guess stored as `"automatic"`, before the page has
/// been read. There is no "Reading the link…" step any more: nothing waits on
/// the network. A link that is being *typed* is different — when it pauses,
/// its page is read and a "Bork it" button is offered, and nothing is saved
/// until that is tapped, so a half-typed link never becomes a bork.
///
/// **Tap 2 chooses.** The sheet becomes the saved card, the Quick File dial and
/// its reason line. A tap on the dial is written as `"user"` at once and the
/// sheet stays: the refine panel takes the reason line's place (subtopic
/// chips, tag chips, "+ Tag") and Done is pinned at the bottom. Another
/// topic on the dial re-chooses. Done, its six-second drain (stopped for
/// good by any touch after the choice) or a swipe closes the sheet with a
/// "Saved to Fitness › Running · Undo" toast, whose Undo takes the whole
/// save back. Before a choice, the toolbar's "Done" keeps the guess.
/// The preview, on-screen text and the model's answer arrive while the dial
/// is up and re-rank it (an untouched dial re-deals, a touched one only gains
/// a ✨), and update the saved bork through `Store.save`'s merge rules —
/// while its filing is still the app's, never over yours.
struct AddSheet: View {
    var initialURL: URL?
    /// What to say once the sheet has gone, and how to take it back (the
    /// toast's Undo), when it can be taken back.
    let onSaved: (String, (() -> Void)?) -> Void
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

    /// Your own topics, for the order the dial breaks ties in.
    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]

    /// Your own subtopics, for the refine panel's chips.
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]

    enum Step { case paste, details }

    @State private var step = Step.paste
    @State private var urlText = ""
    @State private var title = ""
    @State private var author: String?
    @State private var noteOpen = false
    @State private var note = ""
    @State private var noteDate = Date.now
    /// The full topic list, from the dial's More…. A pick there files.
    @State private var showingPicker = false
    @State private var pickedTopic: String?
    @State private var pickedSub: String?
    @State private var error: String?
    @State private var imageURL: URL?
    @State private var duration: Int?
    @State private var postedAt: Date?
    /// Whether the title came from the page or was generated. Drives whether we
    /// present it as a fact or as something to fill in.
    @State private var titleWasFetched = false
    /// The preview ran out of time. The bork saves without one, and
    /// enrichment fills it in afterwards.
    @State private var previewTimedOut = false
    /// The page has been read: before tap 1 for a typed link, after it for
    /// everything else.
    @State private var previewFetched = false
    /// This sheet has just saved its link. It is on its way out, and the
    /// bork it made must not read, mid-dismissal, as "Already in your
    /// library" — which it did, for the half second the sheet slid away.
    @State private var didSave = false
    /// `og:description` — the full caption on Instagram and TikTok. Read for
    /// filing, shown nowhere, saved nowhere.
    @State private var pageDescription: String?
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

    // MARK: Quick File

    /// The bork tap 1 wrote. Everything after it edits a save that exists.
    @State private var saved: Bookmark?
    /// Tap 1 made it, so "Remove this save" may delete it. False when it
    /// re-saved a bork that was already in the library.
    @State private var createdHere = false
    /// The dial: ranked at tap 1 from the link alone, re-ranked as the
    /// preview, the on-screen text and the model's answer land.
    @State private var dial: QuickFileModel?
    @State private var memory = FilingMemory.empty
    @State private var order: [String] = []
    /// A re-saved bork's own filing, which leads its ring.
    @State private var pin: FilingPin?
    @State private var aiAnswer: Categorizer.Suggestion?
    @State private var onScreenText: String?
    /// A typed link has paused: its page is being read and "Bork it" is on
    /// offer. Nothing is saved until it is tapped.
    @State private var typedReady = false
    @State private var extrasOpen = false
    /// Filed, done, removed or swiped away: the sheet has had its say.
    @State private var finished = false
    /// The bork's tags from tap 1 on: the Categorizer's, the page's and the
    /// model's as they land, and the refine panel's toggles. Written as they
    /// change (`writeTags`).
    @State private var tagState: QuickFileTags?
    /// Where the refine panel's subtopic and tag lists come from.
    @State private var refineSource = QuickFileRefineSource.none
    /// The bork as it was before the first choice on this sheet, for Undo.
    @State private var beforeChoice: BeforeChoice?
    /// Done's drain after the first choice.
    @State private var drain = QuickFileDrain()
    /// A tag is being typed: the refine panel docks above the keyboard.
    @State private var typingTag = false
    /// The details step's size with no keyboard; sizes the dial.
    @State private var restingSize = CGSize.zero
    /// Room under the dial for the refine panel (about 235 pt) and the
    /// pinned Done bar (78 pt), plus a little air. Grows with the text.
    @ScaledMetric(relativeTo: .subheadline) private var belowDial: CGFloat = 323

    struct BeforeChoice {
        var categoryID: String?
        var subcategory: String?
        var source: String?
        var tags: [String]
        var tagsEdited: Bool?
    }

    private var style: QuickFileStyle { .app(accent) }

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
            VStack(spacing: 0) {
                sheetHeader
                    .padding(.horizontal, Tokens.gutter)
                Group {
                    switch step {
                    case .paste: pasteStep
                    case .details: detailsStep
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Tokens.paper)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Couldn't save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.large])
        .claySheet()
        // More… on the dial. It opens with nothing picked, so closing it
        // (Cancel, or swiping it away) files nothing; a pick files.
        .sheet(isPresented: $showingPicker, onDismiss: filePick) {
            TopicPickerSheet(categoryID: $pickedTopic, subcategory: $pickedSub)
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
            prepare()
            if let initialURL, urlText.isEmpty {
                urlText = initialURL.absoluteString
                saveNow()
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
        // Swiped away after tap 1: the same as "Done".
        .onDisappear(perform: finishIfNeeded)
    }

    // MARK: Header

    /// A's sheet header: the grabber band, then the title at 17/600 on the
    /// left. Before tap 1 the one way out is Cancel; once saved there is
    /// nothing to cancel, so "Done" keeps it (and the guess) and the one way
    /// back is a deliberate "Remove this save" in the ⋯ menu. Once something
    /// is chosen, Done is pinned under the panel instead.
    private var sheetHeader: some View {
        ClaySheetHeader(title: saved != nil ? "Saved to bookmarker" : "Add a link")
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 2) {
                    if saved != nil {
                        if createdHere {
                            Menu {
                                Button(role: .destructive, action: removeSave) {
                                    Label("Remove this save", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Tokens.ink)
                                    .frame(width: 36, height: 36)
                                    .background(Tokens.surface, in: Circle())
                                    .overlay(Circle().strokeBorder(Tokens.hairline, lineWidth: 1))
                                    .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("More")
                        }
                        if dial?.isChosen != true {
                            Button("Done", action: done)
                                .buttonStyle(.clayQuiet)
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.clayQuiet)
                    }
                }
                .frame(height: 36)
                .padding(.trailing, -6)
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
                    .submitLabel(.go)
                    .onSubmit(saveNow)
                    .padding(14)
                    .frame(minHeight: 48)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous)
                            .stroke(parsedURL != nil ? accent.base.opacity(0.6) : Tokens.hairline,
                                    lineWidth: parsedURL != nil ? 1.5 : 1)
                    )

                if urlText.isEmpty && clipboardHasContent {
                    HStack(spacing: 12) {
                        Text("Paste the link you copied")
                            .textRole(.cardTitle, color: Tokens.ink)
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
                    .padding(.vertical, 10)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .cardSurface(radius: Tokens.cardRadius)
                }

                // A typed link that has paused: what it is, and the button
                // that saves it. Typing never saves on its own.
                if typedReady, let url = parsedURL {
                    VStack(spacing: 12) {
                        linkRow(url, saved: false)
                        Button(Copy.saveVerb, action: saveTyped)
                            .buttonStyle(.clayPrimary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                    Text("Saving from another app? Use the share sheet.")
                        .textRole(.meta)
                }
                .foregroundStyle(Tokens.inkSecondary)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .animation(.easeOut(duration: 0.2), value: typedReady)
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
        // Tap 1 by paste or Return. A jump of eight or more characters at
        // once is a paste, never typing; a newline is the Return key, which
        // a vertical field types rather than submits. Both save at once — but
        // only a real link (`PastedLink`), never a fragment.
        .onChange(of: urlText) { old, new in
            guard step == .paste, saved == nil else { return }
            if new.contains(where: \.isNewline) {
                urlText = new.filter { !$0.isNewline }
                saveNow()
            } else if new.count - old.count >= 8 {
                saveNow()
            } else if parsedURL == nil, typedReady {
                typedReady = false
            }
        }
        // A typed link that pauses only reads its page and offers "Bork it".
        // Debounced so it fires once you've stopped, not on every character.
        .task(id: urlText) {
            guard parsedURL != nil, step == .paste else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, step == .paste else { return }
            await peek()
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

    /// The paste card is tap 1: the link goes in and is saved.
    private func applyPasted(_ link: PastedLink?) {
        guard let url = link?.url else { return }
        urlText = url.absoluteString
        saveNow()
    }

    // MARK: Step 2 — saved, where does it go?

    /// The saved card, the dial and its reason line, then the refine panel,
    /// and the extras folded away. The dial is sized from the sheet's resting
    /// height (`dialDiameter`) so that, at the default text size, everything
    /// down to the tag row sits above the pinned Done without scrolling, and
    /// a drag on the dial is a turn and never a scroll; at large text the
    /// dial bottoms out and the sheet scrolls.
    ///
    /// While a tag is being typed the field must not live in the ScrollView
    /// (keyboard avoidance there is not stable once text changes), so the
    /// scroll content drops to the saved row and a second refine panel docks
    /// in the bottom inset above Done, riding on the keyboard. When the field
    /// loses focus the dock goes and the resting layout returns.
    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let duplicate {
                    duplicateCard(duplicate)
                } else if let dial, let url = parsedURL {
                    linkRow(url, saved: true)
                    if !typingTag {
                        QuickFileHeader(model: dial, style: style)
                            .padding(.top, 6)
                        QuickFileDial(model: dial, style: style, diameter: dialDiameter,
                                      onDone: dial.isChosen ? { finishChosen() } : nil)
                            .padding(.top, -6)
                        if dial.isChosen, let tagState {
                            QuickFileRefinePanel(model: dial, tags: tagState, source: refineSource, style: style,
                                                 onAddTag: { setTypingTag(true) })
                                .padding(.top, -12)
                                .padding(.horizontal, -4)
                                .transition(.opacity)
                        } else {
                            QuickFileDialFooter(model: dial, style: style)
                        }
                        extras
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .animation(.easeOut(duration: 0.18), value: dial?.isChosen)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        // Pinned, so it is always in reach and rides above the keyboard;
        // while typing a tag, the panel docks on top of it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if duplicate == nil, let dial, dial.isChosen {
                VStack(spacing: 0) {
                    if typingTag, let tagState {
                        QuickFileRefinePanel(model: dial, tags: tagState, source: refineSource, style: style,
                                             onEditingTag: { if !$0 { setTypingTag(false) } },
                                             startsTyping: true)
                            .padding(.horizontal, Tokens.gutter - 4)
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                    QuickFileDoneButton(draining: drain.isDraining, style: style) { finishChosen() }
                        .padding(.horizontal, Tokens.gutter)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
                .background {
                    Tokens.paper
                        .overlay(alignment: .top) { Tokens.hairline.frame(height: 1) }
                        .ignoresSafeArea(edges: .bottom)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The resting size: the keyboard and the Done bar don't change it.
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { restingSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in restingSize = size }
            }
            .ignoresSafeArea(.keyboard)
        }
        .background(QuickFileTouchWatcher { drain.touched() })
        // Typing doesn't reach the window's watcher.
        .onChange(of: tagState?.draft) { _, _ in drain.touched() }
        // The dock only exists while a topic is chosen; never leave the
        // sheet on the bare saved row if the choice goes away mid-typing.
        .onChange(of: dial?.isChosen) { _, chosen in
            if chosen != true { typingTag = false }
        }
        .task(id: drain.startedAt) {
            guard drain.isDraining else { return }
            try? await Task.sleep(for: .seconds(QuickFileDrain.seconds))
            guard !Task.isCancelled, drain.isDue(at: .now) else { return }
            finishChosen()
        }
    }

    private func setTypingTag(_ on: Bool) {
        guard typingTag != on else { return }
        withAnimation(.easeOut(duration: 0.2)) { typingTag = on }
    }

    private var dialDiameter: CGFloat {
        Self.dialDiameter(restingSize, below: belowDial)
    }

    /// B's 360 pt wheel, 15 pt clear each side, smaller only when the sheet
    /// is short: `size` is the details step's resting size (no keyboard, Done
    /// bar included), and `below` is the room kept under the dial for the
    /// refine panel and the pinned Done. 118 pt above the dial is the link
    /// row and the reason line. Never under 232 pt; past that the sheet
    /// scrolls. The same before and after choosing and with the keyboard up.
    static func dialDiameter(_ size: CGSize, below: CGFloat = 323) -> CGFloat {
        guard size.height > 0 else { return max(260, min(size.width - 30, 360)) }
        return max(232, min(360, size.width - 30, size.height - 118 - below))
    }

    // MARK: Already saved

    /// The bork this link would land on, if it is already in the library.
    ///
    /// `allBookmarks` is already filtered to `deletedAt == nil`, so a bork you
    /// deleted and are saving again reads as new — which is the right answer;
    /// `DuplicateSave.match` checks the tombstone again anyway, because that
    /// rule is the one worth being sure of.
    private var duplicate: Bookmark? {
        guard !saveAnyway, !didSave, let url = parsedURL else { return nil }
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
        guard let url = parsedURL else { return }
        saveAnyway = true
        commit(url, over: bork)
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

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Already in your library")
                    .textRole(.sectionTitle, color: Tokens.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    TopicDot(palette: palette)
                    Text("\(filed) · \(when)")
                        .textRole(.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            savedRow(cover: CoverImage(url: bork.imageURL, topicID: bork.categoryID),
                     title: bork.title.isEmpty ? "Untitled" : bork.title,
                     meta: bork.displayAuthor.map { "\($0) · \(bork.platform.name)" }
                         ?? bork.url?.host ?? bork.platform.name)

            VStack(spacing: 10) {
                Button("Open it") { openingDuplicate = bork }
                    .buttonStyle(.clayPrimary)
                Button("Save again anyway") { saveAgain(over: bork) }
                    .buttonStyle(.claySecondary)
            }
        }
    }

    /// A's saved row: white, hairline, 62 pt, a 44 pt cover at radius 10,
    /// the title at 15/600 over "@author · Platform" in meta.
    private func savedRow<Cover: View>(cover: Cover, title: String, meta: String,
                                       note: String? = nil) -> some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .lineLimit(1)
                (Text(meta) + Text(note.map { " · \($0)" } ?? ""))
                    .textRole(.meta)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Tokens.cardRadius)
        .accessibilityElement(children: .combine)
    }

    /// The thing itself, compact: A's saved row — cover, title, who made it.
    /// Under the "Saved to bookmarker" header this is the confirmation: you
    /// see the post, not a form about it. Compact so the dial fits under it.
    private func linkRow(_ url: URL, saved isSaved: Bool) -> some View {
        let platform = Platform.detect(from: url)
        let creator = (Bookmark.isPlaceholderAuthor(author, url: url, platform: platform)
                       ? Platform.handle(in: url) : author) ?? url.host ?? platform.name
        return savedRow(cover: CoverImage(url: imageURL, topicID: saved?.categoryID),
                        title: title.isEmpty ? Categorizer.fallbackTitle(for: url) : title,
                        meta: creator == platform.name ? creator : "\(creator) · \(platform.name)",
                        note: isSaved && previewFetched && !titleWasFetched ? "couldn't read the page" : nil)
            .animation(.easeOut(duration: 0.2), value: title)
    }

    /// "Note, side quest, title", folded away under the dial. The whole point
    /// is that you don't type, so these are one tap away rather than in the
    /// way; whatever is set here is written to the bork as the sheet closes.
    /// Tags live in the refine panel.
    private var extras: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { extrasOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                    Text("Note, side quest, title")
                        .textRole(.chip)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(extrasOpen ? 180 : 0))
                }
                .foregroundStyle(Tokens.inkSecondary)
                .padding(.horizontal, 16)
                .frame(minHeight: Tokens.slimRowHeight)
                .cardSurface(radius: Tokens.cardRadius)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(extrasOpen ? "Open" : "Closed")

            if extrasOpen {
                journeyAttach
                titleField
                noteSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var journeyAttach: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Also on a side quest")
                .textRole(.label)
            Text("Optional. Topics file what this is. A side quest is why you kept it.")
                .textRole(.meta)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.chipGap) {
                    ForEach(journeys) { journey in
                        let on = selectedJourneyIDs.contains(journey.id)
                        FilterChip(journey.title, isOn: on) {
                            if on { selectedJourneyIDs.remove(journey.id) }
                            else { selectedJourneyIDs.insert(journey.id) }
                        }
                    }
                    TagChip(Copy.newSideQuest, isOn: false, isAdd: true, size: .filter) {
                        showingNewJourney = true
                    }
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
                        .textRole(.chip)
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
            Text("Title")
                .textRole(.label)
            TextField("What is this?", text: $title, axis: .vertical)
                .textRole(.body)
                .padding(14)
                .cardSurface(radius: Tokens.fieldRadius)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: $noteOpen.animation(.easeOut(duration: 0.18))) {
                Text("Add a note")
                    .textRole(.chip, color: Tokens.inkSecondary)
            }
            if noteOpen {
                TextField("Why does this matter?", text: $note, axis: .vertical)
                    .textRole(.body)
                    .lineLimit(3...6)
                    .padding(14)
                    .background(Tokens.noteTop, in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous)
                            .stroke(Tokens.noteBorder, lineWidth: 1)
                    )
                DatePicker("Note date", selection: $noteDate, displayedComponents: .date)
                    .textRole(.meta)
                    .tint(accent.base)
            }
        }
    }

    // MARK: Tap 1 — save

    /// Memory and topic order, ready before tap 1 so ranking then is free.
    private func prepare() {
        _ = MergedTaxonomy(topics: customTopics)
        memory = QuickFileBridge.memory(allBookmarks)
        order = QuickFileBridge.taxonomyOrder(customIDs: customTopics.map(\.id))
    }

    /// Tap 1 by paste, Return or a link handed in: saves at once — but only a
    /// real link (`PastedLink`, which wants a host with a real TLD), and once.
    private func saveNow() {
        guard step == .paste, saved == nil, let link = PastedLink.firstURL(in: urlText) else { return }
        if link.absoluteString != urlText { urlText = link.absoluteString }
        save(link)
    }

    /// Tap 1 by "Bork it", under a typed link whose page has been read.
    private func saveTyped() {
        guard step == .paste, saved == nil, let url = parsedURL else { return }
        save(url)
    }

    private func save(_ url: URL) {
        urlFocused = false
        // Already in the library: the card that says so, never a silent merge.
        guard duplicate == nil else {
            withAnimation(.easeOut(duration: 0.22)) { step = .details }
            return
        }
        commit(url)
    }

    /// Writes the bork with what is known so far and the best guess as
    /// `"automatic"`, then shows the dial at once and reads the page behind
    /// it. Re-saving over a bork that is already there keeps its filing.
    private func commit(_ url: URL, over existing: Bookmark? = nil) {
        // The + button raises the wall before the sheet ever opens; this is
        // the last line of defence, for a limit reached while the sheet was
        // up (a share draining behind it, another device syncing). Nothing
        // typed is lost: the link goes back to `RootView`, and after sign-up
        // the sheet reopens with it already in the field.
        if SaveLimit.shouldWall(liveCount: liveCount, signedIn: account?.isSignedIn ?? false) {
            onLimitReached(url)
            dismiss()
            return
        }

        if title.isEmpty { title = Categorizer.fallbackTitle(for: url) }
        if author == nil { author = Categorizer.fallbackAuthor(for: url) }
        let offline = Categorizer.suggest(url: url, title: title, description: pageDescription, author: author)
        pin = existing.flatMap { QuickFileBridge.pin(for: $0) }
        let ranking = rank(url)

        // What stays if nothing is confirmed: the dial's own guess (your
        // history can outrank the keywords), else the Categorizer's.
        var categoryID = offline.categoryID
        var subcategory = offline.subcategory
        if ranking.preselect != nil, let best = ranking.candidates.first {
            categoryID = best.categoryID
            subcategory = best.subcategory
        }
        if let existing, let kept = existing.categoryID {
            categoryID = kept
            subcategory = existing.subcategory
        }

        var draft = BookmarkDraft(
            url: url, title: title, author: author,
            platform: Platform.detect(from: url), kind: nil,
            categoryID: categoryID, subcategory: subcategory, tags: offline.tags,
            text: SavedContent.excerpt(pageDescription),
            durationSeconds: duration
        )
        draft.imageURLString = imageURL?.absoluteString
        draft.postedAt = postedAt
        draft.previewFetched = previewFetched
        draft.filingSource = "automatic"

        do {
            didSave = true
            let bork = try Store.save(draft, in: context)
            saved = bork
            createdHere = existing == nil
            let tagState = QuickFileTags(chosen: bork.tags, suggested: offline.tags, edited: bork.tagsEdited == true)
            tagState.onChange = { writeTags(to: bork) }
            self.tagState = tagState
            refineSource = makeRefineSource()
            dial = makeDial(ranking, url: url)
            #if DEBUG
            // `-quickFileChosen`: as if the top candidate had been tapped and
            // then the screen touched, so the sheet holds still for a capture.
            if ScreenshotDefaults.quickFileChosen, let dial, !dial.isChosen, let top = dial.candidates.first {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    dial.file(top)
                    drain.touched()
                }
            }
            #endif
            Haptics.tap()
            withAnimation(.easeOut(duration: 0.22)) { step = .details }
            Task { await enrich(url, bork: bork) }
        } catch {
            didSave = false
            let line = PlainError.message(error, doing: "save")
            self.error = line.isEmpty ? nil : line
        }
    }

    /// A save you had already filed opens chosen on that filing: the panel
    /// at once, nothing written, nothing draining.
    private func makeDial(_ ranking: FilingRanking, url: URL) -> QuickFileModel {
        var yours: FilingCandidate?
        if let pin, pin.reason == .yours, var lead = ranking.candidates.first(where: { $0.categoryID == pin.categoryID }) {
            lead.subcategory = pin.subcategory
            yours = lead
        }
        let model = QuickFileModel(ranking: ranking, input: input(for: url), mode: .refine, chosen: yours)
        drain = QuickFileDrain(alreadyChosen: yours != nil)
        model.onConfirm = { candidate in choose(candidate) }
        model.onMore = {
            pickedTopic = nil
            pickedSub = nil
            showingPicker = true
        }
        QuickFileAppArt.preload(model.candidates.map(\.categoryID))
        return model
    }

    private func input(for url: URL) -> FilingInput {
        FilingInput(url: url, title: title, text: nil, description: pageDescription,
                    author: author, ocrText: onScreenText)
    }

    private func rank(_ url: URL) -> FilingRanking {
        FilingSuggest.rank(input(for: url), memory: memory, ai: aiAnswer, pinned: pin, taxonomyOrder: order)
    }

    // MARK: Reading the page

    /// A typed link has paused: read its page and offer "Bork it". Never
    /// saves — a half-typed link must not become a bork.
    private func peek() async {
        guard let url = parsedURL else { return }
        resetPreview()
        typedReady = true
        let fetched = await LinkPreview.fetch(for: url, within: .seconds(3))
        guard !Task.isCancelled, step == .paste, saved == nil, parsedURL == url else { return }
        apply(fetched, for: url)
    }

    private func resetPreview() {
        title = ""
        author = nil
        imageURL = nil
        duration = nil
        postedAt = nil
        pageDescription = nil
        titleWasFetched = false
        previewFetched = false
        previewTimedOut = false
    }

    /// What the page said, into the sheet. A real page title, or the one
    /// made from the link — never a routing word dressed up as a description
    /// — and never over a title you are editing.
    private func apply(_ fetched: LinkPreview.Result?, for url: URL) {
        previewTimedOut = fetched == nil
        previewFetched = fetched != nil
        if let preview = fetched {
            if let image = preview.imageURL { imageURL = image }
            if let seconds = preview.durationSeconds { duration = seconds }
            if let posted = preview.publishedAt { postedAt = posted }
            if let description = preview.description { pageDescription = description }
            if let name = preview.author { author = name }
            if let fetchedTitle = preview.title, !editingTitle {
                title = fetchedTitle
                titleWasFetched = true
            }
        }
        if title.isEmpty { title = Categorizer.fallbackTitle(for: url) }
        if author == nil { author = Categorizer.fallbackAuthor(for: url) }
    }

    /// After tap 1, behind a sheet that is already useful: the page (oEmbed
    /// for YouTube, TikTok and X, Open Graph for the web, never more than
    /// three seconds), then on-screen text and the model side by side. Each
    /// re-ranks the dial. Store writes go through the bork itself, so they
    /// still land if the sheet has closed in the meantime.
    private func enrich(_ url: URL, bork: Bookmark) async {
        if !previewFetched {
            let fetched = await LinkPreview.fetch(for: url, within: .seconds(3))
            Self.writePreview(fetched, url: url, to: bork)
            apply(fetched, for: url)
            let offline = Categorizer.suggest(url: url, title: title, description: pageDescription, author: author)
            if tagState?.suggest(offline.tags) == true { writeTags(to: bork) }
            rerank(url)
        }
        readOnScreenText(bork)
        await askModel(url, bork: bork)
    }

    /// The page's findings, through `Store.save`'s merge rules: a fetched
    /// title replaces only the one made from the link, a real creator only a
    /// placeholder, and the filing is untouched (the draft carries no topic).
    private static func writePreview(_ fetched: LinkPreview.Result?, url: URL, to bork: Bookmark) {
        guard let fetched, bork.deletedAt == nil, let context = bork.modelContext else { return }
        var draft = BookmarkDraft(
            url: url, title: fetched.title ?? "", author: fetched.author,
            platform: bork.platform, kind: nil, categoryID: nil, subcategory: nil,
            text: SavedContent.excerpt(fetched.description),
            durationSeconds: fetched.durationSeconds
        )
        draft.imageURLString = fetched.imageURL?.absoluteString
        draft.postedAt = fetched.publishedAt
        draft.previewFetched = true
        _ = try? Store.save(draft, in: context)
    }

    /// The words on the cover, read quickly, as one more (weak) hint.
    private func readOnScreenText(_ bork: Bookmark) {
        guard let image = imageURL ?? bork.imageURL else { return }
        let id = bork.id
        Task { @MainActor in
            guard let text = await ThumbnailText.read(id, imageURL: image, accurate: false) else { return }
            onScreenText = text
            if let url = parsedURL { rerank(url) }
        }
    }

    /// The model, once for every save, however sure the ranking already is,
    /// and never waited on, also after a choice (its subtopic and tags feed
    /// the refine panel; it never moves the choice). Silent on every failure: signed out, offline, quota spent. Its
    /// answer is one more piece of evidence: it re-ranks the dial (sure
    /// keywords or your history with a creator can still win), and becomes
    /// the stored guess if the bork's filing is still the app's and nothing
    /// has touched it since asking — even if the sheet has closed, where it
    /// used to be lost.
    private func askModel(_ url: URL, bork: Bookmark) async {
        guard dial != nil, bork.deletedAt == nil,
              let account, let session = await account.currentSession() else { return }
        let request = SmartCategorizer.Context(url: url, title: title, author: author, description: pageDescription)
        let asked = input(for: url)
        let known = memory
        let topics = order
        let lead = pin
        let stamp = bork.updatedAt
        guard let answer = await SmartCategorizer.suggest(request, session: session) else { return }
        aiAnswer = answer
        rerank(url)
        let ranking = FilingSuggest.rank(asked, memory: known, ai: answer, pinned: lead, taxonomyOrder: topics)
        Self.keepGuess(ranking, on: bork, unchangedSince: stamp)
        // After the guess, whose stamp check a tag write would spoil.
        if tagState?.suggest(answer.tags) == true { writeTags(to: bork) }
    }

    /// A late answer reaches the dial through `offer` (an untouched dial
    /// re-deals, a touched one only gains a ✨ or an "Also likely" chip) and,
    /// while the dial is untouched, the stored guess follows what it shows.
    private func rerank(_ url: URL) {
        guard let dial else { return }
        let latest = input(for: url)
        let ranking = FilingSuggest.rank(latest, memory: memory, ai: aiAnswer, pinned: pin, taxonomyOrder: order)
        QuickFileAppArt.preload(ranking.candidates.map(\.categoryID))
        dial.offer(ranking, input: latest)
        if !dial.touched, !finished, let bork = saved {
            Self.keepGuess(ranking, on: bork)
        }
    }

    /// The ranking's guess becomes the bork's stored filing — only while that
    /// filing is still the app's to change, and, given a `stamp`, only if
    /// nothing has touched the bork since.
    private static func keepGuess(_ ranking: FilingRanking, on bork: Bookmark, unchangedSince stamp: Date? = nil) {
        guard bork.deletedAt == nil, EnrichmentPolicy.mayFile(source: bork.filingSource),
              ranking.preselect != nil, let best = ranking.candidates.first else { return }
        if let stamp, bork.updatedAt != stamp { return }
        guard best.categoryID != bork.categoryID || best.subcategory != bork.subcategory else { return }
        bork.categoryID = best.categoryID
        bork.subcategory = best.subcategory
        bork.touch()
        try? bork.modelContext?.save()
    }

    /// The tags as `tagState` has them, by `Store.save`'s rules: once you
    /// have touched them they replace the bork's, before that they only join.
    private func writeTags(to bork: Bookmark) {
        guard let tagState, bork.deletedAt == nil else { return }
        var changed = false
        if tagState.edited {
            if bork.tags != tagState.chosen || bork.tagsEdited != true {
                bork.tags = tagState.chosen
                bork.tagsEdited = true
                changed = true
            }
        } else if bork.tagsEdited != true {
            let added = tagState.chosen.filter { !bork.tags.contains($0) }
            if !added.isEmpty {
                bork.tags = Array(Set(bork.tags + added)).sorted()
                changed = true
            }
        }
        guard changed else { return }
        bork.touch()
        try? bork.modelContext?.save()
    }

    /// The refine panel's lists, from the library as it is at tap 1: every
    /// subtopic (built-in and yours), your most-used ones, and the tags you
    /// used lately on a filing (`TagRecency`, as the old tag field had them).
    private func makeRefineSource() -> QuickFileRefineSource {
        let merged = MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
        let uses: [QuickFileRefine.Use] = allBookmarks.compactMap { bork in
            guard bork.filingSource == "user", let id = bork.categoryID else { return nil }
            return QuickFileRefine.Use(categoryID: id, subcategory: bork.subcategory, at: bork.updatedAt)
        }
        let used = QuickFileRefine.subUse(uses)
        let items = allBookmarks.map {
            TagRecency.Item(categoryID: $0.categoryID, subcategory: $0.subcategory, tags: $0.tags, at: $0.updatedAt)
        }
        return QuickFileRefineSource(
            subs: { id in merged.topic(id: id).map { merged.subs(for: $0) } ?? [] },
            used: { used[$0] ?? [] },
            recentTags: { TagRecency.suggestions(in: items, categoryID: $0, subcategory: $1, limit: 12) }
        )
    }

    // MARK: Tap 2 — choose, refine, done

    /// Tap 2, and every change after it: a key on the dial, its centre, a
    /// subtopic chip, the "Also likely" chip or a pick from More…. Written as
    /// yours at once, and the sheet stays for the refine panel. The bork as
    /// it was before the first choice is kept for Undo; the first choice
    /// starts Done's drain.
    private func choose(_ candidate: FilingCandidate) {
        guard let bork = saved, !finished else { return }
        if beforeChoice == nil {
            beforeChoice = BeforeChoice(categoryID: bork.categoryID, subcategory: bork.subcategory,
                                        source: bork.filingSource, tags: bork.tags, tagsEdited: bork.tagsEdited)
        }
        bork.categoryID = candidate.categoryID
        bork.subcategory = candidate.subcategory
        bork.filingSource = "user"
        bork.touch()
        try? context.save()
        QuickFileBridge.scheduleSnapshot(context: context)
        drain.chose(at: .now, assistive: UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning)
    }

    /// Done, its drain, or a swipe after a choice: the extras are written and
    /// a toast offers Undo. Undo takes back everything the sheet did: a bork
    /// it made leaves the library ("Save removed"), one that was already
    /// there gets its filing and tags back.
    private func finishChosen(dismissing: Bool = true) {
        guard let bork = saved, !finished, let before = beforeChoice else {
            if dismissing, !finished { done() }
            return
        }
        tagState?.commitDraft()
        finished = true
        if writeExtras(to: bork) { bork.touch() }
        try? context.save()

        let store = context
        let created = createdHere
        let report = onSaved
        let undo = {
            guard bork.deletedAt == nil else { return }
            bork.categoryID = before.categoryID
            bork.subcategory = before.subcategory
            bork.filingSource = before.source
            bork.tags = before.tags
            bork.tagsEdited = before.tagsEdited
            // A tombstone, like any delete, under the guess it was saved
            // with, so pasting the link again starts over.
            if created { bork.deletedAt = .now }
            bork.touch()
            try? store.save()
            QuickFileBridge.scheduleSnapshot(context: store)
            if created { report("Save removed", nil) }
        }
        if dismissing { dismiss() }
        let line = created ? nil : dial?.filed.map(QuickFileCopy.filed)
        onSaved(line ?? Self.savedLine(for: bork), undo)
        ReviewPrompter.reached(.borkSaved, requestReview)
    }

    /// "Done": the bork stays as saved, filed under our guess, plus whatever
    /// the extras say.
    private func done() {
        guard let bork = saved, !finished else { return dismiss() }
        if beforeChoice != nil { return finishChosen() }
        tagState?.commitDraft()
        finished = true
        if writeExtras(to: bork) { bork.touch() }
        try? context.save()
        dismiss()
        onSaved(Self.savedLine(for: bork), nil)
        ReviewPrompter.reached(.borkSaved, requestReview)
    }

    /// Swiped away after tap 1: the same as "Done".
    private func finishIfNeeded() {
        guard let bork = saved, !finished else { return }
        if beforeChoice != nil { return finishChosen(dismissing: false) }
        tagState?.commitDraft()
        finished = true
        if writeExtras(to: bork) { bork.touch() }
        try? context.save()
        onSaved(Self.savedLine(for: bork), nil)
    }

    /// The one way back from tap 1, and it can itself be undone.
    private func removeSave() {
        guard let bork = saved, createdHere, !finished else { return }
        finished = true
        bork.deletedAt = .now
        bork.touch()
        try? context.save()
        let store = context
        dismiss()
        onSaved("Save removed", {
            bork.deletedAt = nil
            bork.touch()
            try? store.save()
        })
    }

    /// A pick from More… chooses, or re-chooses.
    private func filePick() {
        guard let topic = pickedTopic, let dial else { return }
        dial.file(dial.candidate(topicID: topic, subcategory: pickedSub))
    }

    /// The extras, written through to the bork as the sheet closes. Says
    /// whether anything changed, so an untouched bork isn't restamped. Tags
    /// are written as they change (`writeTags`).
    @discardableResult
    private func writeExtras(to bork: Bookmark) -> Bool {
        var changed = false
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if editingTitle, !typed.isEmpty, typed != bork.title {
            bork.title = typed
            bork.titleEdited = true
            changed = true
        }
        if noteOpen, !note.isEmpty, bork.noteText != note || bork.noteDate != noteDate {
            bork.noteText = note
            bork.noteDate = noteDate
            changed = true
        }
        for journey in journeys where selectedJourneyIDs.contains(journey.id) && !journey.contains(bork.id) {
            journey.attach(bork.id)
        }
        return changed
    }

    /// "Saved to Fitness › Running" — where it is, guess or not.
    private static func savedLine(for bork: Bookmark) -> String {
        guard let topic = Taxonomy.category(id: bork.categoryID) else { return "Saved to your library" }
        return "Saved to " + (bork.subcategory.map { "\(topic.name) › \($0)" } ?? topic.name)
    }
}
