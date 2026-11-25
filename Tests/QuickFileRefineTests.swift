import XCTest
import SwiftData
@testable import borkmarkr

/// Quick File's "pick, refine, done": the dial in `.refine` mode, the tags
/// the panel toggles, Done's drain, the share session's writes, the snapshot
/// fields and `Store.save`'s `tagsRemoved` merge.
@MainActor
final class QuickFileRefineTests: XCTestCase {

    // MARK: The model

    func testAChoiceStaysLiveAndReChooses() {
        let (model, confirmed) = Self.dial()
        model.tap(0)
        XCTAssertEqual(model.filed?.categoryID, "fitness")
        XCTAssertTrue(model.isChosen)
        XCTAssertFalse(model.isFolded)
        XCTAssertTrue(model.showsCheck)
        XCTAssertEqual(model.confirmations, 1)

        // The same topic again, on its key or the centre: nothing written.
        model.tap(0)
        model.confirm()
        XCTAssertEqual(confirmed.calls.count, 1)

        // Turning away shows another topic without the check; the centre
        // then chooses it.
        model.turn(1)
        XCTAssertEqual(model.shown?.categoryID, "recipes")
        XCTAssertFalse(model.showsCheck)
        XCTAssertEqual(model.filed?.categoryID, "fitness")
        model.confirm()
        XCTAssertEqual(model.filed?.categoryID, "recipes")
        XCTAssertTrue(model.showsCheck)
        XCTAssertEqual(model.confirmations, 2)
        XCTAssertEqual(confirmed.calls.map(\.categoryID), ["fitness", "recipes"])

        // More… still opens after a choice, and a pick off the ring chooses.
        model.more()
        XCTAssertTrue(model.isOnMore)
        XCTAssertNil(model.shown)
        model.file(model.candidate(topicID: "money", subcategory: "Budgeting"))
        XCTAssertEqual(model.filed?.categoryID, "money")
        XCTAssertTrue(model.showsCheck)
    }

    func testASubtopicChipSetsAndClears() {
        let (model, confirmed) = Self.dial()
        model.toggleSubtopic("Running")
        XCTAssertTrue(confirmed.calls.isEmpty, "no subtopic before a choice")
        model.tap(0)
        model.toggleSubtopic("Running")
        XCTAssertEqual(model.filed?.subcategory, "Running")
        XCTAssertEqual(model.refinements, 1)
        XCTAssertEqual(model.confirmations, 1)
        model.toggleSubtopic("running")
        XCTAssertNil(model.filed?.subcategory)
        XCTAssertEqual(model.refinements, 2)
        XCTAssertEqual(confirmed.calls.map(\.subcategory), [nil, "Running", nil])

        // A tap on the chosen topic's key keeps the subtopic a chip set.
        model.toggleSubtopic("Yoga")
        model.tap(0)
        XCTAssertEqual(model.filed?.subcategory, "Yoga")
    }

    func testALateAnswerNeverMovesAChoiceAndOnlyAppendsSubtopics() {
        let (model, _) = Self.dial()
        model.tap(0)
        let before = model.suggestedSubs(for: "fitness")
        let row = model.subtopicRow(for: "fitness", fresh: ["Mobility", "Running", "Yoga"])

        var later = Self.ranking
        later.candidates[1].altSubs = ["Pasta"]
        later.candidates.swapAt(0, 1)
        later.candidates[1].altSubs = ["Mobility", "Stretching"]
        model.offer(later)
        XCTAssertEqual(model.filed?.categoryID, "fitness")
        XCTAssertEqual(model.highlighted, 0)
        XCTAssertEqual(model.sparkle, "recipes")
        XCTAssertNil(model.aiChip)
        XCTAssertEqual(Array(model.suggestedSubs(for: "fitness").prefix(before.count)), before)
        XCTAssertTrue(model.suggestedSubs(for: "fitness").contains("Stretching"))
        XCTAssertEqual(model.subtopicRow(for: "fitness", fresh: ["Stretching", "Yoga", "Running", "Mobility"]),
                       row + ["Stretching"])
    }

