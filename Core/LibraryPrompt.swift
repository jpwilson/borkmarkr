import Foundation

/// The one slim action row the Library may show under its search field.
///
/// 1.3 stacked up to four cards there — the waiting banner, "Sort your
/// borks", the backup nudge and the dial hint — and on a signed-out phone two
/// or three of them at once pushed the first save below the fold. Quiet clay
/// allows **one** (design/SYSTEM.md, "Slim action row"), so the choice is a
/// policy, and a policy is pure and tested (`Scripts/test_library_prompt.swift`).
///
/// Priority, highest first:
/// 1. **waiting** — borks already sent that are not in the library yet.
///    It is about saves the person made and cannot see working.
/// 2. **backup** — the signed-out card: "only on this phone", then the
///    countdown to the save limit. Past the counter floor it is the only
///    warning before a save stops working, so it outranks housekeeping.
/// 3. **sort** — unfiled borks, until waved away at this count.
/// 4. **dial hint** — where the dial lives, once.
///
/// Whatever is not picked is not lost: each prompt's own state (snooze,
/// dismissal, the hint's "done") is untouched, so the next one surfaces the
/// moment the one above it goes.
///
/// Foundation only, so it compiles alone with `Core/Copy.swift` and
/// `Core/SaveLimit.swift` for the test.
enum LibraryPrompt: Equatable {
    case waiting(count: Int)
    /// Signed out only. `liveCount` decides between "only on this phone" and
    /// the countdown (`SaveLimit`).
    case backup(liveCount: Int)
    case sort(count: Int)
    case dialHint

    /// The prompt to show, or `nil` for none.
    ///
    /// - `waiting`: borks held back by the save limit.
    /// - `backupDue`: `SignInNudge.showsBanner` — already false signed in, and
    ///   during the quiet period after an ✕ below the counter floor.
    /// - `liveCount`: the library without waiting borks.
    /// - `unsorted` / `sortSnoozedAt`: the sort row shows while the unfiled
    ///   count is above the count it was waved away at.
    /// - `dialHintDue`: the hint has not done its job yet.
    static func pick(
        waiting: Int,
        backupDue: Bool,
        liveCount: Int,
        unsorted: Int,
        sortSnoozedAt: Int,
        dialHintDue: Bool
    ) -> LibraryPrompt? {
        if waiting > 0 { return .waiting(count: waiting) }
        if backupDue { return .backup(liveCount: liveCount) }
        if unsorted > 0 && unsorted > sortSnoozedAt { return .sort(count: unsorted) }
        if dialHintDue { return .dialHint }
        return nil
    }

    // MARK: - Copy

    /// 15/600, one line at the default size on the smallest phone.
    var title: String {
        switch self {
        case .waiting(let count):
            return "\(Copy.countedBorks(count)) waiting"
        case .backup(let liveCount):
            guard let left = Self.countdown(liveCount) else { return "Only on this phone" }
            return left == 0
                ? "\(Copy.countedBorks(liveCount)) on this phone"
                : "\(left) save\(left == 1 ? "" : "s") left"
        case .sort(let count):
            return "\(Copy.countedBorks(count)) to sort"
        case .dialHint:
            return "File every bork in one tap"
        }
    }

    /// 13/18 secondary, under the title.
    var subtitle: String {
        switch self {
        case .waiting(let count):
            return "Sign up to keep \(count == 1 ? "it" : "them")"
        case .backup(let liveCount):
            guard let left = Self.countdown(liveCount) else { return "Sign up and it's backed up" }
            return left == 0 ? "Sign up to keep saving" : "Then you'll need a free account"
        case .sort:
            return "One tap each"
        case .dialHint:
            return "Tap + or share from any app"
        }
    }

    /// The quiet coral action at the right.
    var action: String {
        switch self {
        case .waiting: return "Keep"
        case .backup: return "Sign up"
        case .sort: return "Sort"
        case .dialHint: return "Try it"
        }
    }

    /// Whether the row carries an ✕. Waiting borks are not a remark; the
    /// countdown is load-bearing (`SaveLimit.bannerIsDismissable`).
    var isDismissable: Bool {
        switch self {
        case .waiting: return false
        case .backup(let liveCount):
            return SaveLimit.bannerIsDismissable(liveCount: liveCount, signedIn: false)
        case .sort, .dialHint: return true
        }
    }

    /// What VoiceOver hears: the full sentence the 1.3 banner said, where
    /// there was one, so no meaning is lost to the shorter row.
    var spoken: String {
        switch self {
        case .waiting(let count):
            return SaveLimit.waitingBanner(count: count) ?? "\(title). \(subtitle)"
        case .backup(let liveCount):
            return SaveLimit.bannerHeadline(liveCount: liveCount, signedIn: false)
                ?? "Only on this phone. Sign up and it's backed up, and on the web at bookmarker.lol."
        case .sort, .dialHint:
            return "\(title). \(subtitle)"
        }
    }

    /// Saves left once the countdown runs, else `nil`.
    private static func countdown(_ liveCount: Int) -> Int? {
        guard SaveLimit.showsCounter(liveCount: liveCount, signedIn: false) else { return nil }
        return SaveLimit.remaining(liveCount: liveCount, signedIn: false)
    }
}
