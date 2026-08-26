import SwiftUI
import SwiftData

struct YouView: View {
    let onReplayTour: () -> Void
    @ObservedObject var account: Account

    @Environment(\.accent) private var accent
    @AppStorage("accentKey") private var accentKey = AccentRamp.fallback.key
    @AppStorage("feedDensity") private var density = "cards"
    @AppStorage("startingTab") private var startingTab = AppTab.library.rawValue

    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil })
    private var bookmarks: [Bookmark]
    @Query(filter: #Predicate<BookmarkCollection> { $0.deletedAt == nil })
    private var collections: [BookmarkCollection]

    @State private var showingHowTo = false
    @State private var showingImport = false
    @State private var showingAuth = false
    @State private var showingInsights = false
    @State private var creatingQuestTitle: String?

    private var thisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return bookmarks.filter { $0.savedAt >= cutoff }.count
    }

    private var topicCount: Int {
        Set(bookmarks.compactMap(\.categoryID)).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                insights
                intake
                if !collections.isEmpty { collectionsBlock }
                appearance
                help
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Tokens.paper)
        .sheet(isPresented: $showingHowTo) {
            HowToSheet().environment(\.accent, accent)
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet { _ in }.environment(\.accent, accent)
        }
        .sheet(isPresented: $showingAuth) {
            AuthSheet(account: account).environment(\.accent, accent)
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

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You")
                        .font(Typo.display(34, .heavy))
                        .tracking(-1.0)
                        .foregroundStyle(Tokens.ink)
                    accountStatus
                }
                Spacer(minLength: 8)
                avatar
            }

            statsStrip

            if !account.isSignedIn {
                Button { showingAuth = true } label: {
                    Text("Sign in")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Back up and sync your borks")
            }
        }
    }

    @ViewBuilder
    private var accountStatus: some View {
        if account.isSignedIn {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? "Signed in")
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                    Text(account.isSyncing ? "Syncing…"
                         : account.lastSynced.map { "Backed up \(RelativeDate.label(for: $0).lowercased())" }
                            ?? "Waiting to back up")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer(minLength: 8)
                Button("Sign out") { account.signOut() }
                    .font(Typo.ui(13, .semibold))
                    .foregroundStyle(Tokens.destructive)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Only on this phone")
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
                Text("Sign in to back up and sync your borks")
                    .font(Typo.ui(12, .medium))
                    .foregroundStyle(Tokens.inkMeta)
            }
        }
    }

    private var avatar: some View {
        Circle()
            .fill(accent.tint)
            .frame(width: 64, height: 64)
            .overlay { avatarGlyph }
            .overlay {
                Circle().stroke(accent.base.opacity(0.22), lineWidth: 1)
            }
            .glow(accent.base, radius: 36, opacity: 0.18)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatarGlyph: some View {
        if let letter = avatarLetter {
            Text(letter)
                .font(Typo.display(24, .heavy))
                .foregroundStyle(accent.deep)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accent.deep)
        }
    }

    /// First letter of the signed-in email. Never a hardcoded "J".
    private var avatarLetter: String? {
        guard let email = account.email,
              let local = email.split(separator: "@").first,
              let first = local.first
        else { return nil }
        return String(first).uppercased()
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(bookmarks.count)", label: Copy.borks(bookmarks.count), accented: false)
            Rectangle().fill(Tokens.divider).frame(width: 1, height: 36)
            statColumn(value: "\(topicCount)", label: topicCount == 1 ? "topic" : "topics", accented: false)
            Rectangle().fill(Tokens.divider).frame(width: 1, height: 36)
            statColumn(value: "\(thisWeek)", label: "this week", accented: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Copy.countedBorks(bookmarks.count)), \(topicCount) \(topicCount == 1 ? "topic" : "topics"), \(thisWeek) this week")
    }

    private func statColumn(value: String, label: String, accented: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Typo.display(22, .heavy))
                .foregroundStyle(accented ? accent.base : Tokens.ink)
            Text(label)
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Insights

    private var insights: some View {
        Button { showingInsights = true } label: {
            InsightsEntry(bookmarks: bookmarks)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Intake

    private var intake: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Bring things in")
            VStack(spacing: 0) {
                YouRow(
                    symbol: "square.and.arrow.down",
                    well: Tokens.ink,
                    glyph: .white,
                    title: "Import what you've already saved",
                    subtitle: "X, Instagram, TikTok, YouTube, browser bookmarks"
                ) { showingImport = true }

                insetDivider

                YouRow(
                    symbol: "square.and.arrow.up",
                    well: accent.base,
                    glyph: .white,
                    title: "Save from other apps",
                    subtitle: "The fastest way to add anything"
                ) { showingHowTo = true }
            }
            .cardSurface(radius: Tokens.cardRadius)
        }
    }

    private var insetDivider: some View {
        Tokens.divider
            .frame(height: 1)
            .padding(.leading, 58)
    }

    // MARK: Collections

    private var collectionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Collections")
            VStack(spacing: 0) {
                ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                    if index > 0 { insetDivider }
                    HStack(spacing: 12) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(collection.category?.palette.deep ?? Tokens.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                collection.category?.palette.tint ?? Tokens.mutedControl,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.name)
                                .font(Typo.ui(14, .semibold))
                                .foregroundStyle(Tokens.ink)
                            Text(Copy.countedBorks(collection.count))
                                .font(Typo.ui(11.5, .medium))
                                .foregroundStyle(Tokens.inkMeta)
                        }
                        Spacer()
                        Pill(text: collection.visibility.label, symbol: collection.visibility.symbol)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                }
            }
            .cardSurface(radius: Tokens.cardRadius)
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            YouSectionLabel("Look")
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colour")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.ink)
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
                                        .font(Typo.ui(10, .medium))
                                        .foregroundStyle(accentKey == ramp.key ? Tokens.ink : Tokens.inkMeta)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ramp.name)
                            .accessibilityAddTraits(accentKey == ramp.key ? [.isSelected] : [])
                        }
                        Spacer()
                    }
                }

                Tokens.divider.frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Feed")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.ink)
                    YouChoiceTrack(
                        options: [("cards", "Cards"), ("compact", "Compact")],
                        selection: $density
                    )
                }

                Tokens.divider.frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Open on")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.ink)
                    YouChoiceTrack(
                        options: AppTab.allCases.map { ($0.rawValue, $0.title) },
                        selection: $startingTab
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Tokens.cardRadius)
        }
    }

    // MARK: Help

    private var help: some View {
        Button(action: onReplayTour) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                Text("Replay welcome tour")
                    .font(Typo.ui(13.5, .semibold))
                Spacer()
            }
            .foregroundStyle(Tokens.inkSecondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("See the intro again")
    }
}