    func testASaveYouFiledOpensChosenWithoutWriting() {
        var mine = Self.ranking.candidates[1]
        mine.subcategory = "Pasta"
        let model = QuickFileModel(ranking: Self.ranking, input: Self.input, mode: .refine, chosen: mine)
        let confirmed = Calls()
        model.onConfirm = { confirmed.calls.append($0) }
        XCTAssertTrue(model.isChosen)
        XCTAssertEqual(model.highlighted, 1)
        XCTAssertEqual(model.shown?.subcategory, "Pasta")
        XCTAssertEqual(model.confirmations, 0)
        XCTAssertTrue(confirmed.calls.isEmpty)

        // Triage ignores it and still folds after one filing.
        let triage = QuickFileModel(ranking: Self.ranking, input: Self.input, chosen: mine)
        XCTAssertNil(triage.filed)
        triage.tap(0)
        XCTAssertTrue(triage.isFolded)
        triage.turn(1)
        triage.tap(1)
        XCTAssertEqual(triage.filed?.categoryID, "fitness")
        XCTAssertEqual(triage.highlighted, 0)
    }

    // MARK: Tags

    func testTagsToggleAddAndSuggest() {
        let tags = QuickFileTags(chosen: ["run"], suggested: ["run", "TikTok"])
        var changes = 0
        tags.onChange = { changes += 1 }
        XCTAssertEqual(tags.suggested, ["run"], "site names never suggested")

        XCTAssertTrue(tags.suggest(["cardio", "instagram"]))
        XCTAssertEqual(tags.chosen, ["run", "cardio"])
        XCTAssertEqual(changes, 0, "a suggestion is not the person's")

        tags.toggle("run")
        XCTAssertEqual(tags.chosen, ["cardio"])
        XCTAssertEqual(tags.removed, ["run"])
        XCTAssertTrue(tags.edited)
        XCTAssertEqual(changes, 1)

        // Edited: suggestions are offered, never turned on.
        XCTAssertFalse(tags.suggest(["tempo"]))
        XCTAssertEqual(tags.suggested, ["run", "cardio", "tempo"])
        XCTAssertEqual(tags.chosen, ["cardio"])

        XCTAssertTrue(tags.add("  #Run "))
        XCTAssertEqual(tags.chosen, ["cardio", "run"])
        XCTAssertTrue(tags.removed.isEmpty)
        XCTAssertFalse(tags.add("##"))
        XCTAssertFalse(tags.add("RUN"))

        tags.draft = "Long  run"
        tags.commitDraft()
        XCTAssertEqual(tags.chosen.last, "long run")
        XCTAssertEqual(tags.draft, "")
        XCTAssertEqual(changes, 3)
    }

    // MARK: Done's drain

    func testTheDrainStartsOnceAndAnyTouchStopsItForGood() {
        let t0 = Date()
        var drain = QuickFileDrain()
        drain.touched()
        XCTAssertFalse(drain.stoppedForGood, "the touch that chooses doesn't count")
        drain.chose(at: t0, assistive: false)
        XCTAssertTrue(drain.isDraining)
        XCTAssertFalse(drain.isDue(at: t0.addingTimeInterval(5)))
        XCTAssertTrue(drain.isDue(at: t0.addingTimeInterval(6)))
        drain.chose(at: t0.addingTimeInterval(3), assistive: false)
        XCTAssertEqual(drain.startedAt, t0, "a later choice doesn't restart it")

        drain.touched()
        XCTAssertFalse(drain.isDraining)
        drain.chose(at: t0.addingTimeInterval(8), assistive: false)
        XCTAssertFalse(drain.isDraining, "stopped for good")

        var assisted = QuickFileDrain()
        assisted.chose(at: t0, assistive: true)
        XCTAssertFalse(assisted.isDraining)

        var yours = QuickFileDrain(alreadyChosen: true)
        yours.chose(at: t0, assistive: false)
        XCTAssertFalse(yours.isDraining)
    }

    // MARK: The share session

