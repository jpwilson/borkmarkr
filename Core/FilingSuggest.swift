import Foundation

/// What Quick File knows about the link it is asking about. `ocrText` is
/// on-screen text already passed through `FilingSuggest.cleanOCR`.
struct FilingInput: Sendable {
    var url: URL
    var title: String
    var text, description, author, ocrText: String?
}

/// One place on the dial: a topic, the subtopic it would be filed under, and
/// why it is there.
struct FilingCandidate: Codable, Sendable, Equatable, Identifiable {

    /// Why a topic is on the dial. A pin (`yours`, `guess`) always comes
    /// first; the rest are ordered by how many points each added, biggest
    /// first, ties in this declaration order.
    enum Reason: String, Codable, Sendable {
        case yours, guess, creator, domain, ai, hashtag, keyword, ocr, habit, starter
    }

    var categoryID: String
    var subcategory: String?
    var score: Int
    var reasons: [Reason]
    /// Up to three other subtopics with evidence, best first: the chips under
    /// the dial.
    var altSubs: [String]
    /// How the creator reads in the reason line, when your history with them
    /// helped put this topic here.
    var creator: String?
    /// How many times you filed this creator's posts under this topic.
    var creatorPicks: Int
    /// The word a reason line quotes: the heaviest keyword, hashtag or
    /// on-screen hit behind the first text reason.
    var matched: String?

    /// One entry per topic, so the topic is the identity.
    var id: String { categoryID }
}

struct FilingRanking: Codable, Sendable, Equatable {
    var candidates: [FilingCandidate]
    /// 0 when the first candidate should be highlighted and shown in the
    /// centre; nil when the dial asks instead.
    var preselect: Int?
    /// The header copy's three states, on the Categorizer's own threshold.
    var evidence: Categorizer.Suggestion.Evidence
}

/// A candidate that leads whatever it scores: the filing a save already has
/// (`yours`) or the guess stored for it (`guess`).
struct FilingPin: Sendable {
    var categoryID: String
    var subcategory: String?
    var reason: FilingCandidate.Reason
}

/// Quick File's ranking: which seven topics go on the dial, in what order, and
/// the one line that says why.
///
/// **Score per topic**, whole numbers only so the JS port
/// (`docs/filing-suggest.js`) lands on the same numbers:
///
///     keywords                      Categorizer.scores, as is
///   + on-screen text ÷ 2            capped at 13: never strong on its own
///   + AI                            high 28, medium 13
///   + 12 per pick of this creator   capped at 36
///   + 6 per pick of this website    capped at 18; web links only
///   + recency of your filings here  3 a week, 2 a month, 1 a year; capped at 6
///
/// **Order**: score, then your most recent filing there, then taxonomy order
/// (built-ins, then custom ids A–Z, as the caller passes `taxonomyOrder`). One
/// entry per topic. A pin leads; `Taxonomy.onboardingInterests` fill whatever
/// seats are left. A topic missing from `taxonomyOrder` (a custom topic since
/// deleted) never appears.
///
/// **Preselect** the first candidate when it is a pin, or when it has a reason
/// about this link (keyword, hashtag, on-screen text, creator, website, AI)
/// and scores 6 or more. **Evidence** is `.strong` at 14 or more with a reason
/// other than on-screen text or habit, `.thin` otherwise, `.none` when nothing
/// is preselected: the Categorizer's own threshold, so the header copy agrees
/// on both platforms.
enum FilingSuggest {

    static let ringSize = 7

    enum Weight {
        static let creatorPerPick = 12, creatorCap = 36
        static let domainPerPick = 6, domainCap = 18
        static let aiHigh = 28, aiMedium = 13
        static let ocrCap = 13
        static let habitCap = 6
        static let preselectFloor = 6
        static let strong = Categorizer.Suggestion.confidentScore
    }

    private static let evidential: Set<FilingCandidate.Reason> = [.keyword, .hashtag, .ocr, .creator, .domain, .ai]
    private static let aboutTheLink: Set<FilingCandidate.Reason> = [.keyword, .hashtag, .creator, .domain, .ai]

