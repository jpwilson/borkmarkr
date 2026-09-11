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
///
/// ## 1.1: the same card, now counting
///
/// `SaveLimit` puts a ceiling on a signed-out library, so from forty borks
/// this card stops describing where the library lives and starts saying how
/// many saves are left. It is the *same* card in the same place — a second
/// banner would be two things nagging where one was enough — and the only rule
/// that changes is the ✕: once the countdown is running the card is the only
/// warning before a save stops working, so it stays put. Below forty the ✕
/// buys fourteen days exactly as it always did.
///
/// The milestone sheet narrows to match: signed out there is one, at five.
/// Twenty-five is reachable again now that the limit is fifty, and it stays
/// off the signed-out list on purpose — between five and the wall the reminder
/// is this card, which says a number rather than raising a modal. Twenty-five
/// and a hundred fire only for someone who *has* an account and has never
/// once synced — see `dueMilestone`.
@MainActor
enum SignInNudge {

    /// Library size from which the banner and the You-tab dot appear. Below
    /// three borks there is little to lose and the app is still being tried.
    static let bannerFloor = 3

    /// The three sheet moments. Each is a point where the library stops being
    /// an experiment. Which of them is eligible now depends on whether there
    /// is an account — see `dueMilestone`.
    static let milestones = [5, 25, 100]

    /// What any dismissal buys.
    static let quietPeriod: TimeInterval = 14 * 86_400

    private static let bannerDismissedKey = "signInNudgeBannerDismissedAt"
    private static let lastSheetKey = "signInNudgeLastSheetAt"
    private static let shownMilestonesKey = "signInNudgeShownMilestones"
    private static let seenCountKey = "signInNudgeSeenBorkCount"

    // MARK: - What to show

