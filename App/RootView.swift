import SwiftUI
import SwiftData
import OSLog

enum AppTab: String, CaseIterable, Hashable {
    case library, browse, revisit, you

    var title: String {
        switch self {
        case .library: "Library"
        case .browse: "Browse"
        case .revisit: "Revisit"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .library: "square.stack.fill"
        case .browse: "square.grid.2x2.fill"
        case .revisit: "clock.arrow.circlepath"
        case .you: "person.fill"
        }
    }

    /// Reads a persisted or deep-linked tab name, including ones this build no
    /// longer has.
    ///
    /// 1.1 folded Search into Browse. A phone updating from 1.0.x can be
    /// carrying `startingTab = "search"`, and a link or a screenshot script can
    /// still ask for it. Falling through to the default would silently drop
    /// someone onto the Library when they asked to search — Browse is where
    /// searching now happens, so that is where "search" goes.
    static func resolve(_ raw: String) -> AppTab? {
        if raw == "search" { return .browse }
        return AppTab(rawValue: raw)
    }
}

/// What the collections sheet on the root is showing: a link somebody sent,
/// or (for screenshots — the You tab has its own entry) your own list.
enum CollectionRoute: Identifiable, Hashable {
    case incoming(slug: String)
    case list

    var id: String {
        switch self {
        case .incoming(let slug): "incoming:\(slug)"
        case .list: "list"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("accentKey") private var accentKey = AccentRamp.fallback.key
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("startingTab") private var startingTabRaw = AppTab.library.rawValue
    @AppStorage("interests") private var interestsRaw = ""

    @State private var tab: AppTab = .library
    /// One-shot: hand the caret to Browse's search field after the tab switch.
    @State private var focusBrowseSearch = false
    @State private var showingAdd = false
    /// A link the person had already pasted when the wall went up. Signing up
    /// hands it straight back to a fresh Add sheet — being asked to find and
    /// paste the same link again is the part that would make this feel like a
    /// punishment.
    @State private var pendingSave: URL?
    /// The save-limit wall, and the auth flow it leads to. Both live here
    /// rather than in the Library because the + button, the Add sheet and a
    /// share that landed over the limit all raise the same one sheet.
    @State private var wall: SaveLimitReason?
    @State private var showingWallAuth = false
    @State private var wallAuthMode: AuthSheet.Mode = .signUp
    @State private var toast: String?
    /// "Undo" after a filing, "Sort" after shares arrive.
    @State private var toastAction: ToastAction?
    @State private var toastToken = UUID()
    /// "Sort your borks", from the inbox toast (and `-triage`).
    @State private var triage: TriageSheet.Deck?
    /// Drives the You-tab dot. A count rather than a `@Query` of every
    /// bookmark: the root view re-renders on every tab change and does not
    /// need the rows, only how many there are.
    @State private var borkCount = 0
    @StateObject private var account = Account()
    @AppStorage("browseAxis") private var browseAxis = "topics"

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]
    /// For the press-and-hold "Side quest" menu on every bork.
    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var sideQuests: [Mission]

    /// Deep-link target when a category chip is tapped from a detail sheet.
    @State private var pendingTopic: String?
    /// A collection link opened into the app (`bookmarker://c/<slug>`).
    @State private var collectionRoute: CollectionRoute?
    /// A link that arrived before the first-run tour was done, or while
    /// another sheet was up. Presented the moment the screen is clear.
    @State private var pendingCollection: String?
    /// Borks a shared link added to the library, announced once its sheet
    /// is gone — a toast under a sheet is a toast nobody sees.
    @State private var collectionSaved = 0

    private var accent: AccentRamp { AccentRamp.named(accentKey) }
    private var interests: [String] {
        interestsRaw.split(separator: ",").map(String.init)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Tokens.paper.ignoresSafeArea()

            Group {
                switch tab {
                case .library: LibraryView(
                    onAdd: requestAdd,
                    onSearch: {
                        browseAxis = BrowseView.Axis.topics.rawValue
                        focusBrowseSearch = true
                        tab = .browse
                    },
                    onSeeJourneys: {
                        browseAxis = BrowseView.Axis.journeys.rawValue
                        tab = .browse
                    },
                    onShowWall: { wall = $0 },
                    onOpenAccount: { tab = .you },
                    account: account,
                    // Every sheet the root owns, so a milestone sheet never
                    // goes up behind one of them.
                    canInterrupt: !showingAdd && wall == nil && !showingWallAuth
                        && triage == nil && collectionRoute == nil && hasOnboarded
                )
                case .browse: BrowseView(
                    interests: interests,
                    pendingTopic: $pendingTopic,
                    focusSearch: $focusBrowseSearch,
                    account: account
                )
                case .revisit: RevisitView(account: account)
                case .you: YouView(onReplayTour: { hasOnboarded = false }, account: account)
                }
            }
            // Pinned to the screen's width. A ZStack is as wide as its widest
            // child and re-proposes that width to every child, so one tab
            // laying out too wide (build 14: a cover widened the Library by
            // ~70pt a side) dragged the dock off both edges with it. Pinned,
            // an overflow stays that tab's problem and the dock stays put.
            .containerRelativeFrame(.horizontal)
            .environment(\.accent, accent)
            .environment(\.account, account)
            .environment(\.sideQuests, sideQuests)

            if let toast {
                ToastView(text: toast, action: toastAction) {
                    withAnimation(.easeOut(duration: 0.2)) { self.toast = nil }
                }
                // 12 pt above the tab bar, which the safe-area inset below
                // has already lifted this ZStack's bottom edge past.
                .padding(.bottom, 12)
                .padding(.horizontal, Tokens.gutter)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The flat tab bar is a bottom safe-area inset, not a layer drawn over
        // the content: every ScrollView stops above it, so nothing scrolls
        // under it or peeks beside it (1.3's floating dock needed every screen
        // to pad `.bottom, 120`). The keyboard is ignored so the bar stays
        // down behind it rather than riding up on top of it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabDock(
                tab: $tab,
                onAdd: requestAdd,
                signedOutDot: SignInNudge.showsBadge(signedIn: account.isSignedIn, borks: borkCount)
            )
            .environment(\.accent, accent)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.accent, accent)
        .tint(accent.base)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingAdd) {
            AddSheet(
                initialURL: pendingSave,
                onSaved: { message, undo in
                    pendingSave = nil
                    showToast(message, action: undo.map { ToastAction(title: "Undo", perform: $0) })
                    tab = .library
                    refreshBorkCount()
                },
                // The limit was reached while the sheet was open. Keep the
                // link, close the sheet, raise the wall — and never lose what
                // they pasted.
                onLimitReached: { url in
                    pendingSave = url
                    showingAdd = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(420))
                        wall = .addSheet
                    }
                },
                account: account
            )
            .environment(\.accent, accent)
        }
        .sheet(item: $triage, onDismiss: refreshBorkCount) { deck in
            TriageSheet(deck: deck, account: account)
                .environment(\.accent, accent)
        }
        .sheet(item: $wall) { _ in
            SaveLimitWall(
                liveCount: borkCount,
                onSignUp: { wall = nil; presentWallAuth(.signUp) },
                onSignIn: { wall = nil; presentWallAuth(.signIn) },
                onMakeRoom: {
                    wall = nil
                    pendingSave = nil
                    tab = .library
                    // No multi-select delete exists and this is not the moment
                    // to build one — deleting is a tap into a bork and the bin
                    // in its footer, so say that rather than inventing a
                    // gesture the app does not have.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(380))
                        showToast("Open any bork and tap the bin to make room")
                    }
                }
            )
            .environment(\.accent, accent)
        }
        .sheet(isPresented: $showingWallAuth) {
            AuthSheet(account: account, mode: wallAuthMode)
                .environment(\.accent, accent)
        }
        .sheet(item: $collectionRoute, onDismiss: announceCollectionSaves) { route in
            Group {
                switch route {
                case .incoming(let slug):
                    SharedCollectionSheet(slug: slug, account: account) { added in
                        collectionSaved = added
                    }
                case .list:
                    CollectionsList(account: account)
                }
            }
            .environment(\.accent, accent)
        }
        .onOpenURL { url in
            guard let slug = CollectionShare.slug(from: url) else { return }
            pendingCollection = slug
            presentPendingCollection()
        }
        .onChange(of: hasOnboarded) { _, done in
            if done { presentPendingCollection() }
        }
        .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
            OnboardingView(
                accentKey: $accentKey,
                onFinish: { picked in
                    interestsRaw = picked.joined(separator: ",")
                    hasOnboarded = true
                }
            )
            .environment(\.accent, accent)
        }
        .onAppear {
            // Before the merged taxonomy is built, so it never installs a
            // topic under an id that is about to change underneath it.
            let folded = Store.foldCustomTopicIDs(in: context)
            if folded > 0 {
                Logger(subsystem: "com.jpwilson.borkmarkr", category: "migration")
                    .notice("Folded custom topic ids: \(folded, privacy: .public) rows re-keyed")
            }
            _ = MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
            // The Share Extension's dial draws topic art from App Group
            // thumbnails; this keeps them there (off the main actor).
            QuickFileBridge.installArtIfNeeded(customTopics: customTopics)
            Store.retryOEmbedPreviews(in: context)
            if let saved = AppTab.resolve(startingTabRaw) {
                tab = saved
                // Write the migrated value back so the You tab's picker has
                // something it can show as selected.
                if startingTabRaw != saved.rawValue { startingTabRaw = saved.rawValue }
            }
            #if DEBUG
            if DebugSeed.isRequested {
                DebugSeed.run(in: context)
                hasOnboarded = true
                // The seed's own topic arrived after the install above.
                let seededTopics = (try? context.fetch(FetchDescriptor<CustomTopic>())) ?? []
                _ = MergedTaxonomy(topics: seededTopics.filter { $0.deletedAt == nil })
            }
            #endif
            ReviewPrompter.recordLaunch()
            #if DEBUG
            if ScreenshotDefaults.openAdd {
                pendingSave = ScreenshotDefaults.addURL
                hasOnboarded = true
                showingAdd = true
            }
            if CollectionsDebug.openList {
                hasOnboarded = true
                collectionRoute = .list
            }
            if ScreenshotDefaults.openTriage {
                hasOnboarded = true
                Task { @MainActor in
                    // After the seed and the first frame, or the sheet is dropped.
                    try? await Task.sleep(for: .milliseconds(700))
                    triage = TriageSheet.Deck(rawValue: ScreenshotDefaults.triageDeck ?? "") ?? .unfiled
                }
            }
            if let mode = ScreenshotDefaults.openAuth {
                hasOnboarded = true
                presentWallAuth(mode.lowercased() == "signin" ? .signIn : .signUp)
            }
            if let kind = ScreenshotDefaults.openWall {
                hasOnboarded = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    switch kind {
                    case "waiting": wall = .waiting
                    case "addSheet": wall = .addSheet
                    default: wall = .add
                    }
                }
            }
            if let text = ScreenshotDefaults.toast {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    showToast(text, action: ToastAction(title: "Undo") {})
                }
            }
            if let slug = CollectionsDebug.incomingSlug {
                hasOnboarded = true
                pendingCollection = slug
                presentPendingCollection()
            }
            #endif
            drain()
            Store.admitWaiting(in: context, signedIn: account.isSignedIn)
            refreshBorkCount()
            Task { await account.sync(context: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving: whatever was filed while we were open reaches the
            // Share Extension's next dial.
            if phase == .background {
                QuickFileBridge.refreshSnapshot(context: context)
            }
            // The Share Extension queues saves while we're backgrounded; pick
            // them up the moment we're visible again.
            if phase == .active {
                drain()
                // Room may have been made on another device, or by a delete
                // in this one before it was backgrounded.
                Store.admitWaiting(in: context, signedIn: account.isSignedIn)
                refreshBorkCount()
                Task { await account.sync(context: context) }
            }
        }
        // Keep both clients current while the app stays open after editing.
        // This task is cancelled automatically when the root leaves the tree.
        .task(id: account.isSignedIn) {
            guard account.isSignedIn else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if scenePhase == .active { await account.sync(context: context) }
            }
        }
        .onChange(of: account.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            // Admit before syncing, not after. A waiting bork is deliberately
            // never pushed, so anything still flagged when `push` runs would
            // sit out its own first backup and wait for the next foreground.
            Store.admitWaiting(in: context, signedIn: true)
            refreshBorkCount()
            // Back up the moment someone signs in, not at the next foreground.
            // Push runs before pull, so what's on the phone is never at risk.
            Task { await account.sync(context: context) }
        }
        // Finish the save they were making when the wall went up — but only
        // once the auth sheet is actually gone. Signing in happens *inside*
        // that sheet, and a presentation raised while it is still up is
        // silently dropped, which would lose the link this whole dance exists
        // to keep.
        .onChange(of: showingWallAuth) { _, showing in
            guard !showing, account.isSignedIn, pendingSave != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard pendingSave != nil else { return }
                showingAdd = true
            }
        }
        .onChange(of: pendingTopic) { _, value in
            if value != nil { tab = .browse }
        }
        .onChange(of: tab) { _, _ in refreshBorkCount() }
    }

    /// The + button, from the dock and from the empty Library.
    ///
    /// At the limit this raises the wall instead of the Add sheet. It is the
    /// one place the app says no, and it says it before the keyboard comes up
    /// rather than after a link has been pasted and a title fetched — being
    /// stopped at the door is kinder than being stopped at the till.
    ///
    /// The count is read here rather than taken from `borkCount`. That cache
    /// is refreshed on appearance, on foreground, on a save and on a tab
    /// change — and a **delete** is none of those. So the wall's own "Make
    /// room instead", which tells you to open a bork and tap the bin, left the
    /// count at twenty and put the wall straight back up on the next +: the
    /// one escape hatch the sheet offers did not work. `liveCount` counts in
    /// SQL, and this runs on a tap.
    private func requestAdd() {
        let live = Store.liveCount(in: context)
        borkCount = live
        if SaveLimit.shouldWall(liveCount: live, signedIn: account.isSignedIn) {
            wall = .add
        } else {
            showingAdd = true
        }
    }

    /// Present the link that was opened, once nothing is in the way. The
    /// wall, the Add sheet and the auth sheet all yield — someone tapped a
    /// link, and the link is what they want to see. The first-run tour does
    /// not: it finishes first, and the link is presented after it.
    private func presentPendingCollection() {
        guard hasOnboarded, pendingCollection != nil else { return }
        showingAdd = false
        wall = nil
        showingWallAuth = false
        collectionRoute = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard let slug = pendingCollection else { return }
            pendingCollection = nil
            collectionRoute = .incoming(slug: slug)
        }
    }

    /// After a shared link's sheet closes: the copies are in the library
    /// (`collection_save` then a sync), so show the library and say so.
    private func announceCollectionSaves() {
        let added = collectionSaved
        collectionSaved = 0
        refreshBorkCount()
        guard added > 0 else { return }
        tab = .library
        showToast(added == 1 ? "1 new bork" : "\(added) new borks")
    }

    private func presentWallAuth(_ mode: AuthSheet.Mode) {
        wallAuthMode = mode
        // Let the wall finish dismissing; SwiftUI drops a presentation raised
        // into another sheet's transition.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            showingWallAuth = true
        }
    }

    /// Cheap enough to run on every tab change — SwiftData counts in SQL
    /// rather than materialising the rows.
    ///
    /// Counts the **live** library: a waiting bork is saved, but it is not one
    /// of the twenty and must not push the limit further out of reach.
    private func refreshBorkCount() {
        borkCount = Store.liveCount(in: context)
    }

    private func drain() {
        let result = Store.drainInbox(into: context, signedIn: account.isSignedIn)
        // The Share Extension ranks from a snapshot of your filings; the
        // shares just drained may have been filed on its dial.
        QuickFileBridge.scheduleSnapshot(context: context)
        if result.saved > 0 {
            showToast(result.saved == 1 ? "1 new bork" : "\(result.saved) new borks", action: sortAction())
        } else if result.alreadyHad > 0 {
            showToast(result.alreadyHad == 1 ? "Already in your library" : "\(result.alreadyHad) already in your library")
        }
        guard result.saved > 0 else { return }

        // A share that landed over the limit is already saved and already on
        // screen, greyed, in the Library. The wall is what explains it — and
        // this is the one path where it is raised by something other than a
        // tap, which is exactly why it is gated on borks actually waiting.
        guard result.waiting > 0, hasOnboarded, !showingAdd, wall == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard wall == nil, !showingAdd else { return }
            tab = .library
            wall = .waiting
        }
    }

    /// "Sort" on the inbox toast — only when something that just arrived
    /// still has no topic, or only our guess, and there is a deck to open.
    /// Shares arrive marked unread until the Library has been seen.
    private func sortAction() -> ToastAction? {
        let unread = FetchDescriptor<Bookmark>(predicate: #Predicate {
            $0.deletedAt == nil && $0.waitingSince == nil && $0.isUnread == true
        })
        let arrived = (try? context.fetch(unread)) ?? []
        guard arrived.contains(where: {
            Taxonomy.category(id: $0.categoryID) == nil || $0.filingSource == "automatic"
        }) else { return nil }
        var everything = FetchDescriptor<Bookmark>(predicate: #Predicate {
            $0.deletedAt == nil && $0.waitingSince == nil
        })
        everything.sortBy = [SortDescriptor(\.savedAt, order: .reverse)]
        let library = (try? context.fetch(everything)) ?? []
        guard let deck = TriageSheet.deckWorthSorting(library, customIDs: customTopics.map(\.id)) else { return nil }
        return ToastAction(title: "Sort") { triage = deck }
    }

    private func showToast(_ message: String, action: ToastAction? = nil) {
        let token = UUID()
        toastToken = token
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
            toast = message
            toastAction = action
        }
        Task {
            // Long enough to reach for the action when there is one.
            try? await Task.sleep(for: .seconds(action == nil ? 2.1 : 4.5))
            // Only this toast's own timer may take it down. Without the check,
            // a toast shown a second after another vanished a second later.
            guard toastToken == token else { return }
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

/// The tab bar: Library · Browse · [+] · Revisit · You (SYSTEM.md, Main.dc).
///
/// Flat and pinned to the bottom: paper, a hairline on top, no shadow, five
/// equal slots 56 pt tall above the home indicator; the + is a 52 pt coral
/// circle in line with the tabs. Labels 11/13 semibold; the selected tab is in
/// the accent's deep, the others in secondary. Mounted by RootView as a bottom
/// `safeAreaInset`, so content never runs under it.
///
/// UI tests find the tabs by their labels (Library / Browse / Revisit / You).
struct TabDock: View {
    @Binding var tab: AppTab
    let onAdd: () -> Void
    /// A small dot on You while the library is signed out — the one cue that
    /// is visible from every tab. Subtle on purpose: it points, it doesn't
    /// interrupt.
    var signedOutDot: Bool = false
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 0) {
            item(.library)
            item(.browse)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Tokens.addButton, height: Tokens.addButton)
                    .background(accent.base, in: Circle())
                    .frame(maxWidth: .infinity)
                    .frame(height: Tokens.tabBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .accessibilityLabel("Save a link")
            item(.revisit)
            item(.you)
        }
        .padding(.horizontal, 8)
        .frame(height: Tokens.tabBarHeight)
        .frame(maxWidth: .infinity)
        .background {
            Tokens.paper
                .overlay(alignment: .top) {
                    Rectangle().fill(Tokens.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Main.dc's line icons: outline, 1.75 stroke, the same when selected
    /// (only the colour changes).
    private static func outline(_ target: AppTab) -> String {
        switch target {
        case .library: "bookmark"
        case .browse: "square.grid.2x2"
        case .revisit: "clock.arrow.circlepath"
        case .you: "person"
        }
    }

    private func item(_ target: AppTab) -> some View {
        let on = tab == target
        return Button {
            tab = target
        } label: {
            VStack(spacing: 3) {
                Image(systemName: Self.outline(target))
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if target == .you, signedOutDot {
                            Circle()
                                .fill(accent.base)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Tokens.paper, lineWidth: 1.5))
                                .offset(x: 5, y: -1)
                        }
                    }
                Text(target.title)
                    .font(.custom("Instrument Sans", size: 11).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? accent.deep : Tokens.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Tokens.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityHint(target == .you && signedOutDot
                           ? "Not signed in — your borks are only on this phone" : "")
    }
}

/// A toast's one action, after a hairline: "Undo", "Sort".
struct ToastAction {
    let title: String
    let perform: () -> Void
}

struct ToastView: View {
    let text: String
    var action: ToastAction? = nil
    /// As the action runs: the toast goes at once rather than lingering. It
    /// runs first, so the action can raise the next toast ("Save removed").
    var onAction: () -> Void = {}

    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tokens.toastCheck)
            Text(text)
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let action {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: 18)
                    .padding(.leading, 2)
                Button {
                    Haptics.tap()
                    onAction()
                    action.perform()
                } label: {
                    Text(action.title)
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(accent.base)
                        .padding(.horizontal, 6)
                        .frame(minHeight: Tokens.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, action == nil ? 18 : 10)
        .padding(.vertical, action == nil ? 12 : 0)
        .background(Tokens.toastBG, in: Capsule())
        .lift(.toast)
    }
}
