import Foundation
import Observation

/// The state of one Quick File dial: which seven topics sit on the ring, which
/// one is lit, and what has been filed.
///
/// **Seats.** The ring has eight 45° seats that never move. Seat 0, at 12
/// o'clock, is the best guess; seats 1–6 run clockwise in rank order; seat 7,
/// at 10:30, is More…. Turning clockwise from rank 7 lands on More…, and so
/// does turning anticlockwise from the best guess: "something else".
///
/// **Nothing moves under a thumb.** Any turn, press, tap or More freezes the
/// ring (`touched`). A late answer (`offer`) re-deals an untouched ring and
/// only annotates a touched one: a ✨ on a topic already there, or an "Also
/// likely" chip below for one that isn't. And a tap on the centre within 350
/// ms of the centre changing by itself files what was showing before the
/// change, because the thumb was already on its way down.
///
/// The model files nothing itself. `onConfirm` hands the choice to whoever
/// owns the save (the extension re-enqueues it, the app writes it), and
/// `onUndo` takes it back.
///
/// **Two modes.** `.once` is triage: one filing and the ring folds away.
/// `.refine` is the Add sheet and the share sheet: a filing *chooses*, the
/// ring stays live, and another topic re-chooses (`onConfirm` runs every
/// time). `filed` keeps its name in both; in `.refine` it is what has been
/// chosen. A subtopic chip changes only the subtopic (`toggleSubtopic`), and
/// a late answer after a choice never moves it: it may only add a ✨ and new
/// subtopic suggestions (`latest`).
@MainActor @Observable
final class QuickFileModel {

    enum Mode: Sendable {
        /// One tap files and folds the ring: triage.
        case once
        /// A tap chooses and the ring stays: Add and share.
        case refine
    }

    /// The eighth seat, at 10:30: the full topic list.
    static let moreSlot = 7
    /// A centre tap this soon after the centre changed by itself files what
    /// was showing before.
    static let changeGuard: TimeInterval = 0.35
    /// Selection ticks no closer together than this, so a fast spin purrs
    /// rather than buzzes.
    static let tickInterval: TimeInterval = 0.045
    /// Turning faster than six notches a second, the centre stops sliding.
    static let slideInterval: TimeInterval = 1.0 / 6

    private(set) var ranking: FilingRanking
    private(set) var input: FilingInput
    /// The lit seat: 0–6 a candidate by rank, `moreSlot` for More…, nil while
    /// nothing is chosen (no guess was strong enough to offer).
    private(set) var highlighted: Int?
    /// Any turn, press, tap or More has happened.
    private(set) var touched = false
    /// A late best guess that isn't on the frozen ring: "✨ Also likely".
    private(set) var aiChip: FilingCandidate?
    /// The ring topic a late answer agreed with. It wears a ✨.
    private(set) var sparkle: String?
    /// What was filed. Nil until then, and again after Undo. In `.refine`,
    /// what is chosen.
    private(set) var filed: FilingCandidate?
    /// The newest ranking a late answer offered, also after a choice, when
    /// `ranking` stays frozen. Its subtopics join `suggestedSubs`.
    private(set) var latest: FilingRanking
    let mode: Mode

    /// Bumps once per selection tick (rate-limited), confirm and undo, for
    /// `.sensoryFeedback`.
    private(set) var tick = 0
    private(set) var confirmations = 0
    private(set) var undos = 0
    /// Bumps when a choice changes only its subtopic.
    private(set) var refinements = 0
    /// The last turn's direction: 1 clockwise, -1 anticlockwise.
    private(set) var direction = 1
    /// False while turning faster than six notches a second.
    private(set) var slides = true
    /// Bumps when a late answer re-deals an untouched ring.
    private(set) var revision = 0
    /// What VoiceOver should say about the latest re-deal, if the centre changed.
    private(set) var updateAnnouncement: String?
    /// When a re-deal last moved the centre.
    private(set) var movedAt: Date?
    /// The model has been asked and hasn't answered. While the guess isn't
    /// sure without it, the share sheet waits a little for it before closing
    /// by itself (`QuickFileShareView.waitsForAnswer`).
    var isAsking = false

    @ObservationIgnored var onConfirm: (FilingCandidate) -> Void = { _ in }
    @ObservationIgnored var onMore: () -> Void = {}
    @ObservationIgnored var onUndo: (FilingCandidate) -> Void = { _ in }

    @ObservationIgnored private var lastTurn = Date.distantPast
    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var centreChange: (at: Date, before: FilingCandidate?)?
    /// The subtopic chips each topic has shown, so they never reorder.
    @ObservationIgnored private var shownSubs: [String: [String]] = [:]

    /// `chosen` starts a `.refine` dial already chosen, without calling
    /// `onConfirm`: a save you had already filed.
    init(ranking: FilingRanking, input: FilingInput, mode: Mode = .once, chosen: FilingCandidate? = nil) {
        self.ranking = ranking
        self.latest = ranking
        self.input = input
        self.mode = mode
        self.highlighted = Self.preselected(in: ranking)
        if mode == .refine, let chosen {
            filed = chosen
            touched = true
            highlighted = ranking.candidates.prefix(Self.moreSlot).firstIndex { $0.categoryID == chosen.categoryID }
        }
    }

