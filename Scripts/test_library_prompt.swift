import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/library-prompt-tests Core/Copy.swift Core/SaveLimit.swift Core/LibraryPrompt.swift Scripts/test_library_prompt.swift`
///
/// The Library shows at most one slim action row (design/SYSTEM.md). These
/// checks pin which one wins — waiting > backup > sort > dial hint — that a
/// prompt nobody asked for never appears, and the short copy each row says.

@main
enum LibraryPromptTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        func pick(waiting: Int = 0, backupDue: Bool = false, live: Int = 30,
                  unsorted: Int = 0, snoozedAt: Int = 0, dialHint: Bool = false) -> LibraryPrompt? {
            LibraryPrompt.pick(waiting: waiting, backupDue: backupDue, liveCount: live,
                               unsorted: unsorted, sortSnoozedAt: snoozedAt, dialHintDue: dialHint)
        }

        // ── Nothing due, nothing shown ────────────────────────────────────
        expect(pick() == nil, "a library with nothing to say shows no row")
        expect(pick(unsorted: 4, snoozedAt: 4) == nil, "a sort row waved away at this count stays away")
        expect(pick(unsorted: 3, snoozedAt: 4) == nil, "and stays away as the count falls")

        // ── Each prompt on its own ────────────────────────────────────────
        expect(pick(waiting: 3) == .waiting(count: 3), "waiting borks get the row")
        expect(pick(backupDue: true, live: 7) == .backup(liveCount: 7), "a due backup nudge gets the row")
        expect(pick(unsorted: 8) == .sort(count: 8), "unfiled borks get the sort row")
        expect(pick(unsorted: 5, snoozedAt: 4) == .sort(count: 5), "the sort row returns when the count rises past its snooze")
        expect(pick(dialHint: true) == .dialHint, "the dial hint shows when nothing else is due")

        // ── Priority: waiting > backup > sort > dial hint ─────────────────
        expect(pick(waiting: 1, backupDue: true, unsorted: 8, dialHint: true) == .waiting(count: 1),
               "waiting beats everything")
        expect(pick(backupDue: true, live: 15, unsorted: 8, dialHint: true) == .backup(liveCount: 15),
               "backup beats sort and the dial hint")
        expect(pick(unsorted: 8, dialHint: true) == .sort(count: 8), "sort beats the dial hint")
        expect(pick(backupDue: true, unsorted: 8, snoozedAt: 8, dialHint: true) == .backup(liveCount: 30),
               "a snoozed sort row does not hide what is below it")
        expect(pick(unsorted: 8, snoozedAt: 8, dialHint: true) == .dialHint,
               "and a snoozed sort row lets the dial hint through")

        // ── Copy ──────────────────────────────────────────────────────────
        let sort = LibraryPrompt.sort(count: 8)
        expect(sort.title == "8 borks to sort", "sort title, as the approved artboard")
        expect(sort.subtitle == "One tap each", "sort subtitle, as the approved artboard")
        expect(sort.action == "Sort", "sort action")
        expect(LibraryPrompt.sort(count: 1).title == "1 bork to sort", "one bork is singular")

        let waiting = LibraryPrompt.waiting(count: 3)
        expect(waiting.title == "3 borks waiting", "waiting title")
        expect(waiting.subtitle == "Sign up to keep them", "waiting subtitle, plural")
        expect(LibraryPrompt.waiting(count: 1).subtitle == "Sign up to keep it", "waiting subtitle, singular")
        expect(waiting.spoken == "3 borks waiting — sign up to keep them.",
               "VoiceOver hears SaveLimit's full sentence")
        expect(!waiting.isDismissable, "waiting borks cannot be waved away")

        let early = LibraryPrompt.backup(liveCount: 5)
        expect(early.title == "Only on this phone", "below the counter floor it says where the library lives")
        expect(early.isDismissable, "and it can be waved away")
        let counting = LibraryPrompt.backup(liveCount: 15)
        expect(counting.title == "5 saves left", "from the counter floor it counts down")
        expect(counting.subtitle == "Then you'll need a free account", "and says what happens next")
        expect(!counting.isDismissable, "the countdown cannot be waved away")
        expect(counting.spoken == "5 saves left before you'll need a free account.",
               "VoiceOver hears SaveLimit's countdown sentence")
        expect(LibraryPrompt.backup(liveCount: 19).title == "1 save left", "one save is singular")
        let full = LibraryPrompt.backup(liveCount: 20)
        expect(full.title == "20 borks on this phone", "at the limit it counts the real library")
        expect(full.subtitle == "Sign up to keep saving", "and asks for the account")
        expect(LibraryPrompt.backup(liveCount: 64).title == "64 borks on this phone",
               "over the limit it still counts the real library, never \"64 of 20\"")
        expect(full.action == "Sign up", "backup action")

        let hint = LibraryPrompt.dialHint
        expect(hint.action == "Try it", "dial hint action")
        expect(hint.isDismissable, "the dial hint can be put away")
        expect(LibraryPrompt.sort(count: 2).isDismissable, "the sort row can be snoozed")

        // Every title fits one line of the slim row on a 320 pt phone at
        // 15 pt: about 30 characters beside a 36 pt thumb and the action.
        let all: [LibraryPrompt] = [
            .waiting(count: 120), .backup(liveCount: 3), .backup(liveCount: 11),
            .backup(liveCount: 999), .sort(count: 999), .dialHint,
        ]
        for prompt in all {
            expect(prompt.title.count <= 30, "\"\(prompt.title)\" is short enough for one line")
            expect(!prompt.subtitle.isEmpty && !prompt.action.isEmpty, "\"\(prompt.title)\" has a subtitle and an action")
        }

        print(failures == 0 ? "\nAll library prompt checks passed."
                            : "\n\(failures) library prompt check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
