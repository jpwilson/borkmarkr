import Foundation

/// Asks a model where a link belongs, when the offline categoriser can't tell.
///
/// **Why there are two categorisers.** `Categorizer` matches title and URL
/// against the taxonomy. It's instant, free, works offline, and handles most
/// links — but it can only see words it already knows. A reel titled "she does
/// this every morning and it changed her skin" contains nothing in the beauty
/// subcategory list, so it comes back empty and the link shows as "Not filed
/// yet". A model reads that title the way a person does.
///
/// So: the offline pass always runs and its answer is used immediately. This
/// runs afterwards, only for the links the offline pass couldn't place or
/// placed on thin evidence, and only when you're signed in. Sign-out, aeroplane
/// mode, a server outage, an unset API key — every one of those falls back to
/// the offline answer rather than blocking or failing the save.
///
/// **The key is not in this app.** The request goes to a Supabase Edge Function
/// which holds the Anthropic key server-side. Shipping a key in an iOS binary
/// means shipping it to everyone who downloads the app.
///
/// Like `Categorizer`, the result is a **suggestion**. The caller shows it and
/// the user can change it before saving.
enum SmartCategorizer {

    /// What we send. Small on purpose — no note text, no history, nothing about
    /// the rest of your library. The function only ever sees the one link.
    private struct Request: Encodable {
        var url: String
        var title: String
        var author: String?
        var text: String?
        var tags: [String]
    }

    private struct Response: Decodable {
        var topic: String?
        var subtopic: String?
        var tags: [String]
    }

    /// Returns a validated suggestion, or `nil` for "no better answer than the
    /// one you already have" — which covers every failure mode.
    ///
    /// - Parameter session: a valid Supabase session. Pass `nil` when signed
    ///   out and this returns immediately without touching the network.
    static func suggest(
        url: URL,
        title: String,
        author: String? = nil,
        text: String? = nil,
        tags: [String] = [],
        session: Supabase.Session?
    ) async -> Categorizer.Suggestion? {
        guard let session, Supabase.isConfigured else { return nil }

        let payload = Request(
            url: url.absoluteString,
            title: title,
            author: author,
            text: text,
            // Only tags the user typed are worth sending. The offline pass
            // seeds tags from its own keyword matches, and feeding those back
            // in would just have the model agree with a guess we already know
            // was weak.
            tags: tags
        )

        guard
            let body = try? JSONEncoder().encode(payload),
            let data = try? await Supabase.invoke(
                function: "categorize", bodyJSON: body, session: session
            ),
            let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }

        return validated(decoded, url: url)
    }

    // MARK: - Validation

    /// Checks the model's answer against the taxonomy this build actually has.
    ///
    /// The function embeds a generated copy of the taxonomy (see
    /// `Scripts/gen_taxonomy_ts.py`). If that copy is ever ahead of or behind
    /// the app — a redeploy without a release, or the reverse — an unknown
    /// topic id would otherwise become a bookmark filed under a category that
    /// doesn't exist, invisible in Browse. So unknown ids are dropped, and the
    /// link keeps its honest "not filed" state.
    private static func validated(_ response: Response, url: URL) -> Categorizer.Suggestion? {
        guard let id = response.topic, let topic = Taxonomy.category(id: id) else { return nil }

        // Match the subtopic case-insensitively against the real list rather
        // than trusting the string. Returning "mobility" where the taxonomy
        // says "Mobility" would create a second, lowercase chip in the UI.
        let subcategory = response.subtopic.flatMap { proposed in
            topic.subs.first { $0.caseInsensitiveCompare(proposed) == .orderedSame }
        }

        let platform = Platform.detect(from: url).name.lowercased()
        let tags = (response.tags + [platform])
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        return Categorizer.Suggestion(
            categoryID: topic.id,
            subcategory: subcategory,
            tags: Array(NSOrderedSet(array: tags).array as? [String] ?? tags),
            // A model that read the title and picked from the full list is
            // better evidence than any keyword match, so this outranks the
            // offline confidence threshold.
            score: Categorizer.Suggestion.confidentScore * 2
        )
    }
}
