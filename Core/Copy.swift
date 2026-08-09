import Foundation

/// User-facing wording, in one place.
///
/// A saved item is a **brk**. Not a "save", not a "bookmark", not an "item" —
/// the product needs its own noun, and "1 save" reads like a verb every time.
/// Owning the word is also how the name stops being a joke and starts being a
/// brand: you brk something, you've got 400 brks, you share a brk.
///
/// Centralised because renaming a core noun across a dozen screens by hand is
/// how you end up with three of them in the shipped build.
enum Copy {
    /// "brk" / "brks"
    static func brks(_ count: Int) -> String {
        count == 1 ? "brk" : "brks"
    }

    /// "1 brk" / "26 brks"
    static func countedBrks(_ count: Int) -> String {
        "\(count) \(brks(count))"
    }

    /// Verb form, for buttons and confirmations.
    static let saveVerb = "Brk it"
    static let savedConfirmation = "Brk'd to"
}