    /// Ranks the topics for `input`. Pure and synchronous; nothing waits on it.
    static func rank(
        _ input: FilingInput,
        memory: FilingMemory,
        ai: Categorizer.Suggestion? = nil,
        pinned: FilingPin? = nil,
        taxonomyOrder: [String] = Taxonomy.all.map(\.id),
        now: Date = .now,
        limit: Int = ringSize
    ) -> FilingRanking {
        let nowSeconds = FilingParity.seconds(now)
        var position: [String: Int] = [:]
        for (index, id) in taxonomyOrder.enumerated() where position[id] == nil { position[id] = index }

        var tallies: [String: Tally] = [:]
        for score in Categorizer.scores(url: input.url, title: input.title, text: input.text,
                                        description: input.description, author: input.author) {
            tallies[score.categoryID, default: Tally()].addKeyword(score)
        }
        if let ocr = input.ocrText, !ocr.isEmpty {
            for score in Categorizer.scores(url: nil, title: "", text: ocr) {
                tallies[score.categoryID, default: Tally()].addOCR(score)
            }
        }
        if let ai, let id = ai.categoryID, ai.score > 0 {
            tallies[id, default: Tally()].addAI(ai.evidence == .strong ? Weight.aiHigh : Weight.aiMedium,
                                                sub: ai.subcategory.flatMap { $0.isEmpty ? nil : $0 })
        }
        let creatorLabel = FilingKeys.creatorLabel(author: input.author, url: input.url)
        if let key = FilingKeys.creator(author: input.author, url: input.url) {
            for pick in memory.creators[key] ?? [] { tallies[pick.categoryID, default: Tally()].addCreator(pick) }
        }
        if let key = FilingKeys.domain(url: input.url) {
            for pick in memory.domains[key] ?? [] { tallies[pick.categoryID, default: Tally()].addDomain(pick) }
        }
        for habit in memory.habits {
            let weight = FilingMemory.recency(of: habit.recent, now: nowSeconds)
            guard weight > 0 else { continue }
            tallies[habit.categoryID, default: Tally()].addHabit(habit, weight: weight)
        }

        func candidate(_ id: String, _ tally: Tally, pin: FilingPin?) -> FilingCandidate {
            let subs = tally.rankedSubs
            var reasons = tally.reasons
            var sub = subs.first
            if let pin {
                reasons = [pin.reason] + reasons.filter { $0 != pin.reason }
                sub = pin.subcategory
            }
            return FilingCandidate(
                categoryID: id,
                subcategory: sub,
                score: tally.score,
                reasons: reasons,
                altSubs: Array(subs.filter { $0 != sub }.prefix(3)),
                creator: tally.creatorPicks > 0 ? creatorLabel : nil,
                creatorPicks: tally.creatorPicks,
                matched: tally.matched(for: reasons)
            )
        }

        var ranked: [(id: String, tally: Tally, position: Int)] = []
        for (id, tally) in tallies {
            guard let at = position[id], tally.score > 0 else { continue }
            ranked.append((id, tally, at))
        }
        ranked.sort { a, b in
            if a.tally.score != b.tally.score { return a.tally.score > b.tally.score }
            if a.tally.last != b.tally.last { return (a.tally.last ?? .min) > (b.tally.last ?? .min) }
            return a.position < b.position
        }

        var candidates: [FilingCandidate] = []
        var pinnedID: String?
        if let pinned, position[pinned.categoryID] != nil {
            let pin = FilingPin(categoryID: pinned.categoryID,
                                subcategory: pinned.subcategory.flatMap { $0.isEmpty ? nil : $0 },
                                reason: pinned.reason)
            candidates.append(candidate(pin.categoryID, tallies[pin.categoryID] ?? Tally(), pin: pin))
            pinnedID = pin.categoryID
        }
        for entry in ranked where entry.id != pinnedID {
            candidates.append(candidate(entry.id, entry.tally, pin: nil))
        }
        for id in Taxonomy.onboardingInterests
        where position[id] != nil && !candidates.contains(where: { $0.categoryID == id }) {
            candidates.append(FilingCandidate(categoryID: id, subcategory: nil, score: 0, reasons: [.starter],
                                              altSubs: [], creator: nil, creatorPicks: 0, matched: nil))
        }
        candidates = Array(candidates.prefix(max(0, limit)))

        guard let first = candidates.first else {
            return FilingRanking(candidates: [], preselect: nil, evidence: .none)
        }
        let pinnedLead = first.reasons.contains(.yours) || first.reasons.contains(.guess)
        let hasEvidence = first.reasons.contains(where: evidential.contains)
        let preselect: Int? = pinnedLead || (hasEvidence && first.score >= Weight.preselectFloor) ? 0 : nil
        let evidence: Categorizer.Suggestion.Evidence
        if preselect == nil {
            evidence = .none
        } else if first.score >= Weight.strong && first.reasons.contains(where: aboutTheLink.contains) {
            evidence = .strong
        } else {
            evidence = .thin
        }
        return FilingRanking(candidates: candidates, preselect: preselect, evidence: evidence)
    }