    // MARK: Reading

    /// The ring's topics in rank order, at most seven.
    var candidates: [FilingCandidate] { Array(ranking.candidates.prefix(Self.moreSlot)) }

    func candidate(at seat: Int) -> FilingCandidate? {
        candidates.indices.contains(seat) ? candidates[seat] : nil
    }

    /// The lit candidate; nil on More… or when nothing is chosen.
    var centre: FilingCandidate? { highlighted.flatMap { candidate(at: $0) } }

    var isOnMore: Bool { highlighted == Self.moreSlot }

    /// Triage's filing: the ring has folded and nothing more is taken.
    var isFolded: Bool { mode == .once && filed != nil }

    /// Add or share, with a topic chosen: the refine panel is up.
    var isChosen: Bool { mode == .refine && filed != nil }

    /// What the hub shows. In `.refine` with a choice: the choice while the
    /// light is on its topic (or on nothing), otherwise whatever the light
    /// is on, nil on More….
    var shown: FilingCandidate? {
        guard let filed else { return centre }
        if mode == .once { return filed }
        guard let seat = highlighted else { return filed }
        if let lit = candidate(at: seat), lit.categoryID != filed.categoryID { return lit }
        return seat == Self.moreSlot ? nil : filed
    }

    /// The hub shows what is filed, so it wears the check.
    var showsCheck: Bool { filed != nil && shown?.categoryID == filed?.categoryID }

    /// The lit seat is the guess the ranking offered.
    var showsBestGuess: Bool { highlighted != nil && highlighted == ranking.preselect }

    /// "Filed by you": just filed here, or already filed by you before.
    var yours: Bool { filed != nil || ranking.candidates.first?.reasons.first == .yours }

    var header: String { QuickFileCopy.header(ranking, yours: yours) }

    func reason(for candidate: FilingCandidate) -> String? {
        QuickFileCopy.reason(candidate, input: input)
    }

    /// The ring's own candidate for a topic, re-filed under `subcategory`, or
    /// a bare one for a topic the ring doesn't hold (a pick from More…).
    func candidate(topicID: String, subcategory: String?) -> FilingCandidate {
        if var known = ranking.candidates.first(where: { $0.categoryID == topicID }) {
            known.subcategory = subcategory
            return known
        }
        return FilingCandidate(categoryID: topicID, subcategory: subcategory, score: 0, reasons: [],
                               altSubs: [], creator: nil, creatorPicks: 0, matched: nil)
    }

    /// The subtopics suggested for a topic: the ring's own candidate for it
    /// (its subtopic, then the others with evidence), then any a late answer
    /// added. Earlier entries never move, so new ones only append.
    func suggestedSubs(for topicID: String) -> [String] {
        var out: [String] = []
        for source in [ranking, latest] {
            guard let known = source.candidates.first(where: { $0.categoryID == topicID }) else { continue }
            for sub in [known.subcategory].compactMap({ $0 }) + known.altSubs
            where !out.contains(where: { $0.caseInsensitiveCompare(sub) == .orderedSame }) {
                out.append(sub)
            }
        }
        return out
    }

    /// A topic's subtopic chips in the order they were first shown, with any
    /// that `fresh` adds since at the end: chips never reorder under a thumb.
    func subtopicRow(for topicID: String, fresh: [String]) -> [String] {
        let shown = shownSubs[topicID] ?? []
        let row = shown.filter { fresh.contains($0) } + fresh.filter { !shown.contains($0) }
        if row != shown { shownSubs[topicID] = row }
        return row
    }

    /// The dial's VoiceOver value: "Fitness, Running, suggested, 1 of 7".
    var spokenValue: String {
        if let filed, mode == .once || showsCheck { return QuickFileCopy.filed(filed) }
        if filed != nil {
            guard let seat = highlighted, let candidate = candidate(at: seat) else { return QuickFileCopy.moreTopics }
            return "\(QuickFileCopy.spoken(candidate)), \(seat + 1) of \(candidates.count), \(QuickFileCopy.fileHereInstead)"
        }
        guard let seat = highlighted else { return QuickFileCopy.nothingChosen }
        guard let candidate = candidate(at: seat) else { return QuickFileCopy.moreTopics }
        var parts = [QuickFileCopy.spoken(candidate)]
        if seat == ranking.preselect { parts.append("suggested") }
        parts.append("\(seat + 1) of \(candidates.count)")
        return parts.joined(separator: ", ")
    }

    // MARK: Acting

    /// A finger is down on the dial. Freezes the ring before anything moves.
    func touch() {
        if !touched { touched = true }
    }

