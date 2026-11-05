import SwiftUI

/// bookmarker Pro, before there is a Pro to buy.
///
/// The owner wants to know whether people would pay before building any of
/// it, so nothing here sells anything: no StoreKit, no products, no checkout,
/// and nothing anywhere in the app is limited by it. Each plan is a link. A
/// tap opens bookmarker.lol in Safari, the website counts it, and the
/// footnote says exactly that, so nobody thinks they have just bought
/// something.
///
/// The app sends nothing itself. Its listing promises "No ads. No tracking.
/// No analytics.", so the counting is the website's. And Safari rather than
/// an in-app browser, because the age-rating answers rely on there being
/// none.
///
/// Two doors, told apart by `from` in the link: the Library at 100, 250 and
/// 500 borks (`ProNudge`), and the You tab's row.
struct ProSheet: View {
    let origin: Origin

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Measured, not guessed: the sheet is as tall as what it says at every
    /// text size, so there is no slack under "Not now", and past the height
    /// of the screen it scrolls. The starting value is the default size's.
    @State private var height: CGFloat = 456

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                VStack(spacing: 10) {
                    ForEach(Plan.allCases) { plan in
                        planButton(plan)
                    }
                }

                Text("Pro isn't on sale yet. Picking a plan opens bookmarker.lol to hold that price — nothing is charged.")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkMeta)
                    .fixedSize(horizontal: false, vertical: true)

                Button { dismiss() } label: {
                    Text("Not now")
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Tokens.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Tokens.paper)
        .presentationDetents([.height(height)])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("bookmarker Pro")
                    .font(Typo.display(26, .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Unlimited borks, for when your library outgrows 100.")
                    .font(Typo.ui(14))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The welcome tour's clay: saves pouring into a phone and piling
            // up beside it. Left out at accessibility sizes, where the words
            // need the width.
            if !typeSize.isAccessibilitySize {
                ClayArt(name: "welcomeHero")
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
    }

    /// Opens the plan's page in Safari and closes the sheet.
    private func planButton(_ plan: Plan) -> some View {
        Button {
            openURL(plan.link(from: origin))
            dismiss()
        } label: {
            ProPlanCard(plan: plan, stacked: typeSize.isAccessibilitySize)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(plan.spoken)
        .accessibilityHint("Opens bookmarker.lol in Safari")
    }
}

extension ProSheet {
    /// Which door the sheet was opened from. The website counts it beside
    /// the plan; `web-you` and `web-milestone` are its own.
    enum Origin: String {
        case milestone = "app-milestone"
        case you = "app-you"
    }

    /// The owner's three prices, written here because there is no product
    /// for StoreKit to price. bookmarker.lol/pro quotes the same three.
    enum Plan: String, CaseIterable, Identifiable {
        case monthly, yearly, lifetime

        var id: String { rawValue }

        var name: String {
            switch self {
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            case .lifetime: "Lifetime"
            }
        }

        var price: String {
            switch self {
            case .monthly: "$9.99"
            case .yearly: "$99.99"
            case .lifetime: "$199.99"
            }
        }

        var period: String {
            switch self {
            case .monthly: "a month"
            case .yearly: "a year"
            case .lifetime: "once"
            }
        }

        /// A year for the price of ten months of Monthly. Only Yearly has a
        /// deal, and the plan with one wears the tinted card.
        var deal: String? {
            self == .yearly ? "Two months free" : nil
        }

        /// `https://bookmarker.lol/pro?plan=yearly&from=app-you`
        func link(from origin: Origin) -> URL {
            URL(string: "https://bookmarker.lol/pro?plan=\(rawValue)&from=\(origin.rawValue)")!
        }

        /// "Yearly, $99.99 a year, two months free"
        var spoken: String {
            [name, "\(price) \(period)", deal?.lowercased()]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
    }
}

/// One plan: its name on the left, the price on the right, and an arrow that
/// says the tap leaves the app. Yearly wears the Insights entry's tinted
/// card with its deal in the accent, so it reads as the one to pick without
/// anything being pre-selected.
private struct ProPlanCard: View {
    let plan: ProSheet.Plan
    /// At accessibility sizes the price goes under the name, not beside it.
    let stacked: Bool

    @Environment(\.accent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let card = HStack(spacing: 12) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 6) {
                        name
                        price(alignment: .leading)
                    }
                } else {
                    HStack(spacing: 8) {
                        name
                        Spacer(minLength: 8)
                        price(alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tokens.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(shape)

        if plan.deal != nil {
            card
                .background(
                    LinearGradient(colors: [accent.tint, accent.tint.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: shape
                )
                .overlay(shape.stroke(accent.base.opacity(0.28), lineWidth: 1))
                .shadow(color: accent.base.opacity(0.12), radius: 16, y: 8)
        } else {
            card.cardSurface(radius: 18)
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(plan.name)
                .font(Typo.ui(15, .bold))
                .foregroundStyle(Tokens.ink)
            if let deal = plan.deal {
                Text(deal)
                    .font(Typo.ui(12.5, .semibold))
                    .foregroundStyle(accent.deep)
            }
        }
    }

    private func price(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(plan.price)
                .font(Typo.display(19, .heavy))
                .foregroundStyle(Tokens.ink)
            Text(plan.period)
                .font(Typo.ui(12, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
    }
}

// MARK: - When it comes up by itself

/// The Pro sheet's milestones: once each as the live library first reaches
/// 100, 250 and 500 borks. Live is the count `SaveLimit` and the Library's
/// stats line use, so waiting borks are left out.
///
/// The sign-in sheet's rules, on the same bookkeeping (`MilestoneLedger`)
/// under keys of its own:
///
/// - **Never on launch.** Only a crossing this install saw counts. A library
///   already past 100 when this build first looks never gets the 100 sheet,
///   and an import that crosses two shows one, for the higher.
/// - **Never on top of anything,** the Add sheet included, and never while
///   the sign-in sheet is due or up: that one is about not losing the
///   library, so it goes first. A milestone that can't be shown stays due
///   for the next time the Library is clear. `LibraryView.readNudgePolicy`
///   keeps both rules.
///
/// **Signed in only.** Signed out, the app's own line is that a free account
/// makes the library unlimited, and a paid plan selling the same word would
/// contradict it. What a library crosses signed out is passed over, not
/// saved up (the watermark keeps moving), so creating an account never sets
/// a sheet off. Signing in to a bigger library can, once: that library has
/// outgrown 100.
@MainActor
enum ProNudge {
    static let milestones = [100, 250, 500]

    private static let ledger = MilestoneLedger(prefix: "proNudge")

    /// Pure, like `SignInNudge.dueMilestone`: it decides, the caller records.
    static func dueMilestone(borks: Int, signedIn: Bool) -> Int? {
        signedIn ? ledger.due(milestones, borks: borks) : nil
    }

    static func recordSeen(_ borks: Int) {
        ledger.recordSeen(borks)
    }

    /// The sheet went up, so that milestone is spent for good.
    static func recordSheetShown(_ milestone: Int) {
        ledger.recordShown(milestone)
    }
}
