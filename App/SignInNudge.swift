import SwiftUI

/// When bookmarker says out loud that a library is only on this phone.
///
/// The app is local-first and a save is never gated behind an account — that
/// is the core product rule and it stays. It has one bad side effect: people
/// use bookmarker for weeks without ever learning that nothing is backed up.
/// Until now the only place that said so was the You tab, which is the one tab
/// a happy user never opens. So the fact has to come to them.
///
/// The message is "this only lives on this phone", never "you must sign in".
/// Nothing here withholds a feature and nothing here guilt-trips.
///
/// Two surfaces, deliberately different in weight:
///
/// - **A banner in the Library**, from the third bork on. It states where the
///   library lives rather than asking for anything, it never covers what you
///   are doing, and an ✕ puts it away. This is the honest, permanent version
///   of the message and it does most of the work.
/// - **A sheet at 5, 25 and 100 borks**, once each. A sheet interrupts, so it
///   is spent only where the stake is legible: the library is now big enough
///   that losing it would actually hurt.
///
/// Four rules keep it from becoming nagging:
///
/// - **Never on launch.** A milestone fires on a crossing this install can
///   *prove* — `recordSeen` is the count the app last looked at. A library
///   that was already past 25 the first time this policy saw it never gets a
///   sheet for 25. Opening the app is not an achievement, and a modal on
///   launch is exactly what we refuse to ship.
/// - **Never on top of something else.** The caller presents only with a clear
///   screen; a milestone it could not show stays due and arrives at the next
///   Library appearance.
/// - **Fourteen days of quiet after any dismissal**, and at most one sheet per
///   fourteen days however many milestones an import crosses at once. Two
///   weeks is long enough that a second ask reads as new information rather
///   than as pestering, and short enough to still catch someone before they
///   drop their phone in a river.
/// - **Gone the moment you sign in**, on every surface, permanently.
@MainActor
enum SignInNudge {

    /// Library size from which the banner and the You-tab dot appear. Below
    /// three borks there is little to lose and the app is still being tried.
    static let bannerFloor = 3

    /// The three sheet moments. Each is a point where the library stops being
    /// an experiment.
    static let milestones = [5, 25, 100]

    /// What any dismissal buys.
    static let quietPeriod: TimeInterval = 14 * 86_400

    private static let bannerDismissedKey = "signInNudgeBannerDismissedAt"
    private static let lastSheetKey = "signInNudgeLastSheetAt"
    private static let shownMilestonesKey = "signInNudgeShownMilestones"
    private static let seenCountKey = "signInNudgeSeenBorkCount"

    // MARK: - What to show

    static func showsBanner(signedIn: Bool, borks: Int) -> Bool {
        guard !signedIn, borks >= bannerFloor else { return false }
        return quietIsOver(bannerDismissedKey)
    }

    /// The dot on the You tab. A state marker rather than a prompt — it says
    /// "there is something about your account in here" — so no dismissal
    /// silences it. Signing in does.
    static func showsBadge(signedIn: Bool, borks: Int) -> Bool {
        !signedIn && borks >= bannerFloor
    }

    /// The milestone whose sheet is due right now, or `nil`.
    ///
    /// Deliberately pure: it decides, it does not record. The caller records
    /// with `recordSheetShown` when it actually presents, and with
    /// `recordSeen` once it knows nothing is due — which is what lets a
    /// milestone crossed behind another sheet stay due for the next Library
    /// appearance instead of being silently spent.
    static func dueMilestone(borks: Int) -> Int? {
        // No watermark yet means this policy has never looked at this library.
        // Whatever it has already passed is history, not an achievement.
        guard let watermark = seenCount, quietIsOver(lastSheetKey) else { return nil }
        let shown = shownMilestones
        return milestones.last { $0 <= borks && $0 > watermark && !shown.contains($0) }
    }

    // MARK: - Recording

    /// The library is this big and the app has noticed. Milestones fire on
    /// crossing this number, which is also why the very first call swallows
    /// everything a long-standing library has already passed.
    static func recordSeen(_ borks: Int) {
        UserDefaults.standard.set(borks, forKey: seenCountKey)
    }