    /// The one line under the dial for `candidate`, from its first reason that
    /// has something to say. Nil for a starter.
    static func reasonLine(_ candidate: FilingCandidate, input: FilingInput) -> String? {
        for reason in candidate.reasons {
            switch reason {
            case .yours, .guess:
                continue
            case .creator:
                guard let name = candidate.creator, candidate.creatorPicks > 0 else { continue }
                return candidate.creatorPicks >= 2
                    ? "You filed \(name) here \(candidate.creatorPicks) times"
                    : "You filed \(name) here last time"
            case .hashtag:
                guard let word = candidate.matched else { continue }
                return "#\(word) in the caption"
            case .keyword:
                guard let word = candidate.matched else { continue }
                return "“\(word)” in the title"
            case .ocr:
                guard let word = candidate.matched else { continue }
                return "On-screen text says “\(word)”"
            case .ai:
                return "AI read the caption"
            case .domain:
                guard let domain = FilingKeys.domain(url: input.url) else { continue }
                return "You file \(domain) here"
            case .habit:
                return "One of your usual spots"
            case .starter:
                return nil
            }
        }
        return nil
    }

    /// Text recognised on a thumbnail, reduced to what might say what the post
    /// is about. Drops lines under 3 characters, lines that are only a handle,
    /// a number or a timestamp, and app furniture (log in, sign up, follow,
    /// original audio…); keeps the first copy of a repeated line; joins with
    /// newlines; stops at 400 characters. Under 8 characters left is nothing.
    static func cleanOCR(_ lines: [String]) -> String? {
        var kept: [String] = []
        var seen: Set<[UInt32]> = []
        for raw in lines {
            let line = FilingParity.trim(raw)
            guard line.unicodeScalars.count >= 3, !isLoneHandle(line), !isNumberish(line), !isFurniture(line),
                  seen.insert(line.unicodeScalars.map(\.value)).inserted
            else { continue }
            kept.append(line)
        }
        var scalars = Array(kept.joined(separator: "\n").unicodeScalars)
        if scalars.count > 400 { scalars = Array(scalars.prefix(400)) }
        let text = FilingParity.trim(String(String.UnicodeScalarView(scalars)))
        return text.unicodeScalars.count >= 8 ? text : nil
    }

    /// Interface text on social apps and login walls. Matched as whole words.
    static let furniture: [String] = [
        "log in", "login", "sign in", "signin", "sign up", "signup", "verify", "captcha",
        "cookie", "cookies", "open app", "open the app", "follow", "following", "followers",
        "subscribe", "subscribed", "original audio", "original sound", "liked by",
        "comment", "comments", "share", "shares",
    ]

    /// `@name` and nothing else.
    private static func isLoneHandle(_ line: String) -> Bool {
        let scalars = Array(line.unicodeScalars)
        guard scalars.count >= 2, scalars[0] == "@" else { return false }
        return scalars.dropFirst().allSatisfy { s in
            ("a"..."z").contains(s) || ("A"..."Z").contains(s) || ("0"..."9").contains(s) || s == "." || s == "_"
        }
    }

    /// Counts, times and dates: "1.2M", "12:34", "0:15 / 1:02", "2024-05-01",
    /// "3h", "2d ago", "45%".
    private static func isNumberish(_ line: String) -> Bool {
        var digits = 0
        var rest = String.UnicodeScalarView()
        for s in line.unicodeScalars {
            switch s {
            case "0"..."9": digits += 1
            case " ", ".", ",", ":", "/", "%", "+", "-": continue
            case "A"..."Z": rest.append(Unicode.Scalar(s.value + 32)!)
            default: rest.append(s)
            }
        }
        guard digits > 0 else { return false }
        var unit = String(rest)
        if unit.hasSuffix("ago") { unit.removeLast(3) }
        return ["", "k", "m", "b", "h", "d", "w", "y", "s", "x"].contains(unit)
    }

