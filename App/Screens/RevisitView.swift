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
/// The screen is a renderer. Every number here comes from `Revisit`, which is
/// pure and tested — see `Core/Revisit.swift` for why.
struct RevisitView: View {
    var account: Account? = nil

    @Environment(\.accent) private var accent

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil },
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

    private enum Route: Hashable {
        case topic(String)
        case neverOpened
    }

    private var merged: MergedTaxonomy {
        MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if showingBackupBanner {
                        SignInNudgeBanner(
                            headline: "Back these up.",
                            onSignUp: { showingAuth = true },
                            onDismiss: {
                                SignInNudge.dismissBanner()
                                withAnimation(Motion.gentle) { showingBackupBanner = false }
                            }
                        )
                        .padding(.horizontal, 18)
                        .transition(.opacity)
                    }

                    if let model {
                        if model.isThin || model.hasNothing {
                            ThinRevisitCard(count: model.total)
                                .padding(.horizontal, 18)
                        } else {
                            sections(model)
                        }
                    }
                }
                .padding(.bottom, 120)
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
        }
        // Rebuilt on appearance and whenever the library changes size. The
        // build itself runs off the main actor, so switching to this tab never
        // waits on it — the sections fade in a frame later on a big library
        // rather than holding the dock.
        .task(id: "\(bookmarks.count)-\(quests.count)") { await rebuild() }
        .onAppear { readNudgePolicy() }
        .onChange(of: account?.isSignedIn ?? false) { _, _ in readNudgePolicy() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Revisit")
                .font(Typo.display(34, .heavy))
                .tracking(-1.0)
                .foregroundStyle(Tokens.ink)
            Text("What's worth another look.")
                .font(Typo.ui(12.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
        .padding(.horizontal, 18)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Saved this week")

            VStack(alignment: .leading, spacing: 12) {
                Text(week.headline)
                    .font(Typo.ui(14.5, .semibold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !week.rising.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Growing")
                            .font(Typo.ui(10, .heavy)).tracking(0.6)
                            .foregroundStyle(Tokens.mutedHeading)
                        FlowLayout(spacing: 7) {
                            ForEach(week.rising) { growth in
                                Button { path.append(Route.topic(growth.id)) } label: {
                                    let palette = merged.topic(id: growth.id)?.palette ?? NeutralPalette.value
                                    HStack(spacing: 5) {
                                        Text(growth.name)
                                            .font(Typo.ui(12.5, .semibold))
                                        Text("+\(growth.gain)")
                                            .font(Typo.ui(11, .bold))
                                            .opacity(0.75)
                                    }
                                    .foregroundStyle(palette.deep)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(palette.tint, in: Capsule())
                                    .tappableChip()
                                }
                                .buttonStyle(ChipStyle())
                            }
                        }
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: 18)
            .padding(.horizontal, 18)
        }
    }

    /// 2 — You keep coming back to.
    private func comingBack(_ items: [RevisitBork]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("You keep coming back to",
                           caption: "The ones you've opened again.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        if let bookmark = index[item.id] {
                            Button { detail = bookmark } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    BookmarkCard(bookmark: bookmark)
                                    Text(openLine(item))
                                        .font(Typo.ui(11, .semibold))
                                        .foregroundStyle(Tokens.inkMeta)
                                        .padding(.horizontal, 2)
                                }
                                .frame(width: 176)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
        }
    }

    private func openLine(_ item: RevisitBork) -> String {
        item.openCount == 1 ? "Opened once" : "Opened \(item.openCount) times"
    }

    /// 3 — Saved, never opened. The section the tab is for, so it gets a full
    /// list rather than a strip: the point is the *length* of the pile.
    private func neverOpened(_ stale: Revisit.NeverOpened) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Saved, never opened")
                    .font(Typo.display(22, .bold))
                    .foregroundStyle(Tokens.ink)
                Text(stale.headline)
                    .font(Typo.ui(13.5, .medium))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)

            LazyVStack(spacing: 9) {
                ForEach(stale.preview) { item in
                    if let bookmark = index[item.id] {
                        Button { detail = bookmark } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, 18)

            if stale.overflow > 0 {
                Button { path.append(Route.neverOpened) } label: {
                    HStack(spacing: 6) {
                        Text("and \(stale.overflow) more")
                            .font(Typo.ui(13.5, .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(accent.deep)
                    .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 4 — A month ago today.
    private func monthAgo(_ items: [RevisitBork]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("A month ago today",
                           caption: "What you were saving four weeks back.")

            LazyVStack(spacing: 9) {
                ForEach(items) { item in
                    if let bookmark = index[item.id] {
                        Button { detail = bookmark } label: {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    /// 5 — Side quests in progress. The Library's card, unchanged.
    private func questsInProgress(_ items: [RevisitQuest]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Side quests in progress")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        if let quest = quests.first(where: { $0.id == item.id }) {
                            Button { openQuest = quest } label: {
                                QuestCard(
                                    title: quest.title,
                                    count: quest.bookmarkIDs.count,
                                    palette: quest.topic?.palette ?? NeutralPalette.value,
                                    motif: QuestMotif.resolve(title: quest.title, categoryID: quest.categoryID),
                                    layout: .rail,
                                    habit: quest.hasHabit,
                                    topicName: quest.topic?.name
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
        }
    }

    /// 6 — What's shifting.
    private func shifting(_ sentence: String, _ shifts: [Revisit.Shift]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("What's shifting",
                           caption: "The last 30 days against the 30 before.")

            VStack(alignment: .leading, spacing: 11) {
                Text(sentence)
                    .font(Typo.display(19, .bold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 7) {
                    ForEach(shifts) { shift in
                        HStack(spacing: 8) {
                            Image(systemName: shift.isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(shift.isUp ? accent.deep : Tokens.inkMeta)
                            Text(shift.name)
                                .font(Typo.ui(13, .semibold))
                                .foregroundStyle(Tokens.ink)
                            Spacer(minLength: 6)
                            Text("\(percent(shift.previousShare)) → \(percent(shift.share))")
                                .font(Typo.ui(12, .medium))
                                .foregroundStyle(Tokens.inkMeta)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: 18)
            .padding(.horizontal, 18)
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

/// Shared section chrome, so six sections can't drift into six styles.
private struct SectionHeading: View {
    let title: String
    var caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typo.display(18, .bold))
                .foregroundStyle(Tokens.ink)
            if let caption {
                Text(caption)
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
    }
}

/// Under ten borks there is nothing honest to say, so the screen says what it
/// will say instead of showing six empty headings. Naming the actual sections
/// is the point: it tells someone what saving ten things buys them.
private struct ThinRevisitCard: View {
    let count: Int
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent.deep)
                .padding(.bottom, 2)

            Text("Save ten things and this fills in")
                .font(Typo.display(20, .bold))
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("What you keep coming back to, what you saved and never opened, what a month ago looked like.")
                .font(Typo.ui(13.5))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(count == 0 ? "Nothing saved yet." : "\(Copy.countedBorks(count)) so far.")
                .font(Typo.ui(12.5, .semibold))
                .foregroundStyle(Tokens.inkMeta)
                .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.base.opacity(0.22), lineWidth: 1)
        )
    }
}

/// "and N more" — the whole never-opened pile, newest first.
private struct NeverOpenedList: View {
    let items: [Bookmark]

    @Environment(\.accent) private var accent
    @State private var detail: Bookmark?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                ForEach(items) { bookmark in
                    Button { detail = bookmark } label: {
                        BookmarkRow(bookmark: bookmark)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Tokens.paper)
        .navigationTitle("Saved, never opened")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
    }
}
