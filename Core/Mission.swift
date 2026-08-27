import Foundation
import SwiftData

/// A thing you're trying to become.
///
/// JP's framing: *"you want to become a faster runner, you want to become a
/// better morning person, you want to run a faster marathon, you want to reduce
/// your injuries during your running training, you want to eat healthier."*
///
/// This is what turns bookmarker from a filing cabinet into something you open on
/// purpose. A library is passive — you visit it when you remember something is
/// in there. A mission is active: it has a reason, it collects the brks that
/// serve it, and it asks you a question once a day.
///
/// Deliberately simple. A mission is a name, a topic tint, the brks you've
/// attached, and an optional daily habit. No sub-goals, no scheduling, no
/// streak-freeze economy — the moment this becomes a habit app it stops being a
/// bookmark app, and the whole value is that the two are connected.
@Model
final class Mission {
    @Attribute(.unique) var id: String
    var title: String
    /// Why it matters, in the user's own words. Shown on the mission card.
    var detail: String?
    var categoryID: String?

    /// Brk IDs attached to this mission. Stored as IDs rather than a relation so
    /// deleting a brk can't orphan or cascade into the mission.
    var bookmarkIDs: [String]

    /// Optional daily habit, e.g. "10 minutes of mobility".
    var habitName: String?
    /// Days the habit was completed, stored as start-of-day. A set of dates is
    /// enough for streaks and a calendar, and it can't drift out of sync with
    /// a separately-maintained counter.
    var completedDays: [Date]

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isArchived: Bool = false
    /// JSON-encoded `[QuestTodo]`. Optional so existing stores migrate.
    var todosJSON: String?

    init(title: String, detail: String? = nil, categoryID: String? = nil, habitName: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.detail = detail
        self.categoryID = categoryID
        self.bookmarkIDs = []
        self.habitName = habitName
        self.completedDays = []
        self.createdAt = .now
        self.updatedAt = .now
    }

    var topic: Topic? { Taxonomy.category(id: categoryID) }
    var hasHabit: Bool { !(habitName ?? "").isEmpty }

    var todos: [QuestTodo] {
        get {
            guard let data = todosJSON?.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([QuestTodo].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let text = String(data: data, encoding: .utf8) {
                todosJSON = text
            } else {
                todosJSON = nil
            }
            updatedAt = .now
        }
    }

    func summary(from bookmarks: [Bookmark]) -> String {
        let items = bookmarks.filter { bookmarkIDs.contains($0.id) }
        guard !items.isEmpty else {
            return "Nothing on this quest yet. Add a few borks and I’ll sum them up."
        }
        let subs = Dictionary(grouping: items.compactMap(\.subcategory)) { $0 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
            .map(\.key)
        let platforms = Dictionary(grouping: items) { $0.platform.name }
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
            .map(\.key)
        var line = "\(Copy.countedBorks(items.count)) on this quest"
        if let topic { line += ", filed under \(topic.name)" }
        if !subs.isEmpty { line += " — mostly \(subs.joined(separator: " and "))" }
        line += "."
        if !platforms.isEmpty {
            line += " Pulled from \(platforms.joined(separator: " and "))."
        }
        if let first = items.first?.displayTitle {
            line += " Starts with “\(first)”."
        }
        return line
    }

    // MARK: - Habit

    func isDone(on day: Date = .now, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        return completedDays.contains { calendar.isDate($0, inSameDayAs: target) }
    }

    func toggle(on day: Date = .now, calendar: Calendar = .current) {
        let target = calendar.startOfDay(for: day)
        if let index = completedDays.firstIndex(where: { calendar.isDate($0, inSameDayAs: target) }) {
            completedDays.remove(at: index)
        } else {
            completedDays.append(target)
        }
        updatedAt = .now
    }

    /// Consecutive days up to today. Counts back from *yesterday* when today
    /// isn't done yet, so an unfinished morning doesn't read as a broken streak
    /// — a streak that resets at midnight punishes people for being asleep.
    func streak(asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        guard !completedDays.isEmpty else { return 0 }
        let days = Set(completedDays.map { calendar.startOfDay(for: $0) })

        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Completions in the last `days` days — the honest measure when someone
    /// isn't aiming for a perfect run.
    func completions(inLast days: Int, asOf today: Date = .now, calendar: Calendar = .current) -> Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: today))
        else { return 0 }
        return completedDays.filter { $0 >= cutoff }.count
    }

    func attach(_ bookmarkID: String) {
        guard !bookmarkIDs.contains(bookmarkID) else { return }
        bookmarkIDs.append(bookmarkID)
        updatedAt = .now
    }

    func detach(_ bookmarkID: String) {
        bookmarkIDs.removeAll { $0 == bookmarkID }
        updatedAt = .now
    }

    func contains(_ bookmarkID: String) -> Bool {
        bookmarkIDs.contains(bookmarkID)
    }

