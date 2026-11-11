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
/// The brand colours come from `Brand` (Core/BrandTokens.swift), which the
/// app's `Tokens` reads too, so the two can no longer drift.
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

    // MARK: Brand tokens (Core/BrandTokens.swift)

    static let paper = Brand.paper
    static let ink = Brand.ink
    static let inkSecondary = Brand.inkSecondary
    /// Decorative only, never information.
    static let inkFaint = Brand.inkFaint
    static let hairline = Brand.hairline
    static let mutedControl = Brand.mutedControl
    static let toastCheck = Brand.toastCheck
    static let coral = Brand.coral
    static let coralDeep = Brand.coralDeep

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