    /// `borks` is the **live** count — waiting borks are not yet part of the
    /// library the limit is about, and are announced by their own banner.
    static func showsBanner(signedIn: Bool, borks: Int) -> Bool {
        guard !signedIn, borks >= bannerFloor else { return false }
        // Past the counter floor the card is a warning, not a remark, and a ✕
        // pressed three weeks ago is not consent to lose the next save.
        if SaveLimit.showsCounter(liveCount: borks, signedIn: signedIn) { return true }
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
    ///
    /// 1.1 splits the three in half, because the save limit made the old set
    /// incoherent:
    ///
    /// - **5, signed out.** Unchanged. The one moment where "this only lives
    ///   on this phone" is news and the library is worth something.
    /// - **25 and 100, signed in only, and only if the account has never
    ///   synced.** With the limit at fifty, twenty-five *is* reachable signed
    ///   out again — and it is still not a sign-up sheet, on purpose. Between
    ///   the sheet at five and the wall at fifty the signed-out reminder is
    ///   the Library card: dismissable and back after fourteen days, then
    ///   counting down from forty with no ✕. A second modal in that stretch
    ///   would be a new nag, and it would not even reach the person it was
    ///   aimed at — anyone saving fast enough to hit twenty-five within a
    ///   fortnight of the five-sheet is inside the quiet period, this returns
    ///   nil, and `recordSeen` moves the watermark past it for good. So 25 and
    ///   100 survive as the one thing still worth saying to someone who signed
    ///   up and whose backup has never actually run — a signed-in library that
    ///   is not backed up is the failure the account was meant to prevent.
    ///   When the backup is working, which is the normal case, both are
    ///   skipped entirely.
    static func dueMilestone(borks: Int, signedIn: Bool, hasSynced: Bool) -> Int? {
        // No watermark yet means this policy has never looked at this library.
        // Whatever it has already passed is history, not an achievement.
        guard let watermark = seenCount, quietIsOver(lastSheetKey) else { return nil }
        let eligible = signedIn ? (hasSynced ? [] : backupMilestones) : signUpMilestones
        let shown = shownMilestones
        return eligible.last { $0 <= borks && $0 > watermark && !shown.contains($0) }
    }

    /// The one signed-out moment. Twenty-five is deliberately not here — see
    /// `dueMilestone`.
    static let signUpMilestones = [5]
    /// Backup reminders for a signed-in account that has never synced. Not a
    /// sign-up prompt at any count.
    static let backupMilestones = [25, 100]

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
    /// The Library states where the library lives; Revisit, where the reason
    /// you are looking at it is "these are worth keeping", asks for the backup
    /// directly. Same component, same policy, one word of context.
    var headline: String = "Only on this phone."
    /// False once `SaveLimit` has the card counting down. The ✕ is an honest
    /// answer to "your library is only on this phone"; it is not an answer to
    /// "your next save will not work", so past the counter floor there isn't
    /// one to press.
    var dismissable: Bool = true
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
                Text(headline)
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

            if dismissable {
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
    /// Signed in, this is not a sign-up prompt: the account exists and the
    /// backup has simply never run. Same sheet, one primary button, honest
    /// about which of the two problems it is.
    var signedIn: Bool = false
    let onSignUp: () -> Void
    let onSignIn: () -> Void
    let onNotNow: () -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(signedIn
                 ? "\(Copy.countedBorks(max(count, milestone))), not backed up yet"
                 : "\(Copy.countedBorks(max(count, milestone))), all on this phone")
                .font(Typo.display(24, .heavy))
                .tracking(-0.5)
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(signedIn
                 ? "You have an account, but this library has never reached it. Back up now and it's safe, and on the web at bookmarker.lol."
                 : "Sign up and they're backed up, and on the web at bookmarker.lol. Nothing else changes.")
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: onSignUp) {
                    Text(signedIn ? "Back up now" : "Sign up")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                if !signedIn {
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

// MARK: - The save limit wall

/// Why a save is being asked to wait, and therefore why this sheet is up.
///
/// `sheet(item:)` wants an `Identifiable`, and the reason is the identity —
/// arriving here from the + button and arriving here from a share that landed
/// over the limit are different moments, even though the sheet is the same.
struct SaveLimitReason: Identifiable, Equatable {
    enum Kind: String {
        /// The + button, before the Add sheet ever opens.
        case add
        /// The Save button, when the limit was reached while the sheet was up.
        case addSheet
        /// Borks are waiting: a share landed over the limit, or the Library's
        /// waiting banner was tapped.
        case waiting
    }
    let kind: Kind
    var id: String { kind.rawValue }

    static let add = SaveLimitReason(kind: .add)
    static let addSheet = SaveLimitReason(kind: .addSheet)
    static let waiting = SaveLimitReason(kind: .waiting)
}

/// The wall. Shown when a save has nowhere to go, and never otherwise.
///
/// **This is the answer to an action, never a greeting.** It cannot appear on
/// launch, because nothing is walled until either the person tries to save or
/// a share has already landed over the limit and is sitting greyed in the
/// Library waiting to be explained. A modal that opens the app is the exact
/// behaviour `SignInNudge` exists to refuse, and the limit does not get to
/// change that.
///
/// Three ways out, in the order the design asks for them, and the third is a
/// real one: **Make room instead** takes the ask away entirely and points at
/// the delete that is already in the app. Someone who does not want an account
/// should not have to want one.
///
/// The privacy paragraph is not decoration. "Sign up" is being asked of
/// someone who chose not to, and the honest objection is *what happens to my
/// borks*. It is a promise the code keeps: rows are owner-scoped by RLS, there
/// is no sharing feature to leak them through, and nothing is sold — see
/// DECISIONS.md.
struct SaveLimitWall: View {
    /// The live library, so the headline counts the real thing.
    let liveCount: Int
    let onSignUp: () -> Void
    let onSignIn: () -> Void
    let onMakeRoom: () -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SaveLimit.wallHeadline(liveCount: liveCount))
                .font(Typo.display(24, .heavy))
                .tracking(-0.5)
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(SaveLimit.wallBody)
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Its own paragraph, on its own ground. Buried in the body it
            // reads as a disclaimer; given a card it reads as the promise it
            // is, and it is the sentence that answers the actual objection.
            VStack(alignment: .leading, spacing: 2) {
                Text(SaveLimit.privacyLead)
                    .font(Typo.ui(13.5, .bold))
                    .foregroundStyle(Tokens.ink)
                Text(SaveLimit.privacyBody)
                    .font(Typo.ui(13))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(accent.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.base.opacity(0.25), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)

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

            Button(action: onMakeRoom) {
                Text("Make room instead")
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
        // Taller than the milestone sheet by exactly the privacy card, and
        // measured rather than guessed — a detent with slack in it reads as a
        // sheet that failed to load its own content. `.large` is the Dynamic
        // Type escape hatch, as on the milestone sheet.
        .presentationDetents([.height(330), .large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }
}

/// "3 borks waiting — sign up to keep them." Sits at the very top of the
/// Library, above everything, because it is about borks the user has already
/// sent and cannot yet see working.
struct WaitingBanner: View {
    let count: Int
    let onTap: () -> Void

    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.deep)
                    .frame(width: 30, height: 30)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)

                Text(SaveLimit.waitingBanner(count: count) ?? "")
                    .font(Typo.ui(13, .bold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.inkMeta)
            }
            .padding(12)
            .cardSurface(radius: 16)
        }
        .buttonStyle(PressableStyle())
    }
}
