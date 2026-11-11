import SwiftUI
import SwiftData

/// Home, as the approved "Quiet clay" artboard draws it (design/project/
/// Main.dc.html): "Your library" with the counts and the avatar, the search
/// entry, at most one slim action row (`LibraryPrompt`), the source chips,
/// two rows of saves, the side-quest rail, then the rest of the saves.
///
/// The insight card ("What are you finding interesting?") left in 1.4: it
/// lives on Revisit and You, so the Library is saves first.
struct LibraryView: View {
    @Environment(\.scenePhase) private var enrichmentScenePhase
    let onAdd: () -> Void
    var onSearch: () -> Void = {}
    var onSeeJourneys: () -> Void = {}
    /// Raise the save-limit wall. Owned by `RootView` because the wall is also
    /// the answer to the + button and to a share that landed over the limit,
    /// and one sheet with one owner is the only way it never double-presents.
    var onShowWall: (SaveLimitReason) -> Void = { _ in }
    /// The avatar opens You. Until the root passes this the avatar is a
    /// picture, as it was in 1.3.
    var onOpenAccount: (() -> Void)? = nil
    var account: Account? = nil
    /// False while the root has a sheet up (the Add sheet, the wall and its
    /// sign-in, Sort your borks, a shared link) or the first-run tour is
    /// showing. A milestone sheet waits for a clear screen rather than
    /// stacking on top of one.
    var canInterrupt: Bool = true

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @AppStorage("feedDensity") private var density = "cards"

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var bookmarks: [Bookmark]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    @State private var sourceFilter: Platform?
    @State private var detail: Bookmark?
    @State private var openJourney: Mission?
    @State private var creatingJourney = false
    @State private var showingBackupBanner = false
    @State private var nudge: SignInMilestone?
    /// The Pro sheet, at 100, 250 and 500 borks. See `ProNudge`.
    @State private var showingPro = false
    @State private var showingAuth = false
    @State private var authMode: AuthSheet.Mode = .signUp
    /// Select mode: pick borks from any source and share them as one link.
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var collecting = false
    @StateObject private var previews = PreviewFetcher()
    /// "Sort your borks", from the action row.
    @State private var triageDeck: TriageSheet.Deck?
    /// The unsorted count when the sort row was last waved away. It stays
    /// away until the count goes above this.
    @AppStorage("triage.snoozedAt") private var sortSnoozedAt = 0
    /// The dial hint has done its job: its ×, "Try it", or a first filing on
    /// the dial put it away for good. See `retireDialHintIfFiled`.
    @AppStorage("dialHint.done") private var dialHintDone = false
    /// When this build first opened the Library. Only a filing since then
    /// counts as having found the dial.
    @AppStorage("dialHint.since") private var dialHintSince = 0.0

    /// Saves before the side-quest rail: two rows of two.
    private static let leadCount = 4

    /// Everything that counts. A waiting bork is saved and on screen, but it
    /// is not part of the library yet — not in the stats line, not in
    /// Highlights, not in a side quest's suggestions. See `SaveLimit`.
    private var live: [Bookmark] {
        bookmarks.filter { !$0.isWaiting }
    }

    /// The feed, which shows waiting borks — greyed, pilled, and deletable.
    /// Hiding them would turn "your share was saved" into a disappearing act.
    private var visible: [Bookmark] {
        guard let sourceFilter else { return bookmarks }
        return bookmarks.filter { $0.platform == sourceFilter }
    }

    private var presentPlatforms: [Platform] {
        let used = Set(bookmarks.map(\.platform))
        return Platform.ordered.filter { used.contains($0) }
    }

    private static func statsLine(_ live: [Bookmark]) -> String {
        var platforms = Set<String>(), categories = Set<String>()
        for bookmark in live {
            platforms.insert(bookmark.platformRaw)
            if let id = bookmark.categoryID { categories.insert(id) }
        }
        let borks = live.count
        let apps = platforms.count
        let topics = categories.count
        return "\(borks) \(Copy.borks(borks)) · \(apps) app\(apps == 1 ? "" : "s") · \(topics) topic\(topics == 1 ? "" : "s")"
    }

