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

    private var thisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return bookmarks.filter { $0.savedAt >= cutoff }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profile
                accountCard
                stats
                importHint
                shareHint
                if !collections.isEmpty { collectionsBlock }
                appearance
                help
            }
            .padding(18)
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
    }

    private var profile: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(accent.tint)
                .frame(width: 54, height: 54)
                .overlay(Text("J").font(Typo.display(22, .heavy)).foregroundStyle(accent.deep))
            VStack(alignment: .leading, spacing: 2) {
                Text("You")
                    .font(Typo.display(22, .heavy))
                    .foregroundStyle(Tokens.ink)
                Text("Everything you save, in one place")
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    /// Signed-out is the honest default state, and it says plainly what that
    /// means rather than hiding it behind a "Sign in" button with no context.
    @ViewBuilder
    private var accountCard: some View {
        if account.isSignedIn {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.base)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? "Signed in")
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                    Text(account.isSyncing ? "Syncing…"
                         : account.lastSynced.map { "Backed up \(RelativeDate.label(for: $0).lowercased())" }
                            ?? "Waiting to back up")
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer()
                Button("Sign out") { account.signOut() }
                    .font(Typo.ui(12.5, .semibold))
                    .foregroundStyle(Tokens.destructive)
            }
            .padding(14)
            .cardSurface(radius: 18)
        } else {
            Button { showingAuth = true } label: {
                HStack(spacing: 11) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(width: 34, height: 34)
                        .background(Tokens.mutedControl, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only on this phone")
                            .font(Typo.ui(14, .bold))
                            .foregroundStyle(Tokens.ink)
                        Text("Sign in to back up and sync your borks")
                            .font(Typo.ui(12, .medium))
                            .foregroundStyle(Tokens.inkMeta)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Tokens.inkFaint)
                }
                .padding(14)
                .cardSurface(radius: 18)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            statTile("\(bookmarks.count)", "borks")
            statTile("\(Set(bookmarks.compactMap(\.categoryID)).count)", "topics")
            statTile("\(thisWeek)", "this week")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Typo.display(24, .heavy))
                .foregroundStyle(accent.base)
            Text(label)
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardSurface(radius: 18)
    }

    /// The cold-start fix, given prominence: most people arrive with thousands
    /// of saves already sitting in other apps.
    private var importHint: some View {
        Button { showingImport = true } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import what you've already saved")
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(Tokens.ink)
                    Text("X, Instagram, TikTok, YouTube, browser bookmarks")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.inkFaint)
            }
            .padding(14)
            .cardSurface(radius: 18)
        }
        .buttonStyle(PressableStyle())
    }

    private var shareHint: some View {
        Button { showingHowTo = true } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(accent.base, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save from other apps")
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(Tokens.ink)
                    Text("The fastest way to add anything")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.inkFaint)
            }
            .padding(14)
            .background(accent.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.base.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var collectionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collections")
                .font(Typo.ui(14.5, .bold))
                .foregroundStyle(Tokens.ink)
            ForEach(collections) { collection in
                HStack(spacing: 11) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(collection.category?.palette.deep ?? Tokens.inkSecondary)
                        .frame(width: 30, height: 30)
                        .background(collection.category?.palette.tint ?? Tokens.mutedControl,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                .padding(12)
                .cardSurface(radius: 16)
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(Typo.ui(14.5, .bold))
                .foregroundStyle(Tokens.ink)

            HStack(spacing: 12) {
                ForEach(AccentRamp.all, id: \.key) { ramp in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            accentKey = ramp.key
                        }
                    } label: {
                        Circle()
                            .fill(ramp.base)
                            .frame(width: 32, height: 32)
                            .scaleEffect(accentKey == ramp.key ? 1.08 : 1)
                            .overlay(
                                Circle()
                                    .stroke(ramp.base, lineWidth: accentKey == ramp.key ? 3 : 0)
                                    .padding(-5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ramp.name)
                    .accessibilityAddTraits(accentKey == ramp.key ? [.isSelected] : [])
                }
                Spacer()
            }

            Picker("Feed density", selection: $density) {
                Text("Cards").tag("cards")
                Text("Compact").tag("compact")
            }
            .pickerStyle(.segmented)

            Picker("Open on", selection: $startingTab) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Text(tab.title).tag(tab.rawValue)
                }
            }
            .font(Typo.ui(13.5, .medium))
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 18)
    }

    private var help: some View {
        Button(action: onReplayTour) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                Text("Replay welcome tour")
                    .font(Typo.ui(13.5, .semibold))
                Spacer()
            }
            .foregroundStyle(Tokens.inkSecondary)
            .padding(14)
            .cardSurface(radius: 16)
        }
        .buttonStyle(.plain)
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
