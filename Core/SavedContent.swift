import Foundation

/// Display-only cleanup; never invents content or replaces the stored title.
enum SavedContent {
    static func excerpt(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard value.count >= 6 else { return nil }
        let walls = ["log in to", "sign in to", "join instagram", "see instagram photos",
                     "create an account", "javascript is not available"]
        guard !walls.contains(where: { value.lowercased().hasPrefix($0) }) else { return nil }
        return String(value.prefix(4_000))
    }

    static func title(_ raw: String, body: String?, platform: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in [" on Instagram:", " on X:", " on X (formerly Twitter):", " on Threads:"] {
            if let range = clean.range(of: marker, options: .caseInsensitive),
               let caption = excerpt(String(clean[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"“”"))) {
                return String(caption.prefix(180))
            }
        }
        let generic = clean.isEmpty || clean.hasPrefix("http")
            || clean.range(of: #" on (X|Instagram|Threads)( \(formerly Twitter\))?$"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
            || ["status", "reel", "post", "instagram", "x"].contains(clean.lowercased())
        if generic, let body = excerpt(body) { return String(body.prefix(180)) }
        return clean.isEmpty ? "Saved post" : clean
    }

    static func breadcrumb(topic: String?, subtopic: String?) -> String {
        [topic, subtopic].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " › ")
    }
}