    var body: some View {
        // Each of these is a pass over the whole library. Taken once per
        // render and handed down, rather than re-derived at every read.
        let live = self.live
        let waitingCount = bookmarks.count - live.count
        let visible = self.visible
        let platforms = presentPlatforms
        let unsorted = TriageSheet.unfiled(live).count
        let prompt = currentPrompt(live: live, waiting: waitingCount, unsorted: unsorted)
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(stats: Self.statsLine(live))
                            .padding(.horizontal, Tokens.gutter)
                        searchEntry
                            .padding(.horizontal, Tokens.gutter)
                            .padding(.top, 16)
                        if let prompt {
                            promptRow(prompt)
                                .padding(.horizontal, Tokens.gutter)
                                .padding(.top, 10)
                                .transition(.opacity)
                        }
                        if bookmarks.isEmpty {
                            EmptyFeedState(filtered: false, onAdd: onAdd)
                                .padding(.horizontal, Tokens.gutter)
                                .padding(.top, Tokens.sectionGap)
                        } else {
                            filterRow(platforms)
                                .padding(.top, 6)
                            feed(visible, live: live)
                                .padding(.top, 6)
                        }
                    }
                    // Bound the scroll content to the viewport, not a child's
                    // ideal width (loaded images and selection labels can be
                    // much wider).
                    .frame(width: max(0, viewport.size.width), alignment: .leading)
                    // The tab bar is the root's safe-area inset, so the scroll
                    // already ends above it; this is only breathing room.
                    .padding(.bottom, Tokens.sectionGap)
                }
                #if DEBUG
                .onAppear { applyDebugAnchor(proxy) }
                #endif
            }
        }
        .background(Tokens.paper)
        .animation(Motion.gentle, value: prompt)
        .safeAreaInset(edge: .bottom) {
            if selecting {
                SelectionBar(count: selected.count, onShare: { collecting = true }, onCancel: endSelecting)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Sorting brings the count down; the row comes back when it rises
        // past where it was waved away, not merely back to it.
        .onChange(of: unsorted) { _, count in
            if count < sortSnoozedAt { sortSnoozedAt = count }
        }
        .sheet(item: $detail) { bookmark in
            DetailSheet(bookmark: bookmark)
                .environment(\.accent, accent)
        }
        .sheet(item: $triageDeck) { deck in
            TriageSheet(deck: deck, account: account)
                .environment(\.accent, accent)
        }
        .sheet(isPresented: $collecting) {
            CollectSheet(bookmarks: selectedBookmarks, account: account, onCreated: endSelecting)
                .environment(\.accent, accent)
        }
        .sheet(item: $openJourney) { journey in
            MissionDetailSheet(mission: journey, account: account).environment(\.accent, accent)
        }
        .sheet(isPresented: $creatingJourney) {
            NewMissionSheet().environment(\.accent, accent)
        }
        .sheet(item: $nudge) { milestone in
            SignInNudgeSheet(
                milestone: milestone.id,
                count: live.count,
                signedIn: account?.isSignedIn ?? false,
                // Signed in, the primary button is "Back up now" and the only
                // thing missing is a sync that has never run — so run one.
                onSignUp: {
                    nudge = nil
                    if account?.isSignedIn == true {
                        Task { await account?.sync(context: context) }
                    } else {
                        present(.signUp, afterSheet: true)
                    }
                },
                onSignIn: { nudge = nil; present(.signIn, afterSheet: true) },
                onNotNow: {
                    SignInNudge.recordNotNow()
                    nudge = nil
                    showingBackupBanner = false
                }
            )
            .environment(\.accent, accent)
        }
        .sheet(isPresented: $showingPro) {
            ProSheet(origin: .milestone)
                .environment(\.accent, accent)
        }
        .sheet(isPresented: $showingAuth) {
            if let account {
                AuthSheet(account: account, mode: authMode)
                    .environment(\.accent, accent)
            }
        }
        .onAppear {
            // Before `markRead`: a share filed on the dial is still unread.
            // Unanimated, or the row would fade out as the Library opens.
            retireDialHintIfFiled(animated: false)
            markRead()
            readNudgePolicy()
            #if DEBUG
            applyDebugProSheet()
            applyDebugDetail()
            #endif
        }
        // Counting from the store, not from a counter the app keeps: a bork
        // saved through the Share Extension arrives when the inbox is drained
        // and must count exactly as much as one saved in the Add sheet.
        .onChange(of: bookmarks.count) { _, _ in
            readNudgePolicy()
            retireDialHintIfFiled()
        }
        .onChange(of: account?.isSignedIn ?? false) { _, _ in readNudgePolicy() }
        // A milestone that had to wait for the Add sheet to close comes back
        // the moment the screen is clear again. The Add sheet files on its
        // dial without changing the count, so that is checked here too.
        .onChange(of: canInterrupt) { _, clear in
            if clear {
                readNudgePolicy()
                retireDialHintIfFiled()
            }
        }
        // Fill in real titles and thumbnails for anything still missing them.
        // Keyed on count so a fresh batch of brks triggers another pass.
        .task(id: bookmarks.count) {
            while !Task.isCancelled {
                if enrichmentScenePhase == .active {
                    await previews.fetchMissing(for: bookmarks, in: context, account: account)
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    // MARK: Header

    /// Main.dc: "Your library" 30/34 with the counts under it, and the
    /// avatar at the right — a 36 pt sand circle in a 44 pt target.
    private func header(stats: String) -> some View {
        ScreenHeader("Your library", subtitle: stats) {
            avatar.padding(.trailing, -4)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        // Your own initial, or nobody's. This was a hardcoded "J" — the
        // founder's — on every phone, signed in or not.
        let letter = Initials.letter(displayName: nil, email: account?.email)
        let circle = Circle()
            .fill(Tokens.sand)
            .frame(width: 36, height: 36)
            .overlay {
                if let letter {
                    Text(letter)
                        .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                        .foregroundStyle(Tokens.sandInk)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.sandInk)
                }
            }
            .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
        if let onOpenAccount {
            Button(action: onOpenAccount) { circle.contentShape(Circle()) }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Your account")
        } else {
            circle.accessibilityHidden(true)
        }
    }

    private var searchEntry: some View {
        Button(action: onSearch) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Tokens.inkSecondary)
                Text(Copy.searchPlaceholder)
                    .textRole(.body, color: Tokens.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .searchFieldSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search your library")
        .accessibilityHint("Opens search at the top of Browse")
    }

    // MARK: The one action row

    /// Which slim row, if any — `LibraryPrompt` decides (waiting > backup >
    /// sort > dial hint). `-dialHint` forces the hint for its screenshot.
    private func currentPrompt(live: [Bookmark], waiting: Int, unsorted: Int) -> LibraryPrompt? {
        if DialHintScreenshot.forced { return .dialHint }
        return LibraryPrompt.pick(
            waiting: waiting,
            backupDue: showingBackupBanner,
            liveCount: live.count,
            unsorted: unsorted,
            sortSnoozedAt: sortSnoozedAt,
            // Off the empty Library, which already says how to save.
            dialHintDue: !dialHintDone && !bookmarks.isEmpty
        )
    }

    private func promptRow(_ prompt: LibraryPrompt) -> some View {
        SlimActionRow(
            art: Self.art(for: prompt),
            title: prompt.title,
            subtitle: prompt.subtitle,
            action: prompt.action,
            perform: { perform(prompt) },
            onDismiss: prompt.isDismissable ? { dismiss(prompt) } : nil
        )
    }

    private static func art(for prompt: LibraryPrompt) -> ClayArtSource {
        switch prompt {
        case .waiting: .asset("brandMark")
        case .backup: .asset("welcomeHero")
        case .sort: .quest(.compass)
        case .dialHint: .quest(.scroll)
        }
    }

    private func perform(_ prompt: LibraryPrompt) {
        switch prompt {
        case .waiting: onShowWall(.waiting)
        case .backup: present(.signUp)
        case .sort: triageDeck = .unfiled
        case .dialHint:
            retireDialHint()
            onAdd()
        }
    }

    private func dismiss(_ prompt: LibraryPrompt) {
        switch prompt {
        case .waiting:
            break
        case .backup:
            SignInNudge.dismissBanner()
            withAnimation(Motion.gentle) { showingBackupBanner = false }
        case .sort(let count):
            withAnimation(Motion.gentle) { sortSnoozedAt = count }
        case .dialHint:
            retireDialHint()
        }
    }

    private func acceptSeed(_ seed: Mission.Seed) {
        let journey = Mission(title: seed.title, categoryID: seed.categoryID)
        journey.bookmarkIDs = seed.bookmarkIDs
        context.insert(journey)
        try? context.save()
        Haptics.success()
        openJourney = journey
    }

    // MARK: Source chips

    /// Main.dc: 34 pt filter chips, 6 apart, in 44 pt targets. The view
    /// options (cards or list, and picking borks to share) sit in one menu at
    /// the right, outside the scrolling chips, so no chip is ever cut off by
    /// it.
    private func filterRow(_ platforms: [Platform]) -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    sourceChip("All", on: sourceFilter == nil) { sourceFilter = nil }
                    ForEach(platforms, id: \.self) { platform in
                        sourceChip(platform.name, on: sourceFilter == platform) {
                            sourceFilter = sourceFilter == platform ? nil : platform
                        }
                    }
                }
                .padding(.leading, Tokens.gutter)
                .padding(.trailing, 4)
            }
            // A hairline where the chips run under the menu, so the cut
            // reads as "more this way" rather than as a chip cut in half.
            .overlay(alignment: .trailing) {
                Tokens.hairline.frame(width: 1, height: 24)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            viewMenu
                .padding(.trailing, Tokens.gutter - 5)
        }
        #if DEBUG
        .onAppear(perform: applyDebugSelection)
        #endif
    }

    private func sourceChip(_ title: String, on: Bool, tap: @escaping () -> Void) -> some View {
        FilterChip(title, isOn: on) {
            Haptics.tap()
            withAnimation(Motion.snap) { tap() }
        }
    }

    /// Cards or list, and select mode. Filled while select mode is on,
    /// because select mode changes what a tap on a card does.
    private var viewMenu: some View {
        Menu {
            Picker("Show borks as", selection: $density) {
                Label("Cards", systemImage: "square.grid.2x2").tag("cards")
                Label("List", systemImage: "list.bullet").tag("compact")
            }
            Divider()
            Button {
                if selecting {
                    endSelecting()
                } else {
                    withAnimation(Motion.gentle) { selecting = true }
                }
            } label: {
                Label(selecting ? "Stop picking" : "Pick borks to share",
                      systemImage: selecting ? "xmark.circle" : "checkmark.circle")
            }
        } label: {
            Image(systemName: selecting ? "checkmark" : "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selecting ? .white : Tokens.ink)
                .frame(width: 34, height: 34)
                .background(selecting ? Tokens.ink : Tokens.surface, in: Circle())
                .overlay(Circle().strokeBorder(selecting ? Tokens.ink : Tokens.hairline, lineWidth: 1))
                .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(selecting ? "View options, picking borks" : "View options")
    }

    // MARK: Feed

    /// Two rows of saves, the side-quest rail, the rest. In list density the
    /// rail comes after the fourth row, the same place in the reading order.
    @ViewBuilder
    private func feed(_ visible: [Bookmark], live: [Bookmark]) -> some View {
        if visible.isEmpty {
            EmptyFeedState(filtered: true, onAdd: onAdd)
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, Tokens.sectionGap)
        } else {
            let lead = Array(visible.prefix(Self.leadCount))
            let rest = Array(visible.dropFirst(Self.leadCount))
            VStack(alignment: .leading, spacing: 0) {
                saves(lead)
                rail(live)
                    .id("rail")
                    .padding(.top, Tokens.sectionGap)
                    .padding(.bottom, rest.isEmpty ? 0 : Tokens.sectionGap)
                if !rest.isEmpty {
                    saves(rest).id("rest")
                }
            }
        }
    }

    private func rail(_ live: [Bookmark]) -> some View {
        JourneyRail(
            journeys: journeys,
            bookmarks: live,
            onOpen: { openJourney = $0 },
            onSeeAll: onSeeJourneys,
            onStart: { creatingJourney = true },
            onAcceptSeed: acceptSeed,
            account: account
        )
    }

    @ViewBuilder
    private func saves(_ items: [Bookmark]) -> some View {
        if density == "compact" {
            LazyVStack(spacing: 8) {
                ForEach(items) { bookmark in
                    Button { open(bookmark) } label: {
                        BookmarkRow(bookmark: bookmark)
                            .selectable(selecting, selected: selected.contains(bookmark.id))
                    }
                    .buttonStyle(PressableStyle())
                    .borkActions(bookmark, enabled: !selecting)
                    .accessibilityIdentifier("bork-card")
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Tokens.gutter)
        } else {
            // Every card is the same height at a given width, so a plain lazy
            // grid lines up — and builds only the rows on screen.
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Tokens.gridGap, alignment: .top),
                          GridItem(.flexible(), spacing: Tokens.gridGap, alignment: .top)],
                spacing: Tokens.gridGap
            ) {
                ForEach(items) { bookmark in
                    Button { open(bookmark) } label: {
                        BookmarkCard(bookmark: bookmark)
                            .selectable(selecting, selected: selected.contains(bookmark.id))
                    }
                    .buttonStyle(PressableStyle())
                    .borkActions(bookmark, enabled: !selecting)
                    .accessibilityIdentifier("bork-card")
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, Tokens.gutter)
        }
    }

    /// Asks `SignInNudge` what the signed-out cues should be doing, from the
    /// library as it stands, then `ProNudge` whether the Pro sheet is due.
    /// One call site for every surface, which is what keeps the two sheets
    /// from ever stacking.
    private func readNudgePolicy() {
        guard let account else {
            showingBackupBanner = false
            return
        }
        let borks = live.count
        let signedIn = account.isSignedIn

        // Deletes make room, and signing in makes all of it. Cheap and a no-op
        // when nothing is waiting, so it runs on every reading rather than on
        // a guess about which change could have freed a slot.
        Store.admitWaiting(in: context, signedIn: signedIn)

        showingBackupBanner = SignInNudge.showsBanner(signedIn: signedIn, borks: borks)

        guard let milestone = SignInNudge.dueMilestone(
            borks: borks, signedIn: signedIn, hasSynced: account.lastSynced != nil
        ) else {
            SignInNudge.recordSeen(borks)
            // Pro gets a turn only with no sign-in sheet due: that one is
            // about not losing the library, so it goes first, and a Pro
            // milestone stays due behind it.
            readProMilestone(borks: borks, signedIn: signedIn)
            return
        }
        // Nothing goes on top of another sheet. Leaving the watermark alone
        // keeps this milestone due for the next time the Library is clear.
        guard screenIsClear else { return }

        SignInNudge.recordSheetShown(milestone)
        SignInNudge.recordSeen(borks)

        // The 5th bork is usually saved in the Add sheet, which is dismissing
        // as this runs; a sheet presented into that transition is dropped.
        // Same reason ReviewPrompter waits.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            nudge = SignInMilestone(id: milestone)
        }
    }

    /// The Pro sheet at 100, 250 and 500 borks, on the sign-in sheet's rules:
    /// a crossing this install saw, never over another sheet, and a
    /// milestone it could not show stays due. See `ProNudge`.
    private func readProMilestone(borks: Int, signedIn: Bool) {
        guard let milestone = ProNudge.dueMilestone(borks: borks, signedIn: signedIn) else {
            ProNudge.recordSeen(borks)
            return
        }
        guard screenIsClear else { return }

        ProNudge.recordSheetShown(milestone)
        ProNudge.recordSeen(borks)

        // The 100th bork is usually saved in the Add sheet, which is still
        // dismissing as this runs — same wait as the sign-in sheet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            showingPro = true
        }
    }

    /// Whether a milestone sheet may go up now: nothing from the root, and
    /// none of the Library's own sheets either.
    private var screenIsClear: Bool {
        canInterrupt && nudge == nil && !showingPro && !showingAuth && detail == nil
            && openJourney == nil && !creatingJourney
            && triageDeck == nil && !collecting
    }

    /// The hint is for someone who has not met the dial, so it goes for good
    /// once they have filed on it: a `"user"` filing saved since this build
    /// first opened the Library (the Add sheet's, or the web's after a sync),
    /// or one still unread (the share sheet's, drained since the Library was
    /// last open). Older `"user"` filings may be the old picker's, so they
    /// don't count.
    private func retireDialHintIfFiled(animated: Bool = true) {
        guard !dialHintDone else { return }
        if dialHintSince == 0 { dialHintSince = Date.now.timeIntervalSinceReferenceDate }
        let since = Date(timeIntervalSinceReferenceDate: dialHintSince)
        guard bookmarks.contains(where: {
            $0.filingSource == "user" && ($0.isUnread || $0.savedAt >= since)
        }) else { return }
        if animated { retireDialHint() } else { dialHintDone = true }
    }

    private func retireDialHint() {
        withAnimation(Motion.gentle) { dialHintDone = true }
    }

    /// The sign-up flow is the You tab's `AuthSheet`, reused as-is. When the
    /// milestone sheet is what asked for it, let that finish dismissing first
    /// or SwiftUI drops the second presentation.
    private func present(_ mode: AuthSheet.Mode, afterSheet: Bool = false) {
        authMode = mode
        guard afterSheet else {
            showingAuth = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            showingAuth = true
        }
    }

    // MARK: Select mode

    private var selectedBookmarks: [Bookmark] {
        bookmarks.filter { selected.contains($0.id) }
    }

    /// A tap on a card opens it — or, in select mode, picks it.
    private func open(_ bookmark: Bookmark) {
        guard selecting else {
            detail = bookmark
            return
        }
        Haptics.tap()
        if selected.contains(bookmark.id) {
            selected.remove(bookmark.id)
        } else {
            selected.insert(bookmark.id)
        }
    }

    private func endSelecting() {
        withAnimation(Motion.gentle) {
            selecting = false
            selected = []
        }
    }

    #if DEBUG
    /// `-select N` and `-collect` — see `CollectionsDebug`.
    private func applyDebugSelection() {
        guard let n = CollectionsDebug.preselect, !selecting, selected.isEmpty else { return }
        selected = Set(visible.prefix(n).map(\.id))
        selecting = true
        if CollectionsDebug.openCollect { collecting = true }
    }

    /// `-proSheet` — see `ScreenshotDefaults.openProSheet`.
    private func applyDebugProSheet() {
        guard ScreenshotDefaults.openProSheet else { return }
        Task { @MainActor in
            // After the seed and the first frame, or the sheet is dropped.
            try? await Task.sleep(for: .milliseconds(700))
            showingPro = true
        }
    }

    /// `-detail 0` / `-detail <stableID>` — see `ScreenshotDefaults.openDetail`.
    private func applyDebugDetail() {
        guard let wanted = ScreenshotDefaults.openDetail, detail == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if let index = Int(wanted), bookmarks.indices.contains(index) {
                detail = bookmarks[index]
            } else {
                detail = bookmarks.first { $0.id == wanted }
            }
        }
    }

    /// `-libraryAt rail|rest` — see `ScreenshotDefaults.libraryAnchor`.
    private func applyDebugAnchor(_ proxy: ScrollViewProxy) {
        guard let anchor = ScreenshotDefaults.libraryAnchor else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            proxy.scrollTo(anchor, anchor: .top)
        }
    }
    #endif

    private func markRead() {
        let unread = bookmarks.filter(\.isUnread)
        guard !unread.isEmpty else { return }
        for bookmark in unread { bookmark.isUnread = false }
        try? context.save()
    }
}

/// An empty Library, or a source filter with nothing in it. The clay scene a
/// first save would sit beside, then how to make one.
private struct EmptyFeedState: View {
    let filtered: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !filtered {
                ClayArtImage(source: .asset("welcomeHero"))
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
                    .padding(.bottom, 20)
            }

            Text(filtered ? "Nothing from this app yet" : "Everything you save, in one place")
                .textRole(.sectionTitle, color: Tokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(filtered
                 ? "Try another source."
                 : "In Instagram, X, TikTok or YouTube — tap Share, then bookmarker.")
                .textRole(.body, color: Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 12)

            if !filtered {
                Button("Paste a link", action: onAdd)
                    .buttonStyle(.clayPrimary)
                    .padding(.top, 22)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, filtered ? 12 : 24)
    }
}

/// Screenshot hook. `-dialHint` shows the dial hint on its own, whatever its
/// state, over a seeded library whose unfiled saves would otherwise keep it
/// behind the sort row. Always false outside DEBUG.
private enum DialHintScreenshot {
    static var forced: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-dialHint")
        #else
        return false
        #endif
    }
}
