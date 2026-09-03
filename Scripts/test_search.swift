import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/search-tests Core/Copy.swift Core/SearchScope.swift Scripts/test_search.swift`

@main
enum SearchScopeTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        /// Builds a subject the way `Bookmark` does: the blob is every field
        /// concatenated, lowercased and diacritic-folded.
        func bork(
            title: String,
            topic: String? = nil,
            subtopic: String? = nil,
            tags: [String] = [],
            note: String = "",
            platform: String = "Instagram"
        ) -> SearchSubject {
            let blob = ([title, note, subtopic ?? "", topic ?? "", platform] + tags)
                .joined(separator: " ")
                .lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
            return SearchSubject(blob: blob, topicName: topic, subtopic: subtopic, tags: tags)
        }

        let hamstrings = bork(
            title: "4 stretches for tight hamstrings after long runs",
            topic: "Fitness", subtopic: "Stretching", tags: ["hamstrings", "running"]
        )
        let orzo = bork(
            title: "One-pan lemon orzo that reheats properly",
            topic: "Recipes", subtopic: "One-pan", tags: ["orzo", "weeknight"], platform: "Web"
        )
        let runningShoes = bork(
            title: "Why your running shoes are wrong",
            topic: "Fitness", subtopic: "Gear", tags: ["shoes"]
        )
        let coldCase = bork(
            title: "Unsolved: the detective who never closed the case",
            topic: "True crime", subtopic: "Cold cases", tags: ["unsolved"], platform: "YouTube"
        )
        let cafe = bork(
            title: "The café that roasts its own",
            topic: "Food", subtopic: "Coffee", tags: ["café", "roasting"], platform: "Web"
        )

        // MARK: Unscoped is the pre-1.1 behaviour, unchanged.

        expect(hamstrings.matches(query: "hamstrings", scopes: []), "unscoped finds a word in the title")
        expect(hamstrings.matches(query: "Stretching", scopes: []), "unscoped finds the subtopic")
        expect(hamstrings.matches(query: "FITNESS", scopes: []), "unscoped is case-insensitive")
        expect(!orzo.matches(query: "hamstrings", scopes: []), "unscoped does not match everything")
        expect(runningShoes.matches(query: "running", scopes: []), "unscoped matches a title-only hit")

        // The whole trimmed query is one substring, as it always was — this is
        // what makes "long runs" find the hamstring clip.
        expect(hamstrings.matches(query: " long runs ", scopes: []), "unscoped trims and matches a phrase")
        expect(!hamstrings.matches(query: "runs long", scopes: []), "unscoped is a phrase match, not a term match")

        // MARK: Scopes narrow, they never widen.

        expect(
            hamstrings.matches(query: "running", scopes: .tags),
            "Tags scope matches a tag"
        )
        expect(
            !runningShoes.matches(query: "running", scopes: .tags),
            "Tags scope ignores a title-only hit"
        )
        expect(
            hamstrings.matches(query: "stretch", scopes: .subtopics),
            "Subtopics scope matches a prefix of the subtopic"
        )
        expect(
            !hamstrings.matches(query: "stretch", scopes: .tags),
            "Subtopics text does not satisfy the Tags scope"
        )
        expect(
            hamstrings.matches(query: "fit", scopes: .topics),
            "Topics scope matches the topic name"
        )
        expect(
            !hamstrings.matches(query: "instagram", scopes: .topics),
            "Topics scope does not see the platform"
        )
        expect(
            !coldCase.matches(query: "detective", scopes: [.topics, .subtopics, .tags]),
            "a title word matches nothing when every scope is on"
        )

        // MARK: Scopes OR together; terms AND.

        expect(
            hamstrings.matches(query: "running", scopes: [.topics, .tags]),
            "Topics OR Tags: the tag alone is enough"
        )
        expect(
            hamstrings.matches(query: "fitness", scopes: [.topics, .tags]),
            "Topics OR Tags: the topic alone is enough"
        )
        expect(
            hamstrings.matches(query: "fitness running", scopes: [.topics, .tags]),
            "two terms may land in two different selected scopes"
        )
        expect(
            !hamstrings.matches(query: "fitness orzo", scopes: [.topics, .tags]),
            "every term has to land somewhere — one miss fails the bork"
        )
        expect(
            hamstrings.matches(query: "  running   hamstrings  ", scopes: .tags),
            "extra whitespace between terms is ignored"
        )

        // MARK: Folding matches `searchBlob`'s own folding.

        expect(cafe.matches(query: "cafe", scopes: .tags), "an unaccented query matches an accented tag")
        expect(cafe.matches(query: "café", scopes: .tags), "an accented query matches too")
        expect(cafe.matches(query: "COFFEE", scopes: .subtopics), "scoped matching is case-insensitive")

        // MARK: Degenerate input.

        expect(orzo.matches(query: "", scopes: []), "an empty query constrains nothing")
        expect(orzo.matches(query: "   ", scopes: [.tags]), "whitespace is an empty query, scoped or not")
        let untagged = bork(title: "Loose note", topic: nil, subtopic: nil, tags: [])
        expect(
            !untagged.matches(query: "loose", scopes: .tags),
            "a bork with no tags can never match the Tags scope"
        )
        expect(
            untagged.matches(query: "loose", scopes: []),
            "…but it is still found unscoped"
        )

        // MARK: Headline wording.

        expect(
            SearchCopy.resultsHeadline(count: 12, query: "running", scopes: []) == "12 borks for “running”",
            "unscoped header"
        )
        expect(
            SearchCopy.resultsHeadline(count: 12, query: "running", scopes: .tags)
                == "12 borks with the tag “running”",
            "tag header"
        )
        expect(
            SearchCopy.resultsHeadline(count: 1, query: "running", scopes: .subtopics)
                == "1 bork in the subtopic “running”",
            "subtopic header, singular"
        )
        expect(
            SearchCopy.resultsHeadline(count: 3, query: "running", scopes: .topics)
                == "3 borks in the topic “running”",
            "topic header"
        )
        expect(
            SearchCopy.resultsHeadline(count: 3, query: "running", scopes: [.topics, .subtopics])
                == "3 borks for “running” in topics, subtopics",
            "plural scopes are listed in chip order"
        )
        expect(
            SearchCopy.resultsHeadline(count: 0, query: "  running  ", scopes: [])
                == "0 borks for “running”",
            "the header shows the trimmed query"
        )
        expect(
            SearchScope.ordered.map(\.label) == ["Topics", "Subtopics", "Tags"],
            "chips read broadest to narrowest"
        )

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
