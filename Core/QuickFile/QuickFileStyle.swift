import SwiftUI
import UIKit

/// How Quick File looks where it runs.
///
/// The dial is one design in three places: the Share Extension, the app's Add
/// sheet and triage. What differs is only what each place can reach. The
/// extension compiles Core and nothing else, so `system` is SF Rounded and
/// topic art from the 240 px thumbnails the app leaves in the App Group. The
/// app swaps in Bricolage and Instrument Sans and its bundled clay scenes
/// (`QuickFileStyle+App.swift`).
///
/// The brand colours are `App/DesignSystem/Tokens.swift` by value, for the
/// same reason the extension's status card carries them: App/ is not compiled
/// into the extension.
struct QuickFileStyle: Sendable {
    /// The hub's topic name and other display lines.
    var display: @Sendable (CGFloat) -> Font
    /// Everything else.
    var ui: @Sendable (CGFloat, Font.Weight) -> Font
    /// A topic's clay picture, or nil for the colour disc with its initial.
    var art: @MainActor @Sendable (String) -> UIImage?
    /// The bead, the confirm check and the drain on "Not now". Nowhere else.
    var accent: Color
    /// The header and text buttons, in the accent's family.
    var accentDeep: Color

    static let system = QuickFileStyle(
        display: { size in .system(size: size, weight: .bold, design: .rounded) },
        ui: { size, weight in .system(size: size, weight: weight, design: .rounded) },
        art: { topicID in QuickFileArt.image(for: topicID) },
        accent: coral,
        accentDeep: coralDeep
    )

    // MARK: Brand tokens (Tokens.swift by value)

    static let paper = Color(red: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEE / 255)
    static let ink = Color(red: 0x19 / 255, green: 0x15 / 255, blue: 0x10 / 255)
    static let inkSecondary = Color(red: 0x6E / 255, green: 0x65 / 255, blue: 0x5A / 255)
    /// Decorative only, never information.
    static let inkFaint = Color(red: 0xA3 / 255, green: 0x9A / 255, blue: 0x8D / 255)
    static let hairline = Color(red: 0xEA / 255, green: 0xE4 / 255, blue: 0xDA / 255)
    static let mutedControl = Color(red: 0xEE / 255, green: 0xE8 / 255, blue: 0xDE / 255)
    static let toastCheck = Color(red: 0x7B / 255, green: 0xE3 / 255, blue: 0xA4 / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x2D / 255)
    static let coralDeep = Color(red: 0xAE / 255, green: 0x35 / 255, blue: 0x12 / 255)

    /// A topic's colours, custom topics included; unknown ids get the dull
    /// "not filed" palette rather than a colour of their own.
    static func palette(for topicID: String) -> CategoryPalette {
        Taxonomy.category(id: topicID)?.palette ?? NeutralPalette.value
    }
}

/// Quick File's buttons press in a little, like the app's chips.
struct QuickFilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
