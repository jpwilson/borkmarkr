import Foundation

/// Recent tags for a category / subcategory pair.
///
/// The Add sheet used to rank every tag in the library by frequency, so a
/// Marketing › Ads save suggested `#instagram` and `#injuries` — the user's
/// most-used tags anywhere, not the ones that belong on this filing. Recency
/// inside the pair is what you actually want to tap.
enum TagRecency {
    struct Item: Sendable {
        var categoryID: String?
        var subcategory: String?
        var tags: [String]
        var at: Date
    }

    static let limit = 8

    static func suggestions(
        in items: [Item],
        categoryID: String?,
        subcategory: String?,
        excluding: Set<String> = [],
        prefix: String = "",
        limit: Int = TagRecency.limit
    ) -> [String] {
        guard let categoryID else { return [] }

        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excludingLower = Set(excluding.map { $0.lowercased() })
        let categoryLower = categoryID.lowercased()
        let subLower = subcategory?.lowercased()

        func usable(_ tag: String) -> Bool {
            let value = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { return false }
            if excludingLower.contains(value) { return false }
            if Platform.isSiteName(value) { return false }
            if value == categoryLower { return false }
            if let subLower, value == subLower { return false }
            if !prefix.isEmpty && !value.hasPrefix(prefix) { return false }
            return true
        }

        func newest(in subset: [Item]) -> [(String, Date)] {
            var latest: [String: Date] = [:]
            for item in subset {
                for tag in item.tags where usable(tag) {
                    let value = tag.lowercased()
                    if let existing = latest[value] {
                        if item.at > existing { latest[value] = item.at }
                    } else {
                        latest[value] = item.at
                    }
                }
            }
            return latest
                .map { ($0.key, $0.value) }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
                    return lhs.1 > rhs.1
                }
        }

        let inCategory = items.filter { $0.categoryID == categoryID }
        let exact: [Item]
        if let subcategory {
            exact = inCategory.filter {
                $0.subcategory?.caseInsensitiveCompare(subcategory) == .orderedSame
            }
        } else {
            exact = inCategory
        }

        var ordered = newest(in: exact).map(\.0)
        if ordered.count < limit, subcategory != nil {
            let seen = Set(ordered)
            ordered.append(contentsOf: newest(in: inCategory).map(\.0).filter { !seen.contains($0) })
        }
        return Array(ordered.prefix(limit))
    }
}