    /// A journey goes quiet when nothing on it has been opened or saved recently.
    func isQuiet(among bookmarks: [Bookmark], days: Int = 14) -> Bool {
        let attached = bookmarks.filter { bookmarkIDs.contains($0.id) }
        guard attached.count >= 1 else { return false }
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now))
        else { return false }
        if createdAt > cutoff { return false }
        let lastTouch = attached.compactMap { $0.lastOpenedAt ?? $0.savedAt }.max() ?? createdAt
        return lastTouch < cutoff
    }

    func shareText(from bookmarks: [Bookmark]) -> String {
        let items = bookmarks.filter { bookmarkIDs.contains($0.id) }
        let lines = items.prefix(50).map { "• \($0.displayTitle)\n  \($0.urlString)" }
        let body = lines.isEmpty ? "Nothing attached yet." : lines.joined(separator: "\n\n")
        return "\(title) — a side quest from bookmarker\n\n\(body)"
    }

    /// A suggested side quest, named from *their* library — not a catalogue.
    struct Seed: Identifiable, Hashable {
        /// Stable across a title rewrite so a model rename does not remount the row.
        var id: String { categoryID ?? bookmarkIDs.sorted().joined() }
        var title: String
        var categoryID: String?
        var subcategory: String?
        var bookmarkIDs: [String]
        var sampleTitles: [String]
        var blurb: String
    }

    /// Cluster the library into a few side quests. Existing quests occupy a
    /// topic so we do not suggest a second pile for the same filing.
    static func suggested(from bookmarks: [Bookmark], existing: [Mission], limit: Int = 3) -> [Seed] {
        let live = bookmarks.filter { $0.deletedAt == nil }
        let takenTopics = Set(existing.compactMap(\.categoryID))
        let takenIDs = Set(existing.flatMap(\.bookmarkIDs))

        var byTopic: [String: [Bookmark]] = [:]
        for item in live {
            guard let id = item.categoryID else { continue }
            byTopic[id, default: []].append(item)
        }

        var seeds: [Seed] = []
        for (topicID, items) in byTopic {
            guard items.count >= 3, !takenTopics.contains(topicID) else { continue }
            let unused = items.filter { !takenIDs.contains($0.id) }
            guard unused.count >= 3 else { continue }

            let topicName = Taxonomy.category(id: topicID)?.name ?? "this"
            let subCounts = Dictionary(grouping: unused.compactMap(\.subcategory)) { $0 }.mapValues(\.count)
            let dominant = subCounts.max { $0.value < $1.value }
            let sub = (dominant.map { $0.value * 2 >= unused.count } == true) ? dominant?.key : nil
            let samples = unused.prefix(6).map(\.displayTitle)
            let title = draftTitle(topic: topicName, subcategory: sub, titles: samples)
            seeds.append(Seed(
                title: title,
                categoryID: topicID,
                subcategory: sub,
                bookmarkIDs: unused.map(\.id),
                sampleTitles: samples,
                blurb: Copy.suggestedQuestBlurb(
                    count: unused.count,
                    topic: sub ?? topicName,
                    samples: samples + [title]
                )
            ))
        }

        return seeds
            .sorted { $0.bookmarkIDs.count > $1.bookmarkIDs.count }
            .prefix(limit)
            .map { $0 }
    }

    /// Offline names. Never "Get into X" — that is a category, not a quest.
    static func draftTitle(topic: String, subcategory: String?, titles: [String]) -> String {
        let blob = (titles + [subcategory, topic].compactMap { $0 })
            .joined(separator: " ")
            .lowercased()

        func mentions(_ words: String...) -> Bool {
            words.contains { blob.contains($0) }
        }

        if mentions("conspirac", "cover-up", "unsolved", "rabbit") {
            return "Go down the rabbit hole"
        }
        if mentions("startup", "founder", "venture", "bootstrapp") {
            return "Explore starting a business"
        }
        if mentions("social strategy") || (mentions("marketing") && mentions("social", "instagram", "tiktok", "shorts")) {
            return "Marketing on socials"
        }
        if mentions("mobility", "hip", "hamstring", "stretch", "fascia") {
            if mentions("run", "marathon", "5k", "10k") { return "Improve mobility for running" }
            if mentions("football", "soccer") { return "Improve mobility for football" }
            if mentions("desk", "office") { return "Undo the desk stiffness" }
            return "Improve mobility"
        }
        if mentions("tendon", "achilles", "rehab") { return "Build tendon strength" }
        if mentions("pottery", "ceramic", "wheel") { return "Learn pottery" }
        if mentions("pencil", "charcoal", "drawing") { return "Get better at drawing" }
        if mentions("paint", "oil paint", "watercol") { return "Get better at painting" }

        if let subcategory {
            return phrase(for: subcategory)
        }
        return phrase(for: topic)
    }

    private static func phrase(for label: String) -> String {
        switch label.lowercased() {
        case "mobility", "stretching": return "Improve \(label.lowercased())"
        case "conspiracies": return "Go down the rabbit hole"
        case "startups": return "Explore starting a business"
        case "social strategy": return "Marketing on socials"
        case "strength", "hypertrophy": return "Get stronger"
        case "meal prep": return "Get meal prep going"
        case "running": return "Train for running"
        default:
            let lower = label.lowercased()
            if lower.hasSuffix("ing") { return "Get better at \(lower)" }
            return "Work on \(lower)"
        }
    }

    /// Suggestions offered when creating a mission — phrased the way people
    /// actually say them.
    static let templates: [(title: String, habit: String, categoryID: String)] = [
        ("Become a faster runner", "Run or drill", "fitness"),
        ("Run a marathon", "Training session", "fitness"),
        ("Stop getting injured", "Mobility work", "fitness"),
        ("Become a morning person", "Up before 6", "wellness"),
        ("Eat healthier", "Cook something real", "recipes"),
        ("Meal prep every week", "Prep a meal", "recipes"),
        ("Get stronger", "Lift", "fitness"),
        ("Sleep properly", "In bed by 10", "health"),
        ("Read more", "Read 10 pages", "books"),
        ("Grow my audience", "Post something", "creator"),
        ("Learn to cook properly", "Try a recipe", "recipes"),
        ("Be a better parent", "Phone away at dinner", "parenting"),
        ("Get my money in order", "Log spending", "money"),
        ("Deepen my faith", "Read scripture", "beliefs"),
        ("Build something", "Ship one thing", "business"),
    ]
}

/// A single checkbox on a side quest. Stored as JSON on `Mission`.
struct QuestTodo: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var done: Bool

    init(title: String, done: Bool = false) {
        self.id = UUID().uuidString
        self.title = title
        self.done = done
    }
}
