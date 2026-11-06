import Foundation

/// Every line Quick File says, in one place, so the share sheet, the Add
/// sheet, triage and VoiceOver all say the same thing.
///
/// The header keeps the four states both platforms already use (DECISIONS,
/// "Sorted for you"), with the guess now asking to be *turned*. The reason
/// line is `FilingSuggest.reasonLine`, which the web port says word for word.
enum QuickFileCopy {
    static let saved = "Saved to bookmarker"
    static let notNow = "Not now"
    static let notNowHint = "Keeps our guess. You can sort it later in bookmarker."
    static let undo = "Undo"
    static let done = "Done"
    static let dialLabel = "Topic"
    static let turnToChoose = "Turn to choose"
    static let tapToFile = "Tap to file"
    static let moreTopics = "More topics"
    static let moreSubtitle = "Every topic"
    static let moreReason = "Search every topic"
    static let nothingChosen = "Nothing chosen yet. Swipe up or down to choose"
    static let chooseHint = "Turn the dial, or tap a topic"
    static let allTopics = "All topics"
    static let searchPrompt = "Search topics and subtopics"

    static func topicName(_ topicID: String) -> String {
        Taxonomy.category(id: topicID)?.name ?? topicID
    }

    /// The letter on a topic's colour disc when it has no picture.
    static func initial(_ topicID: String) -> String {
        String(topicName(topicID).prefix(1)).uppercased()
    }

    /// "Fitness › Running", or "Fitness".
    static func label(_ candidate: FilingCandidate) -> String {
        let name = topicName(candidate.categoryID)
        return candidate.subcategory.map { "\(name) › \($0)" } ?? name
    }

    /// "Fitness, Running": the label as VoiceOver should read it.
    static func spoken(_ candidate: FilingCandidate) -> String {
        let name = topicName(candidate.categoryID)
        return candidate.subcategory.map { "\(name), \($0)" } ?? name
    }

    static func header(_ ranking: FilingRanking, yours: Bool) -> String {
        if yours { return "Filed by you" }
        switch ranking.evidence {
        case .strong: return "Sorted for you"
        case .thin: return "Our best guess — turn to change"
        case .none: return "Where does this go?"
        }
    }

    static func headerSymbol(_ ranking: FilingRanking, yours: Bool) -> String {
        if yours { return "checkmark.circle" }
        switch ranking.evidence {
        case .strong: return "sparkles"
        case .thin: return "sparkle"
        case .none: return "questionmark.circle"
        }
    }

    /// The one line under the dial: "You filed @kaylawalks here 3 times".
    static func reason(_ candidate: FilingCandidate, input: FilingInput) -> String? {
        FilingSuggest.reasonLine(candidate, input: input)
    }

    /// The glyph for whichever reason `reason` speaks to. It walks the reasons
    /// with the same skips as `FilingSuggest.reasonLine`, so the two agree.
    static func reasonSymbol(_ candidate: FilingCandidate, input: FilingInput) -> String? {
        for reason in candidate.reasons {
            switch reason {
            case .yours, .guess: continue
            case .creator:
                guard candidate.creator != nil, candidate.creatorPicks > 0 else { continue }
                return "person.crop.circle"
            case .hashtag:
                guard candidate.matched != nil else { continue }
                return "number"
            case .keyword:
                guard candidate.matched != nil else { continue }
                return "text.quote"
            case .ocr:
                guard candidate.matched != nil else { continue }
                return "text.viewfinder"
            case .ai: return "sparkles"
            case .domain:
                guard FilingKeys.domain(url: input.url) != nil else { continue }
                return "globe"
            case .habit: return "clock.arrow.circlepath"
            case .starter: return nil
            }
        }
        return nil
    }

    static func filed(_ candidate: FilingCandidate) -> String { "Filed to \(label(candidate))" }

    static func alsoLikely(_ candidate: FilingCandidate) -> String { "Also likely: \(label(candidate))" }

    static func just(_ topicID: String) -> String { "Just \(topicName(topicID))" }

    static func fileUnder(_ topicID: String, _ subcategory: String?) -> String {
        let name = topicName(topicID)
        return subcategory.map { "File under \(name), \($0)" } ?? "File under \(name)"
    }

    static func updated(_ candidate: FilingCandidate) -> String { "Suggestion updated: \(spoken(candidate))" }
}
