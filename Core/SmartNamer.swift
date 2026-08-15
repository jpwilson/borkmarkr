import Foundation

/// Asks the model to name a side quest the way a person would say it.
///
/// Offline `Mission.draftTitle` already refuses "Get into X". This is the
/// second pass: it reads a handful of titles in the pile and returns a name
/// like "Improve mobility for running" or "Go down the rabbit hole".
///
/// **The key is not in this app.** Same contract as `SmartCategorizer` — a
/// Supabase Edge Function holds it, the user's JWT authenticates, every
/// failure (signed out, quota, server) leaves the offline name in place.
///
/// Called once for a batch of suggestions, not per save. That is the
/// "use it sparingly" rule.
enum SmartNamer {

    private struct Request: Encodable {
        var clusters: [Cluster]
    }

    private struct Cluster: Encodable {
        var id: String
        var topic: String
        var subtopic: String?
        var titles: [String]
    }

    private struct Response: Decodable {
        var names: [Named]
    }

    private struct Named: Decodable {
        var id: String
        var title: String
    }

    static func refine(_ seeds: [Mission.Seed], session: Supabase.Session?) async -> [Mission.Seed] {
        guard let session, Supabase.isConfigured, !seeds.isEmpty else { return seeds }

        let payload = Request(clusters: seeds.map { seed in
            Cluster(
                id: seed.id,
                topic: Taxonomy.category(id: seed.categoryID)?.name ?? "",
                subtopic: seed.subcategory,
                titles: Array(seed.sampleTitles.prefix(6))
            )
        })

        guard
            let body = try? JSONEncoder().encode(payload),
            let data = try? await Supabase.invoke(
                function: "name-quest", bodyJSON: body, session: session
            ),
            let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return seeds }

        let byID = Dictionary(uniqueKeysWithValues: decoded.names.map { ($0.id, $0.title) })
        return seeds.map { seed in
            var next = seed
            if let title = byID[seed.id] {
                let cleaned = Self.cleaned(title)
                if !cleaned.isEmpty { next.title = cleaned }
            }
            return next
        }
    }

    private static func cleaned(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("\"") && title.hasSuffix("\"") {
            title = String(title.dropFirst().dropLast())
        }
        title = title.replacingOccurrences(of: "Get into ", with: "", options: .caseInsensitive)
        guard title.count >= 4, title.count <= 48 else { return "" }
        return title
    }
}