    private static func isFurniture(_ line: String) -> Bool {
        var words = " "
        var word = String.UnicodeScalarView()
        for s in line.unicodeScalars {
            switch s {
            case "a"..."z", "0"..."9": word.append(s)
            case "A"..."Z": word.append(Unicode.Scalar(s.value + 32)!)
            default:
                if !word.isEmpty { words += String(word) + " "; word = String.UnicodeScalarView() }
            }
        }
        if !word.isEmpty { words += String(word) + " " }
        return furniture.contains { words.contains(" \($0) ") }
    }

    // MARK: - Tally

    /// Everything one topic collected, and what it adds up to.
    private struct Tally {
        var keyword = 0
        var keywordLabel: String?
        var fromHashtag = false
        var ocr = 0
        var ocrLabel: String?
        var ai = 0
        var creatorPicks = 0
        var domainPicks = 0
        var habit = 0
        /// Your most recent filing here, in seconds.
        var last: Int?
        var subs: [String: (score: Int, last: Int?)] = [:]

        var creatorPoints: Int { min(Weight.creatorCap, Weight.creatorPerPick * creatorPicks) }
        var domainPoints: Int { min(Weight.domainCap, Weight.domainPerPick * domainPicks) }
        var ocrPoints: Int { min(Weight.ocrCap, ocr / 2) }
        var habitPoints: Int { min(Weight.habitCap, habit) }
        var score: Int { keyword + ocrPoints + ai + creatorPoints + domainPoints + habitPoints }

        mutating func addKeyword(_ s: Categorizer.CategoryScore) {
            keyword = s.score
            keywordLabel = s.label
            fromHashtag = s.fromHashtag
            if let sub = s.subcategory { credit(sub, s.subWeight, at: nil) }
        }

        mutating func addOCR(_ s: Categorizer.CategoryScore) {
            ocr = s.score
            ocrLabel = s.label
            if let sub = s.subcategory { credit(sub, s.subWeight / 2, at: nil) }
        }

        mutating func addAI(_ points: Int, sub: String?) {
            ai = points
            if let sub { credit(sub, points, at: nil) }
        }

        mutating func addCreator(_ pick: FilingMemory.Pick) {
            creatorPicks += pick.count
            saw(pick.last)
            if let sub = pick.subcategory { credit(sub, Weight.creatorPerPick * pick.count, at: pick.last) }
        }

        mutating func addDomain(_ pick: FilingMemory.Pick) {
            domainPicks += pick.count
            saw(pick.last)
            if let sub = pick.subcategory { credit(sub, Weight.domainPerPick * pick.count, at: pick.last) }
        }

        mutating func addHabit(_ habit: FilingMemory.Habit, weight: Int) {
            self.habit += weight
            saw(habit.recent.first)
            if let sub = habit.subcategory { credit(sub, min(Weight.habitCap, weight), at: habit.recent.first) }
        }

        private mutating func saw(_ at: Int?) {
            if let at, at > (last ?? .min) { last = at }
        }

        private mutating func credit(_ sub: String, _ points: Int, at: Int?) {
            guard points > 0 else { return }
            var entry = subs[sub] ?? (score: 0, last: nil)
            entry.score += points
            if let at, at > (entry.last ?? .min) { entry.last = at }
            subs[sub] = entry
        }

        /// Each reason with points, biggest first, ties in declaration order.
        var reasons: [FilingCandidate.Reason] {
            let parts: [(reason: FilingCandidate.Reason, points: Int)] = [
                (.creator, creatorPoints), (.domain, domainPoints), (.ai, ai),
                (fromHashtag ? .hashtag : .keyword, keyword), (.ocr, ocrPoints), (.habit, habitPoints),
            ]
            return parts.enumerated()
                .filter { $0.element.points > 0 }
                .sorted { a, b in
                    a.element.points != b.element.points ? a.element.points > b.element.points : a.offset < b.offset
                }
                .map(\.element.reason)
        }

        /// Subtopics with evidence: most points, then your most recent filing
        /// there, then A–Z.
        var rankedSubs: [String] {
            subs.sorted { a, b in
                if a.value.score != b.value.score { return a.value.score > b.value.score }
                if a.value.last != b.value.last { return (a.value.last ?? .min) > (b.value.last ?? .min) }
                return FilingParity.less(a.key, b.key)
            }
            .map(\.key)
        }

        func matched(for reasons: [FilingCandidate.Reason]) -> String? {
            for reason in reasons {
                switch reason {
                case .hashtag, .keyword: return keywordLabel
                case .ocr: return ocrLabel
                default: continue
                }
            }
            return nil
        }
    }
}
