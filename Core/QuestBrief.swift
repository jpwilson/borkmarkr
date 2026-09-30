import Foundation

/// The paragraph under THE THREAD on a side quest, written by the model.
///
/// `Mission.summary(from:)` is a template: it counts the borks and names the
/// topic, and with nothing attached it says "Nothing on this quest yet".
/// Seb's breathing quest showed exactly that and read as *no summary at all*.
/// This is the second pass: the `quest-brief` Edge Function (Claude Sonnet 5
/// via OpenRouter, key on the server) reads the quest's name, its topic, the
/// saved excerpts on it — maybe none yet — and the steps already written, and says
/// what the quest is about in the product's voice plus three next actions.
///
/// **The key is not in this app.** Same contract as `SmartNamer` and
/// `TopicArt`: the user's JWT authenticates. Generation is nonblocking and
/// failures have visible retry states. Private notes and URLs are not sent.
///
/// Pure Foundation apart from the one `Supabase.invoke`, so the shaping and
/// the staleness rule run under `swiftc` in `Scripts/test_quest_brief.swift`.
enum QuestBrief {

    /// What is sent: capped captured excerpts, titles, source IDs and steps.
    /// Never private notes or URLs. Source IDs link back locally.
    static let maxTitles = 12
    static let maxTodos = 8
    static let maxField = 140

    /// What is kept. Two sentences is the brief; anything longer is the
    /// model ignoring the instruction, and gets cut rather than shown.
    static let maxSummary = 320
    static let maxSteps = 3
    static let maxStep = 80

    /// A brief goes stale when the pile changes or a week passes. The count
    /// is the signal, not the ids: reordering does not change what the quest
    /// is about, and re-asking on every attach would spend a call per tap.
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60

    struct Request: Encodable, Equatable {
        struct Source: Encodable, Equatable {
            var id: String
            var title: String
            var text: String
        }
        struct Todo: Encodable, Equatable {
            var title: String
            var done: Bool
        }

        var id: String
        var title: String
        var topic: String?
        var subtopic: String?
        var titles: [String]
        var todos: [Todo]
        var sources: [Source] = []
    }

    struct Brief: Codable, Equatable {
        var summary: String
        var steps: [String]
        var source_ids: [String]? = nil
        var basis: String? = nil
        var version: Int? = nil
        var inputKey: String? = nil
    }

    // MARK: - Shaping

    /// Clamps every field and drops blanks. Nil when there is no title to
    /// write about — the function would refuse it anyway, so don't spend
    /// the round trip.
    static func request(
        id: String,
        title: String,
        topic: String?,
        subtopic: String?,
        titles: [String],
        todos: [Request.Todo],
        sources: [Request.Source] = []
    ) -> Request? {
        let name = clamp(title)
        guard !name.isEmpty else { return nil }
        return Request(
            id: id,
            title: name,
            topic: clamp(topic).nilIfBlank,
            subtopic: clamp(subtopic).nilIfBlank,
            titles: titles.map(clamp).filter { !$0.isEmpty }.prefix(maxTitles).map { $0 },
            todos: todos
                .map { Request.Todo(title: clamp($0.title), done: $0.done) }
                .filter { !$0.title.isEmpty }
                .prefix(maxTodos)
                .map { $0 },
            sources: sources.prefix(maxTitles).map { .init(id: String($0.id.prefix(100)),
                title: String($0.title.prefix(300)), text: String($0.text.prefix(1600))) }
        )
    }

    /// Reads the function's reply. Nil unless there is a real summary: a
    /// list of steps with nothing above them is not a brief, and caching it
    /// would stop the next attempt for a week.
    ///
    /// Read field by field rather than through `Codable`, so a malformed
    /// `steps` costs the steps and not the summary next to it.
    static func parse(_ data: Data) -> Brief? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let steps = (object["steps"] as? [Any])?.compactMap { $0 as? String } ?? []
        guard var result = brief(summary: object["summary"] as? String, steps: steps) else { return nil }
        result.source_ids = object["source_ids"] as? [String]
        result.basis = object["basis"] as? String
        result.version = object["version"] as? Int
        return result
    }

    static func brief(summary: String?, steps: [String]) -> Brief? {
        guard var text = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        text = String(text.prefix(maxSummary))

        var seen = Set<String>()
        var kept: [String] = []
        for raw in steps {
            let step = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-•*·"))
                .trimmingCharacters(in: .whitespaces)
            guard !step.isEmpty, step.count <= maxStep else { continue }
            let key = step.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            kept.append(step)
            if kept.count == maxSteps { break }
        }
        return Brief(summary: text, steps: kept)
    }

    /// Whether the cached brief should be asked for again.
    static func isStale(briefAt: Date?, briefCount: Int?, count: Int, now: Date = .now) -> Bool {
        guard let briefAt, let briefCount else { return true }
        if briefCount != count { return true }
        return now.timeIntervalSince(briefAt) >= refreshInterval
    }

    /// The steps the model suggested that are not already on the to-do list,
    /// so a step you accepted does not keep being offered.
    static func pendingSteps(_ brief: Brief?, existing: [String]) -> [String] {
        guard let brief else { return [] }
        let taken = Set(existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return brief.steps.filter { !taken.contains($0.lowercased()) }
    }

    // MARK: - Storage

    /// `Mission.briefText` holds the whole brief as JSON — one optional
    /// column, which keeps the store change a lightweight migration.
    static func encode(_ brief: Brief) -> String? {
        guard let data = try? JSONEncoder().encode(brief) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ text: String?) -> Brief? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Brief.self, from: data)
    }

    // MARK: - Network

    static func inputKey(_ request: Request) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(request)) ?? Data()
        var hash: UInt64 = 14695981039346656037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }

    enum Outcome { case ready(Brief), unavailable(String) }

    static func generate(_ request: Request, session: Supabase.Session) async -> Outcome {
        do {
            let data = try await Supabase.invoke(function: "quest-brief", bodyJSON: JSONEncoder().encode(request), session: session, timeout: 25)
            if var brief = parse(data), brief.version == 2 {
                let known = Set(request.sources.map(\.id))
                brief.source_ids = brief.source_ids?.filter(known.contains)
                brief.inputKey = inputKey(request)
                return .ready(brief)
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if object?["reason"] as? String == "quota_or_unavailable" {
                return .unavailable("Summary generation is temporarily unavailable or the daily limit was reached. Try again later.")
            }
            return .unavailable("Couldn't generate a summary. Your quest is saved; try again later.")
        } catch {
            return .unavailable("Couldn't reach the summary service. Check your connection and retry.")
        }
    }

    /// One call, nil on any failure. Signed out is not a failure; it is the
    /// common case, and the template is what it gets.
    static func fetch(_ request: Request, session: Supabase.Session?) async -> Brief? {
        guard let session, Supabase.isConfigured else { return nil }
        guard
            let body = try? JSONEncoder().encode(request),
            let data = try? await Supabase.invoke(
                function: "quest-brief", bodyJSON: body, session: session, timeout: 20
            )
        else { return nil }
        return parse(data)
    }

    // MARK: - Helpers

    private static func clamp(_ value: String?) -> String {
        guard let value else { return "" }
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxField))
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
