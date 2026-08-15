import Foundation

/// Reads the last day / week / month of borks and says what is interesting.
///
/// Offline first: topic counts and a short headline from the pile. If the
/// user is signed in, Claude Sonnet 5 via the `insights` Edge Function
/// (OpenRouter, key on the server) rewrites that into a sharper read.
@MainActor
enum SmartInsights {

    enum Window: String, CaseIterable, Identifiable, Sendable {
        case day, week, month
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            }
        }
        var label: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            case .month: "Month"
            }
        }
        var prompt: String {
            switch self {
            case .day: "today"
            case .week: "this week"
            case .month: "this month"
            }
        }
    }

    struct Theme: Identifiable, Sendable, Hashable {
        var id: String { name }
        var name: String
        var count: Int
        var why: String
    }

    struct Report: Sendable {
        var headline: String
        var summary: String
        var spike: String?
        var themes: [Theme]
        var suggestedQuest: String?
        var count: Int
        var fromModel: Bool
    }

    private struct RequestItem: Encodable {
        var title: String
        var topic: String?
        var subtopic: String?
        var platform: String
        var tags: [String]
    }

    private struct Request: Encodable {
        var window: String
        var items: [RequestItem]
    }

    private struct Remote: Decodable {
        var headline: String?
        var summary: String?
        var spike: String?
        var themes: [RemoteTheme]?
        var suggestedQuest: String?
    }

    private struct RemoteTheme: Decodable {
        var name: String?
        var count: Int?
        var why: String?
    }

    static func slice(_ bookmarks: [Bookmark], window: Window, now: Date = .now) -> [Bookmark] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(window.days - 1), to: start) ?? start
        return bookmarks.filter { $0.deletedAt == nil && $0.savedAt >= cutoff }
    }

    /// Instant, no network. Used signed-out and as the fallback.
    static func offline(_ items: [Bookmark], window: Window) -> Report {
        guard !items.isEmpty else {
            return Report(
                headline: "Quiet \(window.prompt)",
                summary: "Nothing new in this window. The interesting part starts when the pile grows.",
                spike: nil,
                themes: [],
                suggestedQuest: nil,
                count: 0,
                fromModel: false
            )
        }

        let topicGroups = Dictionary(grouping: items) { $0.category?.name ?? "Not filed yet" }
        let ranked = topicGroups
            .map { Theme(name: $0.key, count: $0.value.count, why: "\(Copy.countedBorks($0.value.count)) saved") }
            .sorted { $0.count > $1.count }

        let top = ranked.first
        let platforms = Dictionary(grouping: items) { $0.platform.name }.mapValues(\.count)
        let topApp = platforms.max { $0.value < $1.value }?.key

        let headline: String
        if let top, top.count >= 3 {
            headline = "\(top.name) is the thread \(window.prompt)"
        } else {
            headline = "\(items.count) new \(Copy.borks(items.count)) \(window.prompt)"
        }

        var summary = "You saved \(Copy.countedBorks(items.count))"
        if let top { summary += ", mostly \(top.name.lowercased())" }
        if let topApp { summary += ", a lot of it from \(topApp)" }
        summary += "."

        let samples = items.prefix(4).map(\.displayTitle)
        let quest: String?
        if let top, let sample = items.first(where: { ($0.category?.name ?? "") == top.name }) {
            quest = Mission.draftTitle(
                topic: top.name,
                subcategory: sample.subcategory,
                titles: samples
            )
        } else {
            quest = nil
        }

        return Report(
            headline: headline,
            summary: summary,
            spike: ranked.count > 1 && (ranked.first?.count ?? 0) >= 3
                ? "\(ranked[0].name) outpaced everything else."
                : nil,
            themes: Array(ranked.prefix(4)),
            suggestedQuest: quest,
            count: items.count,
            fromModel: false
        )
    }

    static func analyze(
        _ bookmarks: [Bookmark],
        window: Window,
        session: Supabase.Session?
    ) async -> Report {
        let items = slice(bookmarks, window: window)
        let fallback = offline(items, window: window)
        guard let session, Supabase.isConfigured, !items.isEmpty else { return fallback }

        let payload = Request(
            window: window.rawValue,
            items: items.prefix(40).map { item in
                RequestItem(
                    title: String(item.displayTitle.prefix(120)),
                    topic: item.category?.name,
                    subtopic: item.subcategory,
                    platform: item.platform.name,
                    tags: Array(item.tags.prefix(4))
                )
            }
        )

        guard
            let body = try? JSONEncoder().encode(payload),
            let data = try? await Supabase.invoke(
                function: "insights", bodyJSON: body, session: session, timeout: 25
            ),
            let remote = try? JSONDecoder().decode(Remote.self, from: data),
            let headline = remote.headline, !headline.isEmpty
        else { return fallback }

        let themes = (remote.themes ?? []).compactMap { row -> Theme? in
            guard let name = row.name, !name.isEmpty else { return nil }
            return Theme(name: name, count: row.count ?? 0, why: row.why ?? "")
        }

        return Report(
            headline: headline,
            summary: remote.summary ?? fallback.summary,
            spike: remote.spike,
            themes: themes.isEmpty ? fallback.themes : themes,
            suggestedQuest: remote.suggestedQuest,
            count: items.count,
            fromModel: true
        )
    }
}
