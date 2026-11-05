import XCTest
@testable import borkmarkr

/// The share sheet's late answers (`QuickFileShareSession.enrich`), with the
/// page and the model stubbed, and the session the extension may borrow.
final class QuickFileShareTests: XCTestCase {
    private static let link = URL(string: "https://www.instagram.com/reel/DAbc123xyz/")!
    /// Words, but none the keywords know.
    private static let vague = "she does this every morning and it changed everything"
    private static let signedIn = Supabase.Session(accessToken: "access", refreshToken: "", expiresAt: .distantFuture,
                                                   userID: "user", email: "you@example.test")
    private static let skincare = Categorizer.Suggestion(categoryID: "beauty", subcategory: "Skincare",
                                                         tags: ["skincare"], score: 28)
    /// The same answer at medium confidence: 13 points, one short of sure.
    private static let skincareMaybe = Categorizer.Suggestion(categoryID: "beauty", subcategory: "Skincare",
                                                              tags: ["skincare"], score: 13)

    @MainActor func testAnUntouchedDialRedealsAndKeepsTheAnswerOnce() async {
        let (share, probe) = Self.share(caption: Self.vague)
        await share.enrich(session: Self.signedIn, read: { _ in
            await probe.read()
            return LinkPreview.Result(imageURL: URL(string: "https://example.com/cover.jpg"))
        }, judge: { _, _ in
            await probe.ask(share)
            return Self.skincare
        })
        XCTAssertEqual(probe.reads, 1)
        XCTAssertEqual(probe.asks, 1)
        // Not sure without it: an untouched sheet waits for the answer.
        XCTAssertEqual(probe.held, [true])
        XCTAssertEqual(share.model.revision, 1)
        XCTAssertEqual(share.model.centre?.categoryID, "beauty")
        XCTAssertNotNil(share.model.movedAt)
        XCTAssertFalse(share.model.isAsking)
        XCTAssertEqual(probe.writes.count, 1)
        let kept = probe.writes.last
        XCTAssertEqual(kept?.categoryID, "beauty")
        XCTAssertEqual(kept?.subcategory, "Skincare")
        XCTAssertNil(kept?.filingSource)
        XCTAssertEqual(kept?.tags, ["skincare"])
        XCTAssertEqual(kept?.previewFetched, true)
        XCTAssertEqual(kept?.imageURLString, "https://example.com/cover.jpg")

        // Touched but not filed: the dial stays put, and the answer is still kept.
        let (touched, touchedProbe) = Self.share(caption: Self.vague)
        touched.model.touch()
        await touched.enrich(session: Self.signedIn, read: { _ in nil }, judge: { _, _ in Self.skincare })
        XCTAssertEqual(touched.model.revision, 0)
        XCTAssertNil(touched.model.centre)
        XCTAssertTrue(touched.model.sparkle == "beauty" || touched.model.aiChip?.categoryID == "beauty")
        XCTAssertEqual(touchedProbe.writes.map(\.categoryID), ["beauty"])
    }

    @MainActor func testStrongEvidenceIsAskedAboutWithoutHoldingTheSheet() async {
        // Sure from the share's own words: asked all the same, but the sheet
        // closes at its usual time rather than wait for the answer. A medium
        // answer doesn't outrank sure keywords, and it settles the save even
        // though the page ran out of time.
        let (sure, sureProbe) = Self.share(caption: "Five hip mobility drills")
        await sure.enrich(session: Self.signedIn, read: { _ in
            await sureProbe.read()
            return nil
        }, judge: { _, _ in
            await sureProbe.ask(sure)
            return Self.skincareMaybe
        })
        XCTAssertEqual(sureProbe.reads, 1)
        XCTAssertEqual(sureProbe.asks, 1)
        XCTAssertEqual(sureProbe.held, [false])
        XCTAssertFalse(sure.model.isAsking)
        XCTAssertEqual(sure.model.centre?.categoryID, "fitness")
        XCTAssertEqual(sureProbe.writes.count, 1)
        let settled = sureProbe.writes.last
        XCTAssertEqual(settled?.categoryID, "fitness")
        XCTAssertEqual(settled?.subcategory, "Mobility")
        XCTAssertNil(settled?.filingSource)
        XCTAssertEqual(settled?.previewFetched, true)
    }

    @MainActor func testOnlyTheAnswerSettlesASurePage() async {
        // Sure once the page is read: what stays follows it at once, still
        // unsettled, and the answer then settles it and takes the page along.
        // A medium answer doesn't outrank the page's hashtag.
        let (read, readProbe) = Self.share(caption: Self.vague)
        await read.enrich(session: Self.signedIn, read: { _ in
            LinkPreview.Result(author: "@kaylawalks", description: "Five hip mobility drills #mobility")
        }, judge: { _, _ in
            await readProbe.ask()
            return Self.skincareMaybe
        })
        XCTAssertEqual(readProbe.asks, 1)
        XCTAssertEqual(read.model.centre?.categoryID, "fitness")
        XCTAssertEqual(readProbe.writes.map(\.categoryID), ["fitness", "fitness"])
        XCTAssertEqual(readProbe.writes.map(\.previewFetched), [false, true])
        let kept = readProbe.writes.last
        XCTAssertEqual(kept?.subcategory, "Mobility")
        XCTAssertEqual(kept?.author, "@kaylawalks")

        // Sure once the page is read, but the dial was touched: asked all the
        // same. With no answer (offline, quota spent), what stays doesn't
        // move, and nothing marks the page read over a guess it contradicts.
        let (touched, touchedProbe) = Self.share(caption: Self.vague)
        touched.model.touch()
        await touched.enrich(session: Self.signedIn, read: { _ in
            LinkPreview.Result(description: "Five hip mobility drills #mobility")
        }, judge: { _, _ in
            await touchedProbe.ask()
            return nil
        })
        XCTAssertEqual(touchedProbe.asks, 1)
        XCTAssertTrue(touchedProbe.writes.isEmpty)
    }

