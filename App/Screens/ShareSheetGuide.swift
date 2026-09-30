import SwiftUI

/// "Not seeing bookmarker in your share sheet?" — the walkthrough behind the
/// You tab's *Save from other apps* row and the onboarding share step.
///
/// The share sheet is the app's primary acquisition path and most people never
/// discover it on their own. The first version of this sheet said "tap More,
/// then switch bookmarker on", which is where iOS 13 left things. Since then
/// the row of app icons is Siri's suggestions plus the person's own Favorites,
/// and nothing an app does can put itself in it — the person can, with More →
/// Edit → add to Favorites → drag to the front. So that is what the four steps
/// say, in those words, and the mock sheet above them shows the end state —
/// bookmarker first — rather than an icon row that never looked like anyone's
/// phone.
///
/// X gets its own line because it has two share sheets: its own row (Copy
/// link, Share via…, Messages, WhatsApp), which no third-party app can join,
/// and the system sheet behind *Share via…*, where bookmarker lives. Being in
/// the first row was the first thing our first outside user asked for; the
/// honest answer is the second sheet, pinned.
///
/// If the last share from another app failed, one line says so — the
/// breadcrumb the extension leaves (`ShareOutcome`) — so "it didn't work" can
/// be diagnosed without a screenshot of a sheet that has already closed.
struct ShareSheetGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var lastFailure: ShareOutcome.Record?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ShareSheetMock(accent: accent)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Put bookmarker first")
                            .font(Typo.display(24, .heavy))
                            .tracking(-0.5)
                            .foregroundStyle(Tokens.ink)
                        Text("Add bookmarker to your iOS Favorites so it's easier to reach. Each app controls the menu before this sheet.")
                            .font(Typo.ui(14))
                            .foregroundStyle(Tokens.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Tap Share",
                             "In Instagram, TikTok or YouTube that's the share arrow. On X, tap Share, then **Share via…** — X's own row can't show other apps.")
                        step(2, "Scroll the app icons and tap More",
                             "It's the last tile in the row of apps.")
                        step(3, "Tap Edit, then add bookmarker",
                             "Tap the green **+** next to **bookmarker** to put it in your Favorites.")
                        step(4, "Drag it to the front",
                             "Hold the handle beside it and move it near the front. Instagram or X may still require Share to… or Share via… before the iOS sheet appears.")
                    }

                    Text("bookmarker shows up when you share a post or a link — not a photo or a screenshot.")
                        .font(Typo.ui(12.5))
                        .foregroundStyle(Tokens.inkMeta)
                        .fixedSize(horizontal: false, vertical: true)

                    if let lastFailure {
                        lastShareLine(lastFailure)
                    }

                    Button { dismiss() } label: {
                        Text("Got it")
                            .font(Typo.ui(15, .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle("Save from other apps")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .onAppear(perform: readLastShare)
    }

    /// The breadcrumb, if the last run of the extension is worth mentioning.
    private func readLastShare() {
        let last = ShareOutcome.last(in: UserDefaults(suiteName: Store.appGroupID))
        lastFailure = last.flatMap { $0.outcome.isFailure ? $0 : nil }
    }

    private func lastShareLine(_ record: ShareOutcome.Record) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent.base)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your last share from another app didn't save")
                    .font(Typo.ui(13, .bold))
                    .foregroundStyle(Tokens.ink)
                Text("\(record.outcome.explanation) · \(record.at, style: .relative) ago. Copy the link and paste it in with +.")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func step(_ number: Int, _ title: String, _ detail: LocalizedStringKey) -> some View {
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

/// The system share sheet as it looks once bookmarker is pinned: the post
/// being shared, then the row of app icons with bookmarker first and More at
/// the end. Same card, tiles and labels as the You tab's other cards, so it
/// reads as the app explaining the phone rather than a screenshot of one.
struct ShareSheetMock: View {
    let accent: AccentRamp

    var body: some View {
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

            HStack(alignment: .top, spacing: 16) {
                tile(label: "bookmarker", pinned: true) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                }
                tile(label: nil, pinned: false) { EmptyView() }
                tile(label: nil, pinned: false) { EmptyView() }
                tile(label: "More", pinned: false) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tokens.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
        }
        .cardSurface(radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The share sheet, with bookmarker as the first app icon and More at the end")
    }

    private func tile<Glyph: View>(label: String?, pinned: Bool, @ViewBuilder glyph: () -> Glyph) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(pinned ? accent.base : Tokens.mutedControl)
                .frame(width: 46, height: 46)
                .overlay(glyph())
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(accent.base, lineWidth: pinned ? 2.5 : 0)
                        .padding(-4)
                )
            if let label {
                Text(label)
                    .font(Typo.ui(9.5, .semibold))
                    .foregroundStyle(pinned ? accent.deep : Tokens.inkMeta)
            } else {
                Capsule()
                    .fill(Tokens.mutedControl)
                    .frame(width: 30, height: 6)
                    .padding(.top, 3)
            }
        }
    }
}

/// The way into the guide from onboarding, which has nowhere of its own to
/// keep a sheet flag for one step.
struct ShareGuideLink: View {
    let accent: AccentRamp
    @State private var showingGuide = false

    var body: some View {
        Button { showingGuide = true } label: {
            HStack(spacing: 5) {
                Text("Not seeing bookmarker in your share sheet?")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(Typo.ui(13.5, .semibold))
            .foregroundStyle(accent.deep)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingGuide) {
            ShareSheetGuide().environment(\.accent, accent)
        }
    }
}
