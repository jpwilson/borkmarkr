import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/save-limit-tests Core/Copy.swift Core/SaveLimit.swift Core/DuplicateSave.swift Scripts/test_save_limit.swift`
///
/// `SaveLimit` decides whether the next save works. Every rule that can lose
/// someone's bork, or wrongly tell a paying-attention user that it did, is
/// checked here — because the alternative is finding out from a review.
///
/// Four things this is really guarding:
///
/// 1. **Signed in means unlimited**, on every function, at every count. One
///    forgotten `signedIn` guard turns the offer into a lie.
/// 2. **The wall and the drain agree.** If `shouldWall` and `mustWait` ever
///    disagree, the Add sheet refuses a save the share sheet accepts, or the
///    other way round.
/// 3. **Admission never drops a bork and never over-admits.** Waiting borks
///    are real saves; the queue is the only thing standing between them and
///    being invisible forever.
/// 4. **The copy is the contract.** These strings are the whole feature as far
///    as the user is concerned, and they are quoted in APPSTORE.md and on the
///    website.

@main
enum SaveLimitTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        func at(_ seconds: Double) -> Date {
            Date(timeIntervalSince1970: 1_800_000_000 + seconds)
        }

        // ── The number is a contract ──────────────────────────────────────
        expect(SaveLimit.limit == 50, "the free limit is 50")
        expect(SaveLimit.counterFloor == 40, "the countdown starts at 40")
        expect(SaveLimit.limit - SaveLimit.counterFloor == 10,
               "ten saves of warning — about a day at the pace that broke twenty")
        expect(SaveLimit.counterFloor < SaveLimit.limit,
               "the countdown starts before the limit, or it is not a warning")

        // ── remaining ─────────────────────────────────────────────────────
        expect(SaveLimit.remaining(liveCount: 0, signedIn: false) == 50, "an empty library has all 50")
        expect(SaveLimit.remaining(liveCount: 40, signedIn: false) == 10, "40 borks leaves 10")
        expect(SaveLimit.remaining(liveCount: 49, signedIn: false) == 1, "49 borks leaves 1")
        expect(SaveLimit.remaining(liveCount: 50, signedIn: false) == 0, "50 borks leaves none")
        expect(
            SaveLimit.remaining(liveCount: 64, signedIn: false) == 0,
            "a library over the limit has zero left, never a negative number"
        )
        expect(
            SaveLimit.remaining(liveCount: 0, signedIn: true) == nil,
            "signed in there is no such thing as remaining"
        )
        expect(
            SaveLimit.remaining(liveCount: 100_000, signedIn: true) == nil,
            "and that stays true at any size"
        )

        // ── The wall, and the drain, agreeing ─────────────────────────────
        for count in 0...55 {
            expect(
                SaveLimit.shouldWall(liveCount: count, signedIn: false)
                    == SaveLimit.mustWait(liveCount: count, signedIn: false),
                "at \(count) borks the Add sheet and the inbox drain agree"
            )
        }
        expect(!SaveLimit.shouldWall(liveCount: 49, signedIn: false), "the 50th save goes through")
        expect(SaveLimit.shouldWall(liveCount: 50, signedIn: false), "the 51st raises the wall")
        expect(SaveLimit.shouldWall(liveCount: 71, signedIn: false),
               "a library that signed out over the limit still cannot add")
        for count in [0, 49, 50, 51, 400] {
            expect(!SaveLimit.shouldWall(liveCount: count, signedIn: true),
                   "signed in, \(count) borks never walls")
            expect(!SaveLimit.mustWait(liveCount: count, signedIn: true),
                   "signed in, a share at \(count) borks never waits")
        }

        // ── The Library card ──────────────────────────────────────────────
        expect(!SaveLimit.showsCounter(liveCount: 39, signedIn: false),
               "at 39 the card still just says where the library lives")
        expect(SaveLimit.showsCounter(liveCount: 40, signedIn: false), "at 40 it starts counting")
        expect(!SaveLimit.showsCounter(liveCount: 40, signedIn: true),
               "signed in it never counts, at any size")

        expect(SaveLimit.bannerHeadline(liveCount: 39, signedIn: false) == nil,
               "below the floor the 1.0.2 headline is left alone")
        expect(
            SaveLimit.bannerHeadline(liveCount: 40, signedIn: false)
                == "10 saves left before you'll need a free account.",
            "at 40 the card reads 10 saves left"
        )
        expect(
            SaveLimit.bannerHeadline(liveCount: 49, signedIn: false)
                == "1 save left before you'll need a free account.",
            "one left is a save, not 1 saves"
        )
        expect(
            SaveLimit.bannerHeadline(liveCount: 50, signedIn: false)
                == "50 borks on this phone — sign up to keep saving.",
            "at the limit the card asks"
        )
        expect(
            SaveLimit.bannerHeadline(liveCount: 64, signedIn: false)
                == "64 borks on this phone — sign up to keep saving.",
            "over the limit it counts the real library rather than insisting on 50"
        )
        expect(SaveLimit.bannerHeadline(liveCount: 60, signedIn: true) == nil,
               "signed in there is no headline to swap in")

        // The ✕ is an answer to a remark, never to a warning.
        expect(SaveLimit.bannerIsDismissable(liveCount: 39, signedIn: false),
               "below the floor the ✕ still buys fourteen days")
        expect(!SaveLimit.bannerIsDismissable(liveCount: 40, signedIn: false),
               "once it is counting down there is no ✕")
        expect(!SaveLimit.bannerIsDismissable(liveCount: 50, signedIn: false),
               "and certainly not at the limit")
        expect(SaveLimit.bannerIsDismissable(liveCount: 999, signedIn: true),
               "signed in the card is a remark again")

        // ── The wall's own copy ───────────────────────────────────────────
        expect(SaveLimit.wallHeadline(liveCount: 50) == "50 borks on this phone.",
               "the wall's headline is the brief's headline")
        expect(SaveLimit.wallHeadline(liveCount: 1) == "1 bork on this phone.",
               "and it pluralises, however unlikely one bork is here")
        expect(SaveLimit.wallBody.contains("free limit without an account"),
               "the body says what the limit is")
        expect(SaveLimit.wallBody.contains("bookmarker.lol"),
               "and what signing up actually buys")
        expect(SaveLimit.privacyLead == "Your borks are always private.",
               "the privacy promise leads with the promise")
        expect(
            SaveLimit.privacyBody.contains("Never sold")
                && SaveLimit.privacyBody.contains("never visible to anyone else"),
            "both halves of the promise survive"
        )
        // Collections can be shared, so "never shared" would now be a lie. The
        // one exception is the user's own choice, and the sentence says so.
        expect(
            !SaveLimit.privacyBody.contains("never shared")
                && SaveLimit.privacyBody.contains("unless you choose to share a collection"),
            "the promise names its one exception, and it is the user's own choice"
        )

        // ── Waiting ───────────────────────────────────────────────────────
        expect(SaveLimit.waitingBanner(count: 0) == nil, "nothing waiting says nothing")
        expect(SaveLimit.waitingBanner(count: 1) == "1 bork waiting — sign up to keep it.",
               "one waiting bork is an it")
        expect(SaveLimit.waitingBanner(count: 3) == "3 borks waiting — sign up to keep them.",
               "three are a them")

        // ── Admission ─────────────────────────────────────────────────────
        let queue = [at(300), at(100), at(200)]   // deliberately unsorted

        expect(
            SaveLimit.admit(liveCount: 50, waiting: queue, signedIn: false).isEmpty,
            "at the limit nothing is admitted"
        )
        expect(
            SaveLimit.admit(liveCount: 49, waiting: queue, signedIn: false) == [at(100)],
            "one delete admits exactly one, and it is the oldest"
        )
        expect(
            SaveLimit.admit(liveCount: 48, waiting: queue, signedIn: false) == [at(100), at(200)],
            "two deletes admit two, still oldest first"
        )
        expect(
            SaveLimit.admit(liveCount: 0, waiting: queue, signedIn: false).count == 3,
            "room for everything admits everything"
        )
        expect(
            SaveLimit.admit(liveCount: 50, waiting: queue, signedIn: true) == [at(100), at(200), at(300)],
            "signing in admits the whole queue regardless of the count"
        )
        expect(
            SaveLimit.admit(liveCount: 500, waiting: queue, signedIn: true).count == 3,
            "and regardless of how far over the old limit the library is"
        )
        expect(
            SaveLimit.admit(liveCount: 55, waiting: queue, signedIn: false).isEmpty,
            "a library over the limit admits nothing until it is back under"
        )
        expect(
            SaveLimit.admit(liveCount: 0, waiting: [], signedIn: false).isEmpty
                && SaveLimit.admit(liveCount: 0, waiting: [], signedIn: true).isEmpty,
            "an empty queue admits nothing either way"
        )

        // Admission never invents or loses a bork: whatever comes back is a
        // subset of what went in, and never more than there is room for.
        for live in 0...52 {
            let admitted = SaveLimit.admit(liveCount: live, waiting: queue, signedIn: false)
            expect(
                admitted.count <= max(0, SaveLimit.limit - live) && admitted.count <= queue.count,
                "at \(live) live, admission never exceeds the room or the queue"
            )
            expect(
                Set(admitted).isSubset(of: Set(queue)),
                "at \(live) live, admission only ever returns borks that were waiting"
            )
            // A library that is already over — someone who signed out of a
            // big account — is never made *worse* by an admission; it just
            // never gets one until it is back under.
            expect(
                live + admitted.count <= max(live, SaveLimit.limit),
                "at \(live) live, admitting never pushes the library further over the limit"
            )
        }

        // Two duplicate timestamps must not collapse into one admission.
        let tied = [at(100), at(100), at(400)]
        expect(
            SaveLimit.admit(liveCount: 48, waiting: tied, signedIn: false) == [at(100), at(100)],
            "two borks that arrived in the same instant are two borks"
        )

        // ── The You tab ───────────────────────────────────────────────────
        expect(SaveLimit.youCount(liveCount: 17, signedIn: false) == "17 of 50", "You says 17 of 50")
        expect(SaveLimit.youCount(liveCount: 0, signedIn: false) == "0 of 50", "and 0 of 50 on day one")
        expect(SaveLimit.youCount(liveCount: 17, signedIn: true) == nil,
               "signed in there is nothing to be out of")
        expect(SaveLimit.youLine.contains("Free limit: 50 borks"), "the You line names the limit")
        expect(SaveLimit.youLine.contains("unlimited"), "and what an account removes")

        // ── Saving a link you already have ────────────────────────────────
        // The other gate on a save. `Store.save` has always merged a repeat
        // save into the bork that is already there; the Add sheet never said
        // so, and quietly re-filed it. `DuplicateSave` is what the sheet asks
        // before it shows the form.
        struct Row { let id: String; let deletedAt: Date? }
        let library = [
            Row(id: "https://instagram.com/reel/a", deletedAt: nil),
            Row(id: "https://x.com/u/status/1", deletedAt: nil),
            Row(id: "https://youtu.be/gone", deletedAt: at(50)),
        ]
        func found(_ id: String) -> Row? {
            DuplicateSave.match(stableID: id, in: library, id: \.id, deletedAt: \.deletedAt)
        }
        expect(found("https://x.com/u/status/1")?.id == "https://x.com/u/status/1",
               "a link already in the library is found")
        expect(found("https://instagram.com/reel/b") == nil,
               "a link that isn't there is not a duplicate")
        expect(found("https://youtu.be/gone") == nil,
               "a bork you deleted is not a duplicate — saving it again is a new save")
        expect(DuplicateSave.match(stableID: "anything", in: [Row](), id: \.id, deletedAt: \.deletedAt) == nil,
               "an empty library has no duplicates")

        expect(DuplicateSave.savedPhrase(daysAgo: 0) == "saved today", "0 days is today")
        expect(DuplicateSave.savedPhrase(daysAgo: 1) == "saved yesterday", "1 day is yesterday")
        expect(DuplicateSave.savedPhrase(daysAgo: 3) == "saved 3 days ago", "3 days counts days")
        expect(DuplicateSave.savedPhrase(daysAgo: 13) == "saved 13 days ago", "so does 13")
        expect(DuplicateSave.savedPhrase(daysAgo: 14) == nil, "past a fortnight the caller prints a date")

        expect(DuplicateSave.filedPhrase(topic: "Fitness", subtopic: "Running") == "filed under Fitness › Running",
               "topic and subtopic read as a path")
        expect(DuplicateSave.filedPhrase(topic: "Fitness", subtopic: nil) == "filed under Fitness",
               "a topic with no subtopic stops there")
        expect(DuplicateSave.filedPhrase(topic: nil, subtopic: nil) == "not filed yet",
               "an unfiled bork says so rather than inventing a topic")

        print(failures == 0 ? "\nAll save limit checks passed."
                            : "\n\(failures) save limit check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
