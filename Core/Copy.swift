import Foundation

/// User-facing wording, in one place.
///
/// A saved link is a **bork**. Not a "save", not a "bookmark" — the product
/// needs its own noun, and "1 save" reads like a verb every time. You bork
/// something, you've got 400 borks, you share a bork.
///
/// Centralised because renaming a core noun across a dozen screens by hand is
/// how you end up with three of them in the shipped build.
enum Copy {
    /// "bork" / "borks"
    static func borks(_ count: Int) -> String {
        count == 1 ? "bork" : "borks"
    }

    /// "1 bork" / "26 borks"
    static func countedBorks(_ count: Int) -> String {
        "\(count) \(borks(count))"
    }

    static let saveVerb = "Bork it"
    static let searchPlaceholder = "Search everything you've borked"

    /// The human noun for a Mission. Code stays `Mission` (schema).
    static func sideQuests(_ count: Int) -> String {
        count == 1 ? "side quest" : "side quests"
    }

    static func countedSideQuests(_ count: Int) -> String {
        "\(count) \(sideQuests(count))"
    }

    static let sideQuestWord = "side quest"
    static let newSideQuest = "New side quest"
    static let startSideQuest = "Start a side quest"
    static let startThisQuest = "Start this quest"
    static let whatWorkingOn = "What are you working on?"
    static let sideQuestsHeading = "Your side quests"
    static let fromYourLibrary = "From your library"

    /// Library insights card — a question, not a label.
    static let insightsQuestion = "What are you finding interesting?"
    static let insightsFallback = "Your week of borks, read back to you"

    /// The side-quest guide. Seb did not know what a side quest was, so every
    /// surface says the same thing in plain words: a topic files what a bork
    /// *is*, a quest is *why* you kept it.
    static let sideQuestOneLiner = "Topics file what a bork is. A side quest is why you kept it."
    static let sideQuestCoachLine = "Name a goal, pull in the borks that help, tick things off."
    static let howSideQuestsWork = "How side quests work"
    static let sideQuestExplainerHeading = "A side quest is\nwhy you kept it."
    static let sideQuestExplainerBody = "Topics file what a bork is — Fitness, Recipes, Money. A side quest is the goal behind the pile, and it can pull borks from any topic."
    static let sideQuestGuideSteps: [(title: String, detail: String)] = [
        ("Name a goal", "Become a faster runner. Decide on a van. Sleep properly. A quest is a reason, not another folder."),
        ("Pull in the borks that help", "From any topic — a reel, a thread and an article can sit on one quest."),
        ("Tick things off", "Add steps and tick them. Give it a daily habit only if the goal needs one."),
    ]
    static let tryOneOfThese = "TRY ONE OF THESE"
    static let sampleQuestCaption = "Tap to set it up"
    static let notNow = "Not now"

    /// THE THREAD, when the model has written it.
    static let suggestedSteps = "NEXT STEPS"
    static let suggestedStepsHint = "Tap + to put one on your to-do list."

    /// Persuasion under a suggested side quest. The title names the quest;
    /// this line is why you should start it.
    static func suggestedQuestBlurb(count: Int, topic: String?, samples: [String]) -> String {
        let n = countedBorks(count)
        let blob = (samples + [topic].compactMap { $0 }).joined(separator: " ").lowercased()
        if blob.contains("rabbit") || blob.contains("conspirac") || blob.contains("unsolved") {
            return "You're already \(n) deep. Keep the thread in one place."
        }
        if blob.contains("market") || blob.contains("social") || blob.contains("hook") || blob.contains("audience") {
            return "You've already saved the playbook — \(n) on hooks and timing. Don't leave them in a pile."
        }
        if blob.contains("startup") || blob.contains("business") || blob.contains("founder") {
            return "\(n) on starting up. Pick a thread before they go cold."
        }
        if blob.contains("run") || blob.contains("mobility") || blob.contains("stretch") {
            return "\(n) waiting to become a routine, not another saved stretch."
        }
        if let topic, !topic.isEmpty {
            return "You've already saved \(n) on \(topic.lowercased()). A side quest is how they stop being a pile."
        }
        return "You've already saved \(n). A side quest is how they stop being a pile."
    }
}
