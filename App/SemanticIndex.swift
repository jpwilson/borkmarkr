import Foundation
import NaturalLanguage

/// Meaning-based search over the library.
///
/// The brief's actual complaint is that people "don't know how to search through
/// them" — and keyword search doesn't fix that, because nobody remembers the
/// words. They remember *"that thing about the guy who fixed his back"* when the
/// title was "5-minute hip mobility flow you can do at your desk". No substring
/// match will ever connect those two.
///
/// **Why word embeddings and not `sentenceEmbedding`.** The obvious API here is
/// `NLEmbedding.sentenceEmbedding`, and it was the first thing tried. Measured
/// against a sample library it was unusable: "how do I make my car look new"
/// ranked a hip-mobility clip above the car-detailing video, "something to cook
/// tonight" ranked a magnesium thread top, and nearly every score landed in the
/// 0.2–0.45 band — below any threshold that would also exclude nonsense. Apple's
/// sentence model simply doesn't separate these short, noun-heavy strings.
///
/// Averaging *word* vectors over stopword-filtered tokens does much better —
/// but measure it honestly. Against a 10-item sample library and 7 natural-
/// language queries it put the right item first **5 times out of 7**:
///
///   ✓ "how do I make my car look new"        → paint correction   0.72
///   ✓ "something to cook tonight"            → one-pan orzo       0.70
///   ✓ "cant sleep"                           → magnesium thread   0.63
///   ✓ "kid screaming in the supermarket"     → tantrum reset      0.60
///   ~ "the guy who fixed his back"           → hamstring stretches (hip
///                                              mobility was the better hit)
///   ✗ "what should I eat in the morning"     → morning routine    0.75
///   ✗ "ai that does work for me"             → tantrum reset      0.50
///
/// The failure mode is inherent to averaging: one strong token ("morning")
/// dominates the mean and drags the whole vector with it.
///
/// **So this is a supplementary signal, not primary search.** It's surfaced as
/// a "Related" strip *below* exact keyword results, never in place of them —
/// a wrong suggestion at the bottom of a correct list costs nothing, whereas
/// the same wrongness at the top would make search feel broken. Real precision
/// here needs a proper sentence transformer via Core ML (~90MB bundled) or a
/// hosted embedding API; both are worth it later, neither is worth it before
/// the library is dense enough to search.
///
/// Runs entirely on-device: no network, no API key, no per-query cost, and
/// nothing about a private library leaves the phone.
///
/// **Deliberately in-memory rather than persisted.** Storing vectors on the
/// model would mean a schema change against data that already exists on a
/// device. Building lazily costs about a second for a few thousand items, once
/// per launch. Persist when libraries get big enough to notice — not before.
///
/// Also deliberately **not** compiled into the Share Extension: extensions run
/// under a hard memory cap and have no business loading an embedding model to
/// save one URL.
@MainActor
final class SemanticIndex: ObservableObject {

    /// Nil on locales/devices without an English word embedding — search
    /// degrades to keyword-only rather than failing.
    private let embedding = NLEmbedding.wordEmbedding(for: .english)

    private var vectors: [String: [Double]] = [:]
    /// Tracks what each vector was built from, so edits re-embed and untouched
    /// items don't.
    private var stamps: [String: Date] = [:]

    var isAvailable: Bool { embedding != nil }

    /// Ordinary English function words. Content words are deliberately absent —
    /// "morning", "sleep", "new" all carry real meaning for a bookmark library
    /// and removing them to flatter a test would just move the failure.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "your", "you", "yours", "our",
        "that", "this", "these", "those", "there", "here", "what", "which",
        "who", "whom", "whose", "when", "where", "why", "how", "all", "any",
        "both", "each", "few", "more", "most", "other", "some", "such", "than",
        "too", "very", "can", "will", "just", "should", "now", "about", "into",
        "over", "then", "once", "been", "being", "have", "has", "had", "does",
        "did", "doing", "would", "could", "shall", "may", "might", "must",
        "his", "her", "hers", "its", "their", "theirs", "mine", "ours",
        "was", "were", "are", "but", "not", "off", "out", "own", "same",
        "get", "got", "getting", "thing", "things", "stuff", "really",
    ]

    // MARK: - Building

    /// Incremental: only embeds items that are new or changed since last pass.
    func refresh(_ bookmarks: [Bookmark]) {
        guard embedding != nil else { return }

        let live = Set(bookmarks.map(\.id))
        for id in vectors.keys where !live.contains(id) {
            vectors[id] = nil
            stamps[id] = nil
        }

        for bookmark in bookmarks {
            if let stamp = stamps[bookmark.id], stamp == bookmark.updatedAt { continue }
            if let vector = vector(for: Self.text(for: bookmark)) {
                vectors[bookmark.id] = vector
                stamps[bookmark.id] = bookmark.updatedAt
            }
        }
    }

    /// What gets embedded. Title and post body carry the meaning; category,
    /// subcategory and tags are included because they're often the only
    /// descriptive words a bare link has.
    private static func text(for bookmark: Bookmark) -> String {
        var parts = [bookmark.title]
        if let body = bookmark.text, !body.isEmpty { parts.append(String(body.prefix(400))) }
        if let note = bookmark.noteText, !note.isEmpty { parts.append(note) }
        if let category = bookmark.category { parts.append(category.name) }
        if let sub = bookmark.subcategory { parts.append(sub) }
        parts.append(contentsOf: bookmark.tags)
        return parts.joined(separator: " ")
    }

    /// Mean of the word vectors for the content words in `text`.
    private func vector(for text: String) -> [Double]? {
        guard let embedding else { return nil }

        let tokens = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.stopWords.contains($0) }

        var sum: [Double] = []
        var count = 0
        for token in tokens {
            guard let v = embedding.vector(for: token) else { continue }
            if sum.isEmpty { sum = v } else {
                for i in 0..<min(sum.count, v.count) { sum[i] += v[i] }
            }
            count += 1
        }

        guard count > 0, !sum.isEmpty else { return nil }
        return sum.map { $0 / Double(count) }
    }

    // MARK: - Searching

    struct Hit: Identifiable {
        let bookmark: Bookmark
        let score: Double
        var id: String { bookmark.id }
    }

    /// Items whose *meaning* matches the query, best first.
    ///
    /// `minimumScore` is a floor, not a ranking aid: an embedding always has a
    /// nearest neighbour, so without a threshold every query returns
    /// confident-looking nonsense.
    ///
    /// 0.55 from measurement, not taste: good matches landed 0.59–0.75 and the
    /// worst false positive scored 0.50, so this cuts it while keeping every
    /// true hit. The bands do overlap — no threshold separates them cleanly,
    /// which is another reason this stays a secondary strip.
    func search(
        _ query: String,
        in bookmarks: [Bookmark],
        limit: Int = 8,
        minimumScore: Double = 0.55
    ) -> [Hit] {
        guard
            query.trimmingCharacters(in: .whitespaces).count >= 3,
            let queryVector = vector(for: query)
        else { return [] }

        let byID = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })

        return vectors.compactMap { id, vec -> Hit? in
            guard let bookmark = byID[id] else { return nil }
            let score = Self.cosine(queryVector, vec)
            guard score >= minimumScore else { return nil }
            return Hit(bookmark: bookmark, score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
