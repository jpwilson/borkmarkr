import SwiftUI
import SwiftData

struct YouView: View {
    let onReplayTour: () -> Void
    @ObservedObject var account: Account

    @Environment(\.accent) private var accent
    @Environment(\.openURL) private var openURL
    @AppStorage("accentKey") private var accentKey = AccentRamp.fallback.key
    @AppStorage("feedDensity") private var density = "cards"
    @AppStorage("startingTab") private var startingTab = AppTab.library.rawValue
    /// Quick File on the share sheet. In the App Group's defaults, because
    /// the Share Extension is the one that reads it.
    @AppStorage(QuickFileSettings.askAfterShareKey, store: QuickFileSettings.store)
    private var askAfterShare = true

    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil })
    private var bookmarks: [Bookmark]

    @State private var showingHowTo = false
    @State private var showingImport = false
    @State private var showingAuth = false
    @State private var authMode: AuthSheet.Mode = .signUp
    @State private var showingInsights = false
    @State private var showingPro = false
    @State private var creatingQuestTitle: String?
    @State private var confirmingDelete = false
    @State private var deletingAccount = false
    @State private var deleteError: String?

    private var thisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return live.filter { $0.savedAt >= cutoff }.count
    }

    private var topicCount: Int {
        Set(live.compactMap(\.categoryID)).count
    }

    /// Borks that count. A waiting one is saved and visible in the Library,
    /// but it is not part of the library's totals until it is admitted —
    /// see `SaveLimit`.
    private var live: [Bookmark] { bookmarks.filter { !$0.isWaiting } }
    private var liveCount: Int { live.count }
    private var waitingCount: Int { bookmarks.count { $0.isWaiting } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.sectionGap) {
                hero
                insights
                pro
                intake
                collectionsBlock
                appearance
                spreadTheWord
                help
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Tokens.paper)
        .onAppear(perform: openLaunchSheets)
        .sheet(isPresented: $showingHowTo) {
            HowToSheet().environment(\.accent, accent)
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet { _ in }.environment(\.accent, accent)
        }
        .sheet(isPresented: $showingAuth) {
            AuthSheet(account: account, mode: authMode).environment(\.accent, accent)
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and every bork backed up to it. The borks on this phone stay here. It can't be undone.")
        }
        .alert("Couldn't delete your account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(isPresented: $showingInsights) {
            InsightsSheet(bookmarks: live, account: account) { title in
                creatingQuestTitle = title
            }
            .environment(\.accent, accent)
        }
        .sheet(isPresented: $showingPro) {
            ProSheet(origin: .you).environment(\.accent, accent)
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

    // MARK: Hero

    /// Title and avatar, then one white card: the three counts, and under a
    /// hairline what the account is doing (or, signed out, what one buys).
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("You", subtitle: account.isSignedIn ? (account.email ?? "Signed in") : "Not signed in") {
                avatar
            }

            VStack(alignment: .leading, spacing: 0) {
                statsStrip
                    .padding(.vertical, 14)
                Tokens.hairline.frame(height: 1)
                accountStatus
                    .padding(16)
            }
            .cardSurface()
        }
    }

    @ViewBuilder
    private var accountStatus: some View {
        if account.isSignedIn {
            HStack(alignment: .center, spacing: 10) {
                    // A backup that fails silently looks like a backup that
                    // never runs. Say what went wrong — as a person would
                    // (`PlainError`, applied in Account); the raw text is in
                    // the DEBUG log.
                    Text(account.isSyncing ? "Syncing…"
                         : account.lastError
                         ?? account.lastSynced.map { "Backed up \(RelativeDate.label(for: $0).lowercased())" }
                         ?? "Waiting to back up")
                        .textRole(.meta, color: account.isSyncing || account.lastError == nil
                                  ? Tokens.inkSecondary : Tokens.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Sign out") { account.signOut() }
                        .buttonStyle(.clayQuiet)
            }
            .padding(.vertical, -8)
        } else {
            // Said plainly, because "Only on this phone" alone was read as a
            // setting rather than as the account state. The two words people
            // need are "Not signed in".
            VStack(alignment: .leading, spacing: 4) {
                Text("Your borks live only on this phone")
                    .textRole(.cardTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sign up and they're backed up, and on the web at bookmarker.lol.")
                    .textRole(.meta)
                    .fixedSize(horizontal: false, vertical: true)
                freeLimit

                HStack(spacing: 10) {
                    Button("Sign up") { authMode = .signUp; showingAuth = true }
                        .buttonStyle(PrimaryButtonStyle(height: 48))
                    Button("Sign in") { authMode = .signIn; showingAuth = true }
                        .buttonStyle(SecondaryButtonStyle(height: 48))
                }
                .padding(.top, 12)
            }
        }
    }

    /// The limit, said plainly, where someone goes when they want to know
    /// what their account status actually means.
    ///
    /// The count is the point. "Without an account: 20 borks" is a rule; "17 of 20" is
    /// a fact about your library, and it is the number that decides whether
    /// this line is worth reading today.
    @ViewBuilder
    private var freeLimit: some View {
        if let counter = SaveLimit.youCount(liveCount: liveCount, signedIn: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text(counter)
                    .textRole(.cardTitle, color: waitingCount > 0 ? Tokens.destructive
                              : liveCount >= SaveLimit.limit ? accent.deep : Tokens.ink)
                    .monospacedDigit()
                Text(SaveLimit.youLine)
                    .textRole(.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 10)

            if let waitingLine = SaveLimit.waitingBanner(count: waitingCount) {
                Text(waitingLine)
                    .textRole(.meta, color: Tokens.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            try await account.deleteAccount()
            Haptics.success()
        } catch {
            #if DEBUG
            print("Delete account failed:", error)
            #endif
            deleteError = PlainError.message(error, doing: "delete your account")
        }
    }

    /// `-importSheet` and `-shareGuide` (DEBUG captures).
    private func openLaunchSheets() {
        #if DEBUG
        if ScreenshotDefaults.openImport { showingImport = true }
        if ScreenshotDefaults.openShareGuide { showingHowTo = true }
        #endif
    }

    /// The Library's avatar, a size up: sand, the initial in sand-ink.
    private var avatar: some View {
        Circle()
            .fill(Tokens.sand)
            .frame(width: 56, height: 56)
            .overlay { avatarGlyph }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatarGlyph: some View {
        if let letter = avatarLetter {
            Text(letter)
                .font(.custom("Bricolage Grotesque", size: 22, relativeTo: .title3).weight(.bold))
                .foregroundStyle(Tokens.sandInk)
        } else {
            Image(systemName: "person")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.sandInk)
        }
    }

    /// The signed-in email's first letter, by the one rule both avatars share
    /// (`Initials`). Never a hardcoded "J".
    private var avatarLetter: String? {
        Initials.letter(displayName: nil, email: account.email)
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(liveCount)", label: Copy.borks(liveCount), accented: false)
            Tokens.hairline.frame(width: 1, height: 36)
            statColumn(value: "\(topicCount)", label: topicCount == 1 ? "topic" : "topics", accented: false)
            Tokens.hairline.frame(width: 1, height: 36)
            statColumn(value: "\(thisWeek)", label: "this week", accented: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Copy.countedBorks(liveCount)), \(topicCount) \(topicCount == 1 ? "topic" : "topics"), \(thisWeek) this week")
    }

    private func statColumn(value: String, label: String, accented: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("Bricolage Grotesque", size: 24, relativeTo: .title2).weight(.bold))
                .foregroundStyle(accented ? accent.deep : Tokens.ink)
                .monospacedDigit()
            Text(label).textRole(.meta)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Insights

    private var insights: some View {
        Button { showingInsights = true } label: {
            InsightsEntry(bookmarks: live)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Pro

    /// bookmarker Pro, which isn't on sale: the row opens the sheet the
    /// Library shows at 100 borks, and its plans open bookmarker.lol.
    ///
    /// Signed in only. Signed out, the top of this tab says an account alone
    /// makes the library unlimited, and a paid plan selling the same word
    /// underneath would contradict it.
    @ViewBuilder
    private var pro: some View {
        if account.isSignedIn {
            VStack(alignment: .leading, spacing: 8) {
                YouSectionLabel("Plan")
                YouRow(
                    symbol: "infinity",
                    title: "bookmarker Pro",
                    subtitle: "Unlimited borks, for when your library outgrows 100"
                ) { showingPro = true }
                .cardSurface(radius: Tokens.cardRadius)
            }
        }
    }

    // MARK: Intake

    private var intake: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Bring things in")
            VStack(spacing: 0) {
                YouRow(
                    symbol: "square.and.arrow.down",
                    title: "Import what you've already saved",
                    subtitle: "X, Instagram, TikTok, YouTube, browser bookmarks"
                ) { showingImport = true }

                insetDivider

                YouRow(
                    symbol: "square.and.arrow.up",
                    title: "Save from other apps",
                    subtitle: "The fastest way to add anything"
                ) { showingHowTo = true }

                insetDivider

                askAfterShareRow
            }
            .cardSurface(radius: Tokens.cardRadius)
        }
    }

    /// On: the share sheet saves, then shows the dial, and one more tap
    /// files it. Off: the old one-tap share that saves and leaves.
    private var askAfterShareRow: some View {
        Toggle(isOn: $askAfterShare.animation(.easeOut(duration: 0.18))) {
            HStack(spacing: 12) {
                YouRowWell(symbol: "dial.medium")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask where it goes after sharing")
                        .textRole(.cardTitle, color: Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(askAfterShare
                         ? "Saved first, then one tap to file it"
                         : "Sharing saves and closes; sort later")
                        .textRole(.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(accent.base)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: Tokens.slimRowHeight)
        .onChange(of: askAfterShare) { _, _ in Haptics.select() }
    }

    private var insetDivider: some View {
        Tokens.hairline
            .frame(height: 1)
            .padding(.leading, 64)
    }

    // MARK: Collections

    /// The links you've shared. A collection is a server row, so the list
    /// behind this row reads the server; nothing about it lives on the phone.
    private var collectionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Sharing")
            CollectionsEntry(account: account)
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Look")
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colour")
                        .textRole(.cardTitle, color: Tokens.ink)
                    HStack(spacing: 14) {
                        ForEach(AccentRamp.all, id: \.key) { ramp in
                            Button {
                                withAnimation(Motion.snap) { accentKey = ramp.key }
                                Haptics.select()
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(ramp.base)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(ramp.base, lineWidth: accentKey == ramp.key ? 2.5 : 0)
                                                .padding(-4)
                                        )
                                    Text(ramp.name)
                                        .font(.custom("Instrument Sans", size: 11, relativeTo: .caption2).weight(.medium))
                                        .foregroundStyle(accentKey == ramp.key ? Tokens.ink : Tokens.inkSecondary)
                                }
                                .frame(minWidth: Tokens.minTapTarget, minHeight: Tokens.minTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ramp.name)
                            .accessibilityAddTraits(accentKey == ramp.key ? [.isSelected] : [])
                        }
                        Spacer()
                    }
                }

                Tokens.hairline.frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Feed")
                        .textRole(.cardTitle, color: Tokens.ink)
                    ClaySegmented(
                        selection: $density,
                        options: [("cards", "Cards"), ("compact", "Compact")]
                    )
                }

                Tokens.hairline.frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Open on")
                        .textRole(.cardTitle, color: Tokens.ink)
                    ClaySegmented(
                        selection: $startingTab,
                        options: AppTab.allCases.map { ($0.rawValue, $0.title) }
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: Spread the word

    /// 1.0 shipped with no way to rate the app or pass it on. The system rating
    /// prompt fires three times a year at most and only at moments we choose —
    /// this is the door that's always open, for the person who already likes it.
    private var spreadTheWord: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Spread the word")
            VStack(spacing: 0) {
                YouRow(
                    symbol: "star",
                    title: "Rate bookmarker",
                    subtitle: "Thirty seconds, and it's how anyone else finds it"
                ) { openURL(AppStoreListing.writeReview) }

                insetDivider

                // A ShareLink rather than a Button: the row hands the link to
                // the system share sheet, so it lands wherever the person
                // already talks to their friends.
                ShareLink(
                    item: AppStoreListing.url,
                    subject: Text("bookmarker"),
                    message: Text("Every link I save, from every app, in one library I can actually search.")
                ) {
                    YouRowFace(
                        symbol: "paperplane",
                        title: "Share bookmarker",
                        subtitle: "Send someone the App Store link"
                    )
                }
                .buttonStyle(PressableStyle())
            }
            .cardSurface(radius: Tokens.cardRadius)
        }
    }

    // MARK: Help

    /// The tour, and — signed in — account deletion, at the foot of the tab.
    /// Deletion is a store requirement (App Review 5.1.1(v)) and the right
    /// thing anyway: what you can create, you can remove.
    private var help: some View {
        HStack(spacing: 16) {
            Button(action: onReplayTour) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Replay welcome tour")
                }
            }
            .buttonStyle(.clayQuiet)
            .accessibilityHint("See the intro again")

            Spacer(minLength: 0)

            if account.isSignedIn {
                Button(deletingAccount ? "Deleting…" : "Delete account") {
                    confirmingDelete = true
                }
                .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                .foregroundStyle(Tokens.destructive)
                .frame(minHeight: Tokens.minTapTarget)
                .contentShape(Rectangle())
                .disabled(deletingAccount)
            }
        }
        .padding(.top, -12)
    }
}

