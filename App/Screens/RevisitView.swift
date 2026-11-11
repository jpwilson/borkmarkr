import SwiftUI
import SwiftData

/// The tab that answers one question: **what should I look at again?**
///
/// The product thesis is "everything interesting you scroll past every day,
/// captured, organised, revisited, shared". Capture is the Share Extension,
/// organising is Browse, sharing is on the way — and *revisited* was the verb
/// with no home. Nothing in the app ever said "you saved eleven things last
/// month and opened none of them", which is the single most useful sentence a
/// bookmark app can say, and the reason platform bookmarks are write-only
/// graveyards.
///
/// Stacked sections, each hidden when it has nothing to show, ordered by how
/// likely they are to send someone back into their library. **Saved, never
/// opened** is the one that earns the tab, and it gets the room.
///
/// The weekly read ("What are you finding interesting?") opens the tab, in its
/// compact form: it left the Library in 1.4 and lives here and on You.
///
/// The screen is a renderer. Every number here comes from `Revisit`, which is
/// pure and tested — see `Core/Revisit.swift` for why.
struct RevisitView: View {
    var account: Account? = nil

    @Environment(\.accent) private var accent

    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var bookmarks: [Bookmark]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var quests: [Mission]

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]
    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]

    @State private var model: Revisit.Model?
    /// The bookmarks behind the model's ids, built once per rebuild rather
    /// than per render. As a computed property this was four dictionary passes
    /// over the whole library every time the body ran — the sections between
    /// them each need it. The objects are references, so a title edited in the
    /// detail sheet still renders; only a change in *which* borks exist needs a
    /// new index, and that is exactly what triggers a rebuild.
    @State private var index: [String: Bookmark] = [:]
    @State private var path = NavigationPath()
    @State private var detail: Bookmark?
    @State private var openQuest: Mission?
    @State private var showingBackupBanner = false
    @State private var showingAuth = false
    @State private var showingInsights = false
    @State private var creatingQuestTitle: String?
    /// The never-opened pile, dealt one at a time.
    @State private var goingThrough: [Bookmark]?
    #if DEBUG
    @State private var openedLaunchQueue = false
    #endif

    private enum Route: Hashable {
        case topic(String)
        case neverOpened
    }

    private var openTotal: Int {
        bookmarks.reduce(0) { $0 + $1.openCount }
    }

    private var merged: MergedTaxonomy {
        MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.sectionGap) {
                    top

                    if showingBackupBanner {
                        SignInNudgeBanner(
                            headline: "Back these up.",
                            onSignUp: { showingAuth = true },
                            onDismiss: {
                                SignInNudge.dismissBanner()
                                withAnimation(Motion.gentle) { showingBackupBanner = false }
                            }
                        )
                        .padding(.horizontal, Tokens.gutter)
                        .transition(.opacity)
                    }

                    if let model {
                        if model.isThin || model.hasNothing {
                            ThinRevisitCard(count: model.total)
                                .padding(.horizontal, Tokens.gutter)
                        } else {
                            sections(model)
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .background(Tokens.paper)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .topic(let id):
                    if let topic = merged.topic(id: id) { TopicPage(category: topic) }
                case .neverOpened:
                    NeverOpenedList(
                        items: (model?.neverOpened?.items ?? []).compactMap { index[$0.id] }
                    )
                }
            }
            .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
            .sheet(item: $openQuest) { quest in
                MissionDetailSheet(mission: quest, account: account).environment(\.accent, accent)
            }
            .sheet(isPresented: $showingAuth) {
                if let account {
                    AuthSheet(account: account, mode: .signUp).environment(\.accent, accent)
                }
            }
            .sheet(isPresented: $showingInsights) {
                InsightsSheet(bookmarks: bookmarks, account: account) { title in
                    creatingQuestTitle = title
                }
                .environment(\.accent, accent)
            }
            .sheet(isPresented: Binding(
                get: { creatingQuestTitle != nil },
                set: { if !$0 { creatingQuestTitle = nil } }
            )) {
                NewMissionSheet(seed: creatingQuestTitle.map {
                    Mission.Seed(title: $0, categoryID: nil, subcategory: nil,
                                 bookmarkIDs: [], sampleTitles: [], blurb: "")
                })
                .environment(\.accent, accent)
            }
        }
        // Rebuilt on appearance, whenever the library changes size, and
        // whenever something is opened — keyed on counts alone, a bork you had
        // just opened stayed under "Saved, never opened" until the next save.
        // The build itself runs off the main actor, so switching to this tab
        // never waits on it — the sections fade in a frame later on a big
        // library rather than holding the dock.
        .task(id: "\(bookmarks.count)-\(quests.count)-\(openTotal)") { await rebuild() }
        .sheet(isPresented: Binding(get: { goingThrough != nil }, set: { if !$0 { goingThrough = nil } })) {
            RevisitQueueSheet(bookmarks: goingThrough ?? [])
                .environment(\.accent, accent)
        }
        .onAppear {
            readNudgePolicy()
            #if DEBUG
            if ScreenshotDefaults.openInsights { showingInsights = true }
            #endif
        }
        .onChange(of: account?.isSignedIn ?? false) { _, _ in readNudgePolicy() }
    }

    /// Title, then the weekly read as one compact card.
    private var top: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("Revisit", subtitle: "What's worth another look.")
            Button { showingInsights = true } label: {
                InsightsEntry(bookmarks: bookmarks, compact: true)
            }
            .buttonStyle(PressableStyle(scale: 0.99))
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.top, 12)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sections(_ model: Revisit.Model) -> some View {
        if let week = model.thisWeek { savedThisWeek(week) }
        if !model.comingBack.isEmpty { comingBack(model.comingBack) }
        if let stale = model.neverOpened { neverOpened(stale) }
        if !model.monthAgo.isEmpty { monthAgo(model.monthAgo) }
        if !model.quests.isEmpty { questsInProgress(model.quests) }
        if let sentence = model.shiftSentence { shifting(sentence, model.shifts) }
    }

    /// 1 — Saved this week.
    private func savedThisWeek(_ week: Revisit.ThisWeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Saved this week")

            VStack(alignment: .leading, spacing: 14) {
                Text(week.headline)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !week.rising.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Growing").textRole(.label, color: Tokens.inkSecondary)
                        FlowLayout(spacing: Tokens.chipGap) {
                            ForEach(week.rising) { growth in
                                TopicChip(
                                    "\(growth.name) +\(growth.gain)",
                                    palette: merged.topic(id: growth.id)?.palette ?? NeutralPalette.value,
                                    isOn: false,
                                    size: .filter
                                ) { path.append(Route.topic(growth.id)) }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .padding(.horizontal, Tokens.gutter)
        }
    }

    /// 2 — You keep coming back to.
    private func comingBack(_ items: [RevisitBork]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("You keep coming back to",
                           caption: "The ones you've opened again.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Tokens.gridGap) {
                    ForEach(items) { item in
                        if let bookmark = index[item.id] {
                            Button { detail = bookmark } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    BookmarkCard(bookmark: bookmark)
                                    Text(openLine(item))
                                        .textRole(.meta)
                                        .padding(.leading, 4)
                                }
                                .frame(width: 168)
                            }
                            .buttonStyle(PressableStyle())
                            .borkActions(bookmark)
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
            }
            .scrollClipDisabled()
        }
    }

    private func openLine(_ item: RevisitBork) -> String {
        item.openCount == 1 ? "Opened once" : "Opened \(item.openCount) times"
    }

    /// 3 — Saved, never opened. The section the tab is for, so it gets a full
    /// list rather than a strip: the point is the *length* of the pile.
    private func neverOpened(_ stale: Revisit.NeverOpened) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Saved, never opened", caption: stale.headline)

            // Right under the heading, where the UI test (and a thumb) finds it.
            Button {
                Haptics.tap()
                goingThrough = stale.items.compactMap { index[$0.id] }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold))
                    Text("Go through them, one at a time")
                }
            }
            .buttonStyle(.clayPrimary)
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, 2)
            .accessibilityIdentifier("revisit-go-through")

            LazyVStack(spacing: 8) {
                ForEach(stale.preview) { item in
                    if let bookmark = index[item.id] {
                        Button { detail = bookmark } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .buttonStyle(PressableStyle())
                        .borkActions(bookmark)
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)

            if stale.overflow > 0 {
                Button { path.append(Route.neverOpened) } label: {
                    HStack(spacing: 4) {
                        Text("and \(stale.overflow) more")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.clayQuiet)
                .padding(.horizontal, Tokens.gutter)
                .padding(.vertical, -6)
            }
        }
    }

    /// 4 — A month ago today.
    private func monthAgo(_ items: [RevisitBork]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("A month ago today",
                           caption: "What you were saving four weeks back.")

            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    if let bookmark = index[item.id] {
                        Button { detail = bookmark } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .buttonStyle(PressableStyle())
                        .borkActions(bookmark)
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
        }
    }

    /// 5 — Side quests in progress. The Library's card, unchanged.
    private func questsInProgress(_ items: [RevisitQuest]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Side quests in progress")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.gridGap) {
                    ForEach(items) { item in
                        if let quest = quests.first(where: { $0.id == item.id }) {
                            Button { openQuest = quest } label: {
                                QuestCard(
                                    title: quest.title,
                                    count: quest.bookmarkIDs.count,
                                    palette: quest.topic?.palette ?? NeutralPalette.value,
                                    cover: QuestCover.resolve(title: quest.title, categoryID: quest.categoryID),
                                    layout: .rail,
                                    habit: quest.hasHabit,
                                    topicName: quest.topic?.name
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
            }
            .scrollClipDisabled()
        }
    }

    /// 6 — What's shifting.
    private func shifting(_ sentence: String, _ shifts: [Revisit.Shift]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("What's shifting",
                           caption: "The last 30 days against the 30 before.")

            VStack(alignment: .leading, spacing: 12) {
                Text(sentence)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Tokens.hairline.frame(height: 1)

                VStack(spacing: 8) {
                    ForEach(shifts) { shift in
                        HStack(spacing: 8) {
                            Image(systemName: shift.isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(shift.isUp ? accent.deep : Tokens.inkSecondary)
                                .accessibilityLabel(shift.isUp ? "Up" : "Down")
                            Text(shift.name)
                                .textRole(.body, color: Tokens.ink)
                            Spacer(minLength: 6)
                            Text("\(percent(shift.previousShare)) → \(percent(shift.share))")
                                .textRole(.meta)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .padding(.horizontal, Tokens.gutter)
        }
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    // MARK: - Model

    private func rebuild() async {
        let input = Revisit.snapshot(from: bookmarks, missions: quests)
        let borks = input.borks
        let quests = input.quests
        let now = Date.now
        let built = await Task.detached(priority: .userInitiated) {
            Revisit.build(borks: borks, quests: quests, now: now)
        }.value
        index = Dictionary(bookmarks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        model = built
        #if DEBUG
        // `-revisitQueue`: deal the never-opened pile once there is a model.
        if ScreenshotDefaults.openRevisitQueue, !openedLaunchQueue, let stale = built.neverOpened {
            openedLaunchQueue = true
            goingThrough = stale.items.compactMap { index[$0.id] }
        }
        #endif
    }

    /// The same policy the Library reads, on the same one call site shape. The
    /// dismissal is shared: an ✕ here quiets the banner there too, because it
    /// is one sentence about one library, not two notifications.
    private func readNudgePolicy() {
        guard let account else {
            showingBackupBanner = false
            return
        }
        showingBackupBanner = SignInNudge.showsBanner(
            signedIn: account.isSignedIn, borks: bookmarks.count
        )
    }
}

/// The shared `SectionHeader`, plus the one meta line Revisit puts under it.
/// One component, so six sections can't drift into six styles.
private struct SectionHeading: View {
    let title: String
    var caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title)
            if let caption {
                Text(caption)
                    .textRole(.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Tokens.gutter)
    }
}

/// Under ten borks there is nothing honest to say, so the screen says what it
/// will say instead of showing six empty headings. Naming the actual sections
/// is the point: it tells someone what saving ten things buys them.
private struct ThinRevisitCard: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClayArtImage(source: .quest(.scroll))
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .background(Tokens.clayGround)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text("Save ten things and this fills in")
                    .textRole(.sectionTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("What you keep coming back to, what you saved and never opened, what a month ago looked like.")
                    .textRole(.body, color: Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(count == 0 ? "Nothing saved yet." : "\(Copy.countedBorks(count)) so far.")
                    .textRole(.meta)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// "and N more" — the whole never-opened pile, newest first.
private struct NeverOpenedList: View {
    let items: [Bookmark]

    @Environment(\.accent) private var accent
    @State private var detail: Bookmark?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(items) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(PressableStyle())
                    .borkActions(bookmark)
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Tokens.paper)
        .navigationTitle("Saved, never opened")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
    }
}
