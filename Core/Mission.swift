import Foundation
import SwiftData

/// A thing you're trying to become.
///
/// JP's framing: *"you want to become a faster runner, you want to become a
/// better morning person, you want to run a faster marathon, you want to reduce
/// your injuries during your running training, you want to eat healthier."*
///
/// This is what turns borkmarkr from a filing cabinet into something you open on
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
        return "\(title) — a journey from borkmarkr\n\n\(body)"
    }

    /// A suggested journey, named from *their* library — not from a catalogue.
    struct Seed: Identifiable, Hashable {
        var id: String { (categoryID ?? "none") + "|" + title.lowercased() }
        var title: String
        var categoryID: String?
        var bookmarkIDs: [String]
        var blurb: String
    }

    /// Cluster the library into 2–3 journey names. Topic/subtopic piles only —
    /// we never invent a taxonomy of journeys. Existing journeys occupy a topic
    /// so we do not suggest a second "Get into Fitness".
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
            let title: String
            if let dominant, dominant.value * 2 >= unused.count {
                title = "Get into \(dominant.key.lowercased())"
            } else {
                title = "Get into \(topicName.lowercased())"
            }
            seeds.append(Seed(
                title: title,
                categoryID: topicID,
                bookmarkIDs: unused.map(\.id),
                blurb: "\(unused.count) \(Copy.borks(unused.count)) already in your library"
            ))
        }

        return seeds
            .sorted { $0.bookmarkIDs.count > $1.bookmarkIDs.count }
            .prefix(limit)
            .map { $0 }
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
