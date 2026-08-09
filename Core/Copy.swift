import Foundation

/// User-facing wording, in one place.
///
/// A saved link is a **bork**. Not a "save", not a "bookmark" — the product
/// needs its own noun, and "1 save" reads like a verb every time. You bork
/// something, you've got 400 borks, you share a bork.
///
/// Centralised because renaming a core noun across a dozen screens by hand is
/// how you end up with three of them in the shipped build.
enum Copy {
    /// "bork" / "borks"
    static func borks(_ count: Int) -> String {
        count == 1 ? "bork" : "borks"
    }

    /// "1 bork" / "26 borks"
    static func countedBorks(_ count: Int) -> String {
        "\(count) \(borks(count))"
    }

    static let saveVerb = "Bork it"
    static let searchPlaceholder = "Search everything you've borked"
}
