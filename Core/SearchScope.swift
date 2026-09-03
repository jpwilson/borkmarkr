import Foundation

/// Which fields a search is allowed to look in.
///
/// Search used to be a whole tab whose only haystack was `searchBlob` — every
/// field concatenated. That is the right default (you remember *a word*, not
/// which field it was in) and it stays the default. But it has one failure
/// mode that shows up constantly once a library is real: a query like "running"
/// matches the eleven borks whose *titles* mention running as loudly as it
/// matches the topic you actually filed things under. Scoping is the answer,
/// and it has to be additive — none selected is the old behaviour, exactly.
///
/// Deliberately an `OptionSet` rather than an enum: the scopes OR together, and
/// "Topics + Tags" is a real thing to ask for.
struct SearchScope: OptionSet, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    /// The bork's topic name — "Fitness", not its id.
    static let topics = SearchScope(rawValue: 1 << 0)
    /// The bork's `subcategory` — "Mobility".
    static let subtopics = SearchScope(rawValue: 1 << 1)
    /// Any one of the bork's tags.
    static let tags = SearchScope(rawValue: 1 << 2)

    /// Chip order, left to right. Broadest first — a topic contains subtopics
    /// contains tags — so the row reads as a zoom, not as three unrelated
    /// switches.
    static let ordered: [SearchScope] = [.topics, .subtopics, .tags]

    var label: String {
        switch self {
        case .topics: "Topics"
        case .subtopics: "Subtopics"
        case .tags: "Tags"
        default: ""
        }
    }

    /// Singular, for the results header: "in the topic “running”".
    var singularPhrase: String {
        switch self {
        case .topics: "in the topic"
        case .subtopics: "in the subtopic"
        case .tags: "with the tag"
        default: "for"
        }
    }

    /// Plural, for a multi-scope header: "in topics, tags".
    var pluralNoun: String {
        switch self {
        case .topics: "topics"
        case .subtopics: "subtopics"
        case .tags: "tags"
        default: ""
        }
    }

    var selected: [SearchScope] { SearchScope.ordered.filter { contains($0) } }
}

/// Case- and diacritic-folding, in one place.
///
/// `Bookmark.searchBlob` is stored already folded this way. Anything compared
/// against it — or against a raw topic name, subtopic or tag — has to fold
/// identically or "Café" stops matching "cafe" in half the app.
enum SearchText {
    static func fold(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    /// Query terms, folded. Whitespace-separated; empty terms dropped.
    static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

/// The searchable surface of one bork, as plain values.
///
/// A value struct rather than a method on `Bookmark` so the matching rules are
/// pure Foundation: they compile and run under `swiftc` on macOS with no
/// SwiftData, no simulator and no test host (`Scripts/test_search.swift`).
/// Search is the feature people judge the app on; it should be the part with
/// tests that run in two seconds.
struct SearchSubject: Hashable, Sendable {
    /// Already lowercased and diacritic-folded — `Bookmark.searchBlob`.
    var blob: String
    var topicName: String?
    var subtopic: String?
    var tags: [String]

    init(blob: String, topicName: String? = nil, subtopic: String? = nil, tags: [String] = []) {
        self.blob = blob
        self.topicName = topicName
        self.subtopic = subtopic
        self.tags = tags
    }

    /// Does this bork match?
    ///
    /// - No scopes: the whole trimmed query as one substring of `blob`. This is
    ///   verbatim the pre-1.1 behaviour and must stay that way — it is what
    ///   every existing user's muscle memory is built on.
    /// - One or more scopes: **every** term in the query has to land somewhere
    ///   in the selected fields, and the scopes OR together per term. So
    ///   "hip mobility" with Subtopics+Tags matches a bork tagged `hips` and
    ///   filed under `Mobility`, and a two-word query can't be satisfied by one
    ///   word matching twice.
    /// - An empty query matches everything; callers gate on the query being
    ///   non-empty before showing results at all.
    func matches(query: String, scopes: SearchScope) -> Bool {
        let terms = SearchText.terms(query)
        guard !terms.isEmpty else { return true }

        guard !scopes.isEmpty else {
            return blob.contains(SearchText.fold(query))
        }

        let haystacks = haystacks(for: scopes)
        guard !haystacks.isEmpty else { return false }

        return terms.allSatisfy { term in
            haystacks.contains { $0.contains(term) }
        }
    }

    private func haystacks(for scopes: SearchScope) -> [String] {
        var fields: [String] = []
        if scopes.contains(.topics), let topicName { fields.append(SearchText.fold(topicName)) }
        if scopes.contains(.subtopics), let subtopic { fields.append(SearchText.fold(subtopic)) }
        if scopes.contains(.tags) { fields.append(contentsOf: tags.map(SearchText.fold)) }
        return fields.filter { !$0.isEmpty }
    }
}

/// Wording for the search results, kept next to the matching rules so the
/// header can never describe a scope the matcher isn't applying.
enum SearchCopy {

    /// "12 borks for “running”" · "12 borks with the tag “running”" ·
    /// "12 borks for “running” in topics, tags".
    static func resultsHeadline(count: Int, query: String, scopes: SearchScope) -> String {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let borks = Copy.countedBorks(count)
        let selected = scopes.selected

        switch selected.count {
        case 0:
            return "\(borks) for “\(term)”"
        case 1:
            return "\(borks) \(selected[0].singularPhrase) “\(term)”"
        default:
            let nouns = selected.map(\.pluralNoun).joined(separator: ", ")
            return "\(borks) for “\(term)” in \(nouns)"
        }
    }

    /// The empty state's second line. With scopes on, the most likely fix is
    /// that the word simply isn't a tag — say so instead of "try again".
    static func emptyDetail(scopes: SearchScope) -> String {
        guard !scopes.isEmpty else { return "Try a different word, or another source." }
        let nouns = scopes.selected.map(\.pluralNoun).joined(separator: " or ")
        return "Nothing matches in \(nouns). Clear the scopes to search everything."
    }

    static let clearScopes = "Search everything"
}