    /// Moves the light `notches` seats, clockwise when positive, wrapping
    /// through More…. From nothing, the first clockwise notch is the best
    /// guess and the first anticlockwise one is More….
    func turn(_ notches: Int) {
        guard !isFolded, notches != 0 else { return }
        touch()
        let seats = Array(candidates.indices) + [Self.moreSlot]
        let from = highlighted.flatMap { seats.firstIndex(of: $0) } ?? (notches > 0 ? -1 : seats.count)
        let to = ((from + notches) % seats.count + seats.count) % seats.count
        let now = Date()
        let turnDirection = notches > 0 ? 1 : -1
        if direction != turnDirection { direction = turnDirection }
        let sliding = now.timeIntervalSince(lastTurn) >= Self.slideInterval
        if slides != sliding { slides = sliding }
        lastTurn = now
        guard seats[to] != highlighted else { return }
        highlighted = seats[to]
        if now.timeIntervalSince(lastTick) >= Self.tickInterval {
            tick &+= 1
            lastTick = now
        }
    }

    /// A tap on a seat: lights it and files it in one go, or opens More….
    /// In `.refine`, a tap on the topic already chosen only lights it, so a
    /// subtopic set by a chip stays.
    func tap(_ seat: Int) {
        guard !isFolded else { return }
        touch()
        if seat == Self.moreSlot { return more() }
        guard let candidate = candidate(at: seat) else { return }
        if highlighted != seat { highlighted = seat }
        if isChosen, filed?.categoryID == candidate.categoryID { return }
        file(candidate)
    }

    /// Opens the full list.
    func more() {
        guard !isFolded else { return }
        touch()
        if highlighted != Self.moreSlot { highlighted = Self.moreSlot }
        onMore()
    }

    /// The centre: files what it shows. Nothing chosen, or More…, opens the
    /// full list instead.
    func confirm() {
        guard !isFolded else { return }
        if isChosen, showsCheck { return touch() }
        if let change = centreChange, Date().timeIntervalSince(change.at) < Self.changeGuard {
            centreChange = nil
            if let before = change.before { return file(before) }
            return more()
        }
        if let centre { file(centre) } else { more() }
    }

    /// Files `candidate`: tap 2. A chip, the full list and the "Also likely"
    /// chip all come through here. In `.refine` it (re-)chooses: the same
    /// topic and subtopic again is nothing, a new topic is a confirmation
    /// and a new subtopic of the same topic a refinement.
    func file(_ candidate: FilingCandidate) {
        guard !isFolded else { return }
        touch()
        guard mode == .refine else {
            filed = candidate
            confirmations &+= 1
            QuickFileSettings.noteFiled()
            return onConfirm(candidate)
        }
        let before = filed
        if before?.categoryID == candidate.categoryID, before?.subcategory == candidate.subcategory { return }
        filed = candidate
        let seat = candidates.firstIndex { $0.categoryID == candidate.categoryID }
        if highlighted != seat { highlighted = seat }
        if before?.categoryID == candidate.categoryID {
            refinements &+= 1
        } else {
            confirmations &+= 1
        }
        if before == nil { QuickFileSettings.noteFiled() }
        onConfirm(candidate)
    }

    /// A subtopic chip under a choice: sets that subtopic, or clears it when
    /// it is the one already set.
    func toggleSubtopic(_ name: String) {
        guard isChosen, let filed else { return }
        let same = filed.subcategory?.caseInsensitiveCompare(name) == .orderedSame
        file(candidate(topicID: filed.categoryID, subcategory: same ? nil : name))
    }

    /// Takes the filing back. The ring returns to the seat it was on.
    func undo() {
        guard let candidate = filed else { return }
        filed = nil
        undos &+= 1
        onUndo(candidate)
    }

    /// A late answer: the preview arrived, on-screen text was read, or the
    /// model replied. An untouched ring re-deals; a touched one stays exactly
    /// where it is and only gains a ✨ or an "Also likely" chip.
    func offer(_ next: FilingRanking, input: FilingInput? = nil) {
        if let input { self.input = input }
        if latest != next { latest = next }
        if isChosen {
            // Never moves a choice: a ✨ on another ring topic it prefers, at most.
            guard next.preselect != nil, let best = next.candidates.first,
                  best.categoryID != filed?.categoryID,
                  candidates.contains(where: { $0.categoryID == best.categoryID }) else { return }
            if sparkle != best.categoryID { sparkle = best.categoryID }
            return
        }
        guard filed == nil, next != ranking else { return }

        if !touched {
            let before = centre
            ranking = next
            highlighted = Self.preselected(in: next)
            aiChip = nil
            sparkle = nil
            let after = centre
            let moved = before?.categoryID != after?.categoryID || before?.subcategory != after?.subcategory
            let now = Date()
            centreChange = moved ? (now, before) : nil
            if moved { movedAt = now }
            updateAnnouncement = moved ? after.map(QuickFileCopy.updated) : nil
            revision &+= 1
            return
        }

        guard next.preselect != nil, let best = next.candidates.first else { return }
        let shown = ranking.candidates.first
        guard best.categoryID != shown?.categoryID || best.subcategory != shown?.subcategory else { return }
        if candidates.contains(where: { $0.categoryID == best.categoryID }) {
            sparkle = best.categoryID
            aiChip = nil
        } else {
            aiChip = best
            sparkle = nil
        }
    }

    private static func preselected(in ranking: FilingRanking) -> Int? {
        guard let seat = ranking.preselect, seat >= 0, seat < min(ranking.candidates.count, moreSlot) else { return nil }
        return seat
    }
}