    /// A milestone sheet went up. Spends that milestone for good and starts
    /// the quiet period, so a bulk import that crosses two of them still only
    /// produces one sheet.
    static func recordSheetShown(_ milestone: Int) {
        let defaults = UserDefaults.standard
        defaults.set(Array(Set(shownMilestones + [milestone])).sorted(), forKey: shownMilestonesKey)
        defaults.set(Date.now.timeIntervalSinceReferenceDate, forKey: lastSheetKey)
    }

    /// "Not now" on the sheet. Quiets the banner too: someone who has just
    /// said no should not find the same sentence waiting behind the sheet.
    static func recordNotNow() {
        UserDefaults.standard.set(Date.now.timeIntervalSinceReferenceDate, forKey: bannerDismissedKey)
    }

    /// The banner's ✕. Holds the sheet back for the same quiet period — an ✕
    /// is an answer, and following one with a modal is the behaviour this
    /// whole type exists to prevent.
    static func dismissBanner() {
        let defaults = UserDefaults.standard
        let now = Date.now.timeIntervalSinceReferenceDate
        defaults.set(now, forKey: bannerDismissedKey)
        defaults.set(now, forKey: lastSheetKey)
    }

    // MARK: - Storage

    private static var seenCount: Int? {
        UserDefaults.standard.object(forKey: seenCountKey) as? Int
    }

    private static var shownMilestones: [Int] {
        UserDefaults.standard.array(forKey: shownMilestonesKey) as? [Int] ?? []
    }

    private static func quietIsOver(_ key: String) -> Bool {
        guard let stamp = UserDefaults.standard.object(forKey: key) as? Double else { return true }
        return Date.now.timeIntervalSinceReferenceDate - stamp >= quietPeriod
    }
}

/// `sheet(item:)` wants an `Identifiable`, and the milestone is its own
/// identity — presenting 25 after 5 is a different sheet.
struct SignInMilestone: Identifiable {
    let id: Int
}

/// The Library banner: where your library lives, and the one-tap fix.
///
/// Slim on purpose. It sits under the library's own stats line, so the two
/// read as one thought — what you have, and where it is.
struct SignInNudgeBanner: View {
    let onSignUp: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "iphone")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent.deep)
                .frame(width: 30, height: 30)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Only on this phone.")
                    .font(Typo.ui(13.5, .bold))
                    .foregroundStyle(Tokens.ink)

                Text("Sign up and it's backed up, and on the web at bookmarker.lol.")
                    .font(Typo.ui(12, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onSignUp) {
                    Text("Sign up")
                        .font(Typo.ui(12.5, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.inkMeta)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide this")
        }
        .padding(12)
        .cardSurface(radius: 16)
    }
}

/// The milestone sheet. Small, factual, three ways out.
struct SignInNudgeSheet: View {
    let milestone: Int
    /// The library's real size. Milestones can be crossed in bulk — an import,
    /// or saves that queued while the app was closed — and "5 borks" over a
    /// library of 18 reads as a bug.
    let count: Int
    let onSignUp: () -> Void
    let onSignIn: () -> Void
    let onNotNow: () -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(Copy.countedBorks(max(count, milestone))), all on this phone")
                .font(Typo.display(24, .heavy))
                .tracking(-0.5)
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sign up and they're backed up, and on the web at bookmarker.lol. Nothing else changes.")
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: onSignUp) {
                    Text("Sign up")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button(action: onSignIn) {
                    Text("Sign in")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(accent.deep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accent.tint, in: Capsule())
                        .overlay(Capsule().stroke(accent.base.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }

            Button(action: onNotNow) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.paper)
        // Small on purpose: title, one line, three ways out. The second
        // detent is the escape hatch for large Dynamic Type sizes, which the
        // fixed height would otherwise clip.
        .presentationDetents([.height(272), .medium])
        .presentationCornerRadius(Tokens.sheetRadius)
    }
}