    @MainActor func testNothingIsKeptOverAFilingOrAfterTheSheetCloses() async {
        // Filed before anything was asked: no network at all.
        let (filed, filedProbe) = Self.share(caption: Self.vague)
        filed.model.file(filed.model.candidate(topicID: "fitness", subcategory: nil))
        await filed.enrich(session: Self.signedIn, read: { _ in
            await filedProbe.read()
            return nil
        }, judge: { _, _ in
            await filedProbe.ask()
            return Self.skincare
        })
        XCTAssertEqual(filedProbe.reads + filedProbe.asks, 0)
        XCTAssertEqual(filedProbe.writes.map(\.filingSource), ["user"])

        // Filed while the model was answering.
        let (late, lateProbe) = Self.share(caption: Self.vague)
        await late.enrich(session: Self.signedIn, read: { _ in nil }, judge: { _, _ in
            await MainActor.run { late.model.file(late.model.candidate(topicID: "fitness", subcategory: nil)) }
            return Self.skincare
        })
        XCTAssertEqual(lateProbe.writes.map(\.filingSource), ["user"])

        // Filed and undone while it was answering: the guess put back stays.
        let (undone, undoneProbe) = Self.share(caption: Self.vague)
        await undone.enrich(session: Self.signedIn, read: { _ in nil }, judge: { _, _ in
            await MainActor.run {
                undone.model.file(undone.model.candidate(topicID: "fitness", subcategory: nil))
                undone.model.undo()
            }
            return Self.skincare
        })
        XCTAssertEqual(undoneProbe.writes.map(\.filingSource), ["user", nil])
        XCTAssertNil(undoneProbe.writes.last?.categoryID)

        // Closed while it was answering.
        let (gone, goneProbe) = Self.share(caption: Self.vague)
        await gone.enrich(session: Self.signedIn, read: { _ in nil }, judge: { _, _ in
            await gone.close()
            return Self.skincare
        })
        XCTAssertTrue(goneProbe.writes.isEmpty)
        XCTAssertEqual(gone.model.revision, 0)
        XCTAssertFalse(gone.model.isAsking)

        // Sure once the page is read, then closed while it was answering: the
        // guess the page dealt stays, unsettled, for PreviewFetcher to ask.
        let (cut, cutProbe) = Self.share(caption: Self.vague)
        await cut.enrich(session: Self.signedIn, read: { _ in
            LinkPreview.Result(description: "Five hip mobility drills #mobility")
        }, judge: { _, _ in
            await cut.close()
            return Self.skincare
        })
        XCTAssertEqual(cutProbe.writes.map(\.categoryID), ["fitness"])
        XCTAssertEqual(cutProbe.writes.last?.previewFetched, false)
    }

    func testTheExtensionBorrowsOnlyALiveTokenAndNeverTheRefreshToken() {
        let now = Date()
        func stored(expiringIn seconds: TimeInterval) -> Supabase.Session {
            Supabase.Session(accessToken: "access", refreshToken: "refresh",
                             expiresAt: now.addingTimeInterval(seconds), userID: "user", email: "you@example.test")
        }
        XCTAssertNil(SessionKeychain.borrowable(stored(expiringIn: 119), now: now))
        let borrowed = SessionKeychain.borrowable(stored(expiringIn: 121), now: now)
        XCTAssertEqual(borrowed?.accessToken, "access")
        XCTAssertEqual(borrowed?.refreshToken, "")
        XCTAssertNil(SessionKeychain.borrowable(nil, now: now))
    }

    /// A share of `link` whose inbox writes land in the probe.
    @MainActor private static func share(caption: String) -> (QuickFileShareSession, Probe) {
        let probe = Probe()
        let saved = BookmarkDraft.handedOver(url: link, caption: caption)
        let share = QuickFileShareSession(saved: saved, snapshot: nil) { probe.writes.append($0) }
        return (share, probe)
    }
}

/// What the stubs were asked, and what reached the inbox.
@MainActor
private final class Probe {
    var reads = 0
    var asks = 0
    /// For each `ask(_:)`: whether the sheet, untouched, would wait past its
    /// drain for that answer.
    var held: [Bool] = []
    var writes: [BookmarkDraft] = []

    func read() { reads += 1 }
    func ask() { asks += 1 }
    func ask(_ share: QuickFileShareSession) {
        ask()
        held.append(QuickFileShareView.waitsForAnswer(share.model))
    }
}
