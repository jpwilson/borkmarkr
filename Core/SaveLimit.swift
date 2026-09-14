import Foundation

/// How many borks a signed-out library may hold, and what to say about it.
///
/// ## Why there is a limit at all
///
/// bookmarker has always worked signed out, and the You tab has always said
/// the library lives only on this phone. People still did not know: the tab a
/// happy user never opens is the tab where that sentence lived. The 1.0.2
/// banner and milestone sheet (`SignInNudge`) made it visible; they did not
/// make it *land*. Someone with four hundred borks and no account still loses
/// all four hundred when the phone goes in a river, and still can't open
/// bookmarker.lol and find a thing.
///
/// Product policy (September 2026): try twenty saves on iPhone without an
/// account. Sign in to keep saving and to use the web library. This is an
/// account requirement, not a payment gate. Existing saves are never removed.
///
/// ## Why this does not break the core product rule
///
/// **Saving must always be instant, and a save is never gated.** That rule
/// stands, and it is the reason the limit is shaped the way it is:
///
/// - The **Share Extension never refuses**. It writes its draft to the App
///   Group inbox exactly as before, in the same few milliseconds, over the top
///   of Instagram. It does not know or care what the library holds.
/// - A draft that arrives over the limit is still **saved as a real Bookmark**.
///   It is marked *waiting* (`Bookmark.waitingSince`) — greyed in the Library,
///   held out of Browse, search and topic counts — and admitted the moment
///   there is room, or the moment an account exists. Nothing is dropped,
///   nothing is queued in a place the user cannot see, nothing needs re-sharing.
/// - The only place anything is actually refused is the **Add sheet**, where a
///   person is already in the app, has a keyboard up, and can read a sheet.
///
/// So the limit gates *the twenty-first slot*, never the act of saving.
///
/// ## Signed in
///
/// There is no limit, and none of this applies — no counter, no wall, no
/// waiting. That is the whole offer, and hedging it would make the offer a lie.
///
/// Pure by design: every function here takes plain values and returns plain
/// values, so `Scripts/test_save_limit.swift` can exercise the entire policy
/// without SwiftData, a simulator or a signed-in session.
enum SaveLimit {

    /// Live borks a signed-out library may hold.
    static let limit = 20

    /// Where the Library card stops saying where your library lives and starts
    /// counting down. Ten saves is about a day for someone saving the way the
    /// first outside user did (eleven a day) and a week or more for most —
    /// enough warning to act on, late enough that many people never see it.
    static let counterFloor = 10

    // MARK: - The numbers

    /// Saves left before an account is needed, or `nil` when there is no limit.
    ///
    /// Never negative. A library that is over the limit — someone who signed
    /// out with more than twenty — has zero left, not minus fourteen.
    static func remaining(liveCount: Int, signedIn: Bool) -> Int? {
        guard !signedIn else { return nil }
        return max(0, limit - liveCount)
    }

    /// Whether a save attempt must raise the wall instead of saving.
    static func shouldWall(liveCount: Int, signedIn: Bool) -> Bool {
        (remaining(liveCount: liveCount, signedIn: signedIn) ?? 1) == 0
    }

    /// Whether an inbox draft draining now has to wait.
    ///
    /// Same question as `shouldWall`, asked by the drain rather than by a
    /// button — kept as its own name because the answers must never drift
    /// apart, and because the call sites read very differently.
    static func mustWait(liveCount: Int, signedIn: Bool) -> Bool {
        shouldWall(liveCount: liveCount, signedIn: signedIn)
    }

    // MARK: - The Library card

    /// Whether the existing sign-in card is now carrying the countdown.
    static func showsCounter(liveCount: Int, signedIn: Bool) -> Bool {
        !signedIn && liveCount >= counterFloor
    }

    /// The ✕ on the sign-in card is a real answer right up until the countdown
    /// starts. After that the card is load-bearing — it is the only warning
    /// before a save stops working — so it stays.
    static func bannerIsDismissable(liveCount: Int, signedIn: Bool) -> Bool {
        !showsCounter(liveCount: liveCount, signedIn: signedIn)
    }

    /// The card's headline, or `nil` to leave the 1.0.2 wording alone.
    ///
    /// At the limit this counts the *real* library rather than printing "20".
    /// Someone who signed out of an account holding sixty-four borks sees
    /// sixty-four; telling them they have twenty would be the app arguing
    /// with the screen behind it.
    static func bannerHeadline(liveCount: Int, signedIn: Bool) -> String? {
        guard let left = remaining(liveCount: liveCount, signedIn: signedIn),
              showsCounter(liveCount: liveCount, signedIn: signedIn)
        else { return nil }

        if left == 0 {
            return "\(Copy.countedBorks(liveCount)) on this phone — sign up to keep saving."
        }
        return "\(left) save\(left == 1 ? "" : "s") left before you'll need a free account."
    }

    // MARK: - The wall

    static func wallHeadline(liveCount: Int) -> String {
        "\(Copy.countedBorks(liveCount)) on this phone."
    }

    static let wallBody =
        "That's the limit without an account. Sign up — it's free — and keep saving: everything backs up and shows up at bookmarker.lol."

    /// Lead and body of the privacy promise, split so the view can weight the
    /// first half. One sentence, no hedging, and true of the code: bookmarks
    /// are row-level-secured to their owner, and the only way one reaches
    /// another person is its owner putting it in a collection and turning that
    /// collection's link on. "Never shared" left the sentence when collections
    /// arrived — see *Shared collections* in DECISIONS.md.
    static let privacyLead = "Your borks are always private."
    static let privacyBody = "Never sold, never visible to anyone else — unless you choose to share a collection."

    // MARK: - Waiting

    /// The Library's waiting banner, or `nil` when nothing is waiting.
    static func waitingBanner(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(Copy.countedBorks(count)) waiting — sign up to keep \(count == 1 ? "it" : "them")."
    }

    /// Which waiting borks may be admitted right now, oldest first.
    ///
    /// - `liveCount` is the library *excluding* everything still waiting.
    /// - `waiting` is every waiting bork's `waitingSince`, in any order.
    ///
    /// Signing in admits all of them: the limit no longer exists, so neither
    /// does the queue. Otherwise deletes make room, and the room goes to
    /// whatever has been waiting longest — the share you sent first is the one
    /// you have been waiting on.
    static func admit(liveCount: Int, waiting: [Date], signedIn: Bool) -> [Date] {
        let queue = waiting.sorted()
        guard !signedIn else { return queue }
        let room = max(0, limit - liveCount)
        return Array(queue.prefix(room))
    }

    // MARK: - The You tab

    /// "17 of 20". `nil` signed in, where there is nothing to be out of.
    static func youCount(liveCount: Int, signedIn: Bool) -> String? {
        guard !signedIn else { return nil }
        return "\(liveCount) of \(limit)"
    }

    static let youLine = "Without an account: 20 borks. Sign up for unlimited, backed up, and on the web."
}