/// A group's small-caps label, over its white card.
private struct YouSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .textRole(.label, color: Tokens.inkSecondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct YouRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            YouRowFace(symbol: symbol, title: title, subtitle: subtitle)
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }
}

/// The 32 pt sand well every You row starts with: one quiet colour, so the
/// rows read as a list rather than a row of app icons.
struct YouRowWell: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Tokens.sandInk)
            .frame(width: 32, height: 32)
            .background(Tokens.sand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The row without the tap: a sand well, title 15/600 over a meta line, a
/// chevron. Split out so a `ShareLink` — which brings its own button — can be
/// dressed as one of these rows instead of a near-copy. `CollectionsEntry`
/// wears it too.
struct YouRowFace: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            YouRowWell(symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .textRole(.cardTitle, color: Tokens.ink)
                Text(subtitle)
                    .textRole(.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: Tokens.slimRowHeight)
        .contentShape(Rectangle())
    }
}

/// The live listing: Apple ID 6799805479, on sale since 2 Sep 2026.
/// `action=write-review` opens it with the rating sheet already up, which is the
/// difference between a tap and a scavenger hunt.
private enum AppStoreListing {
    static let url = URL(string: "https://apps.apple.com/app/id6799805479")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6799805479?action=write-review")!
}

/// The share-sheet guide lives in ShareSheetGuide.swift. The You tab presents
/// it under the name it always had.
typealias HowToSheet = ShareSheetGuide