private struct YouSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(Typo.ui(13, .semibold))
            .foregroundStyle(Tokens.inkMeta)
            .padding(.leading, 4)
    }
}

private struct YouRow: View {
    let symbol: String
    let well: Color
    let glyph: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(glyph)
                    .frame(width: 32, height: 32)
                    .background(well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.ink)
                    Text(subtitle)
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct YouChoiceTrack: View {
    let options: [(id: String, title: String)]
    @Binding var selection: String

    init(options: [(String, String)], selection: Binding<String>) {
        self.options = options.map { (id: $0.0, title: $0.1) }
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.id) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option.id }
                    Haptics.select()
                } label: {
                    Text(option.title)
                        .font(Typo.ui(12.5, .semibold))
                        .foregroundStyle(selection == option.id ? Tokens.ink : Tokens.inkMeta)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                        .background(selection == option.id ? Tokens.surface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.id ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Tokens.segmentTrack, in: Capsule())
    }
}

/// Explains the share sheet, which most people never discover on their own —
/// and it's the app's primary acquisition path.
struct HowToSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mockShareSheet

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Find something worth keeping", "A reel, a thread, a video, an article — anything.")
                        step(2, "Tap Share", "Then scroll the app row and pick borkmarkr.")
                        step(3, "First time only", "Tap More, then switch borkmarkr on.")
                    }

                    Button { dismiss() } label: {
                        Text("Got it")
                            .font(Typo.ui(15, .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle("Save from other apps")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    private var mockShareSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: Platform.instagram.badgeColors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instagram")
                        .font(Typo.ui(13, .semibold))
                        .foregroundStyle(Tokens.ink)
                    Text("Reel · @physio.jane")
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer()
            }
            .padding(13)

            Divider()

            HStack(spacing: 16) {
                ForEach(0..<3) { index in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(index == 1 ? accent.base : Tokens.mutedControl)
                            .frame(width: 46, height: 46)
                            .overlay(
                                Group {
                                    if index == 1 {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 17, weight: .black))
                                            .foregroundStyle(.white)
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(accent.base, lineWidth: index == 1 ? 2.5 : 0)
                                    .padding(-4)
                            )
                        Text(index == 1 ? "borkmarkr" : " ")
                            .font(Typo.ui(9.5, .semibold))
                            .foregroundStyle(index == 1 ? accent.deep : .clear)
                    }
                }
                Spacer()
            }
            .padding(15)
        }
        .cardSurface(radius: 20)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Typo.ui(12, .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Tokens.ink, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typo.ui(14, .bold))
                    .foregroundStyle(Tokens.ink)
                Text(detail)
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