    func testShareWritesCarryTheChoiceAndTheTagsTurnedOff() {
        var writes: [BookmarkDraft] = []
        let saved = BookmarkDraft.handedOver(url: URL(string: "https://www.instagram.com/reel/DAbc123xyz/")!,
                                             caption: "she does this every morning")
        let share = QuickFileShareSession(saved: saved, snapshot: nil) { writes.append($0) }
        let start = writes.count

        share.model.file(share.model.candidate(topicID: "fitness", subcategory: nil))
        share.model.toggleSubtopic("Running")
        XCTAssertEqual(writes.count - start, 2)
        XCTAssertEqual(writes.last?.subcategory, "Running")
        XCTAssertEqual(writes.last?.filingSource, "user")
        XCTAssertNil(writes.last?.tagsEdited)

        share.tags.add("tempo")
        share.tags.toggle("tempo")
        XCTAssertEqual(writes.last?.tagsEdited, true)
        XCTAssertEqual(writes.last?.tagsRemoved, ["tempo"])
        XCTAssertFalse(writes.last?.tags.contains("tempo") ?? true)

        // A tag still in the field is kept as the sheet closes, then nothing more.
        share.tags.draft = "morning"
        let beforeClose = writes.count
        share.close()
        XCTAssertEqual(writes.count, beforeClose + 1)
        XCTAssertEqual(writes.last?.tags.contains("morning"), true)
        share.model.toggleSubtopic("Yoga")
        XCTAssertEqual(writes.count, beforeClose + 1)
    }

    // MARK: Snapshot and store

    func testASnapshotFromAnOlderAppStillReads() throws {
        let old = #"{"version":1,"memory":\#(String(data: try JSONEncoder().encode(FilingMemory.empty), encoding: .utf8)!),"customTopics":[],"customSubs":{}}"#
        let snapshot = try JSONDecoder().decode(FilingSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snapshot.subUse)
        XCTAssertNil(snapshot.recentTags)

        let fresh = FilingSnapshot(memory: .empty, customTopics: [], customSubs: [:],
                                   subUse: ["fitness": ["Running"]], recentTags: ["fitness\u{1F}": ["tempo"]])
        let back = try JSONDecoder().decode(FilingSnapshot.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(back.subUse?["fitness"], ["Running"])
        XCTAssertEqual(back.recentTags?["fitness\u{1F}"], ["tempo"])
    }

    func testTagsTurnedOffOnTheShareSheetComeOffTheBork() throws {
        let container = try ModelContainer(for: Bookmark.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let url = URL(string: "https://example.com/post")!
        var first = BookmarkDraft(url: url, title: "Post", author: nil, platform: nil, kind: nil,
                                  categoryID: "fitness", subcategory: nil, tags: ["mine", "run"])
        first.tagsEdited = true
        try Store.save(first, in: context)

        var share = BookmarkDraft(url: url, title: "Post", author: nil, platform: nil, kind: nil,
                                  categoryID: "fitness", subcategory: nil, tags: ["tempo"])
        share.tagsEdited = true
        share.tagsRemoved = ["run"]
        let bork = try Store.save(share, in: context)
        XCTAssertEqual(bork.tags, ["mine", "tempo"])
        XCTAssertEqual(bork.tagsEdited, true)

        // Without the list, an edit still replaces them, as before.
        var app = share
        app.tagsRemoved = nil
        app.tags = ["only"]
        XCTAssertEqual(try Store.save(app, in: context).tags, ["only"])
    }

    // MARK: Fixtures

    private static let input = FilingInput(url: URL(string: "https://example.com/p")!, title: "A post",
                                           text: nil, description: nil, author: nil, ocrText: nil)

    private static let ranking = FilingRanking(candidates: [
        candidate("fitness", alt: ["Running", "Mobility"]),
        candidate("recipes", alt: ["Meal prep"]),
        candidate("money", alt: []),
    ], preselect: 0, evidence: .strong)

    private static func candidate(_ id: String, alt: [String]) -> FilingCandidate {
        FilingCandidate(categoryID: id, subcategory: nil, score: 10, reasons: [.keyword], altSubs: alt,
                        creator: nil, creatorPicks: 0, matched: nil)
    }

    private static func dial() -> (QuickFileModel, Calls) {
        let model = QuickFileModel(ranking: ranking, input: input, mode: .refine)
        let calls = Calls()
        model.onConfirm = { calls.calls.append($0) }
        return (model, calls)
    }
}

@MainActor
private final class Calls {
    var calls: [FilingCandidate] = []
}
