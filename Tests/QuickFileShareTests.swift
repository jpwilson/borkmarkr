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

    @MainActor func testAnUntouchedDialRedealsAndKeepsTheAnswerOnce() async {
        let (share, probe) = Self.share(caption: Self.vague)
        await share.enrich(session: Self.signedIn, read: { _ in
            await probe.read()
            return LinkPreview.Result(imageURL: URL(string: "https://example.com/cover.jpg"))
        }, judge: { _, _ in
            await probe.ask()
            return Self.skincare
        })
        XCTAssertEqual(probe.reads, 1)
        XCTAssertEqual(probe.asks, 1)
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

    @MainActor func testStrongEvidenceNeverAsksTheModel() async {
        // Sure from the share's own words.
        let (sure, sureProbe) = Self.share(caption: "Five hip mobility drills")
        await sure.enrich(session: Self.signedIn, read: { _ in
            await sureProbe.read()
            return nil
        }, judge: { _, _ in
            await sureProbe.ask()
            return Self.skincare
        })
        XCTAssertEqual(sureProbe.reads, 1)
        XCTAssertEqual(sureProbe.asks, 0)
        XCTAssertTrue(sureProbe.writes.isEmpty)

        // Sure once the page is read: what stays follows it, and takes the page along.
        let (read, readProbe) = Self.share(caption: Self.vague)
        await read.enrich(session: Self.signedIn, read: { _ in
            LinkPreview.Result(author: "@kaylawalks", description: "Five hip mobility drills #mobility")
        }, judge: { _, _ in
            await readProbe.ask()
            return Self.skincare
        })
        XCTAssertEqual(readProbe.asks, 0)
        XCTAssertEqual(read.model.revision, 1)
        XCTAssertEqual(readProbe.writes.count, 1)
        let kept = readProbe.writes.last
        XCTAssertEqual(kept?.categoryID, "fitness")
        XCTAssertEqual(kept?.subcategory, "Mobility")
        XCTAssertEqual(kept?.author, "@kaylawalks")
        XCTAssertEqual(kept?.previewFetched, true)

        // Sure once the page is read, but the dial was touched: what stays doesn't
        // move, and nothing marks the page read over a guess it contradicts.
        let (touched, touchedProbe) = Self.share(caption: Self.vague)
        touched.model.touch()
        await touched.enrich(session: Self.signedIn, read: { _ in
            LinkPreview.Result(description: "Five hip mobility drills #mobility")
        }, judge: { _, _ in
            await touchedProbe.ask()
            return Self.skincare
        })
        XCTAssertEqual(touchedProbe.asks, 0)
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
    var writes: [BookmarkDraft] = []

    func read() { reads += 1 }
    func ask() { asks += 1 }
}
