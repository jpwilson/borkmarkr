import Foundation

/// The one letter an avatar wears.
///
/// The Library header used to show a hardcoded "J" — the founder's initial —
/// on every phone, signed in or not. The rule now lives in one place and both
/// avatars (Library header, You tab) ask it: the display name if there is
/// one, else the part of the email before the @, else nothing. Nothing means
/// the circle wears a neutral person glyph, never someone else's letter.
///
/// Pure Foundation, so `Scripts/test_topic_picker.swift` compiles it on macOS.
enum Initials {

    /// The first letter or digit of `displayName`, else of the email's local
    /// part, uppercased. `nil` when there is no one to draw — signed out, or
    /// an address with nothing before the @.
    static func letter(displayName: String?, email: String?) -> String? {
        first(in: displayName) ?? first(in: localPart(of: email))
    }

    /// "sam@example.com" → "sam". A string with no @ is used whole.
    static func localPart(of email: String?) -> String? {
        guard let email else { return nil }
        return email
            .split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)
    }

    /// The first character that is a letter or a number, uppercased, and one
    /// grapheme of it: "ß" uppercases to "SS", and an avatar is one glyph.
    /// Punctuation, spaces and emoji are skipped, so "🦊 Sam" and "_sam" are
    /// both "S".
    private static func first(in text: String?) -> String? {
        guard let text,
              let char = text.first(where: { $0.isLetter || $0.isNumber })
        else { return nil }
        return String(char).uppercased().first.map(String.init)
    }
}
