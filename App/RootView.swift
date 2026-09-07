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

    /// Deep-link target when a category chip is tapped from a detail sheet.
    @State private var pendingTopic: String?

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
                    account: account,
                    canInterrupt: !showingAdd && wall == nil && hasOnboarded
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
            .environment(\.accent, accent)

            TabDock(
                tab: $tab,
                onAdd: requestAdd,
                signedOutDot: SignInNudge.showsBadge(signedIn: account.isSignedIn, borks: borkCount)
            )
                .environment(\.accent, accent)

            if let toast {
                ToastView(text: toast)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.accent, accent)
        .tint(accent.base)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingAdd) {
            AddSheet(
                initialURL: pendingSave,
                onSaved: { message in
                    pendingSave = nil
                    showToast(message)
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
            }
            #endif
            ReviewPrompter.recordLaunch()
            #if DEBUG
            if ScreenshotDefaults.openAdd {
                pendingSave = ScreenshotDefaults.addURL
                hasOnboarded = true
                showingAdd = true
            }
            #endif
            drain()
            Store.admitWaiting(in: context, signedIn: account.isSignedIn)
            refreshBorkCount()
            Task { await account.sync(context: context) }
        }
        .onChange(of: scenePhase) { _, phase in
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
        guard result.saved > 0 else { return }
        showToast(result.saved == 1 ? "1 new save" : "\(result.saved) new saves")

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

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.1))
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

/// Floating dock: Library · Browse · [+] · Revisit · You.
struct TabDock: View {
    @Binding var tab: AppTab
    let onAdd: () -> Void
    /// A small dot on You while the library is signed out — the one cue that
    /// is visible from every tab. Subtle on purpose: it points, it doesn't
    /// interrupt.
    var signedOutDot: Bool = false
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                item(.library)
                item(.browse)
                Spacer().frame(width: 62)
                item(.revisit)
                item(.you)
            }
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                    // Paper UNDER the glass, not instead of it.
                    //
                    // `.ultraThinMaterial` alone takes its lightness from
                    // whatever is behind it, and the feed scrolls behind the
                    // dock. Over a dark media cover the material went dark too
                    // and the inactive tabs — `inkFaint` on nothing — vanished
                    // completely: a screenshot of the Library caught "Browse"
                    // as an invisible gap between Library and the + button.
                    //
                    // An opaque fill would fix the contrast and kill the depth.
                    // A near-opaque paper layer beneath the material keeps the
                    // translucency reading as glass while pinning the effective
                    // background light, so contrast no longer depends on what
                    // the user happens to have scrolled to.
                    .fill(Tokens.paper.opacity(0.82))
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                            .stroke(Tokens.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "191510").opacity(0.30), radius: 22, y: 14)
            )

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(accent.base, in: Circle())
                    .overlay(Circle().stroke(Tokens.paper, lineWidth: 3))
                    .shadow(color: accent.base.opacity(0.45), radius: 10, y: 6)
            }
            .offset(y: -24)
            .accessibilityLabel("Save a link")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func item(_ target: AppTab) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 3) {
                Image(systemName: target.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if target == .you, signedOutDot {
                            Circle()
                                .fill(accent.base)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Tokens.paper, lineWidth: 1.5))
                                .offset(x: 5, y: -3)
                        }
                    }
                Text(target.title)
                    .font(Typo.ui(9.5, .semibold))
            }
            // `inkFaint` is a decorative grey — 2.4:1 on paper, and this is a
            // primary navigation control, not a hint. `inkSecondary` reads as
            // clearly unselected while staying legible.
            .foregroundStyle(tab == target ? accent.base : Tokens.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == target ? [.isSelected] : [])
        .accessibilityHint(target == .you && signedOutDot
                           ? "Not signed in — your borks are only on this phone" : "")
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tokens.toastCheck)
            Text(text)
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Tokens.toastBG, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}
