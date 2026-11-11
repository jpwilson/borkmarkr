import SwiftUI

/// The brand's colours, once, for both targets.
///
/// `Core/` compiles into the app and the Share Extension; `App/` only into the
/// app. So the colours both need live here, and `Tokens` (App) and
/// `QuickFileStyle` (Core) read them rather than each carrying a copy.
/// design/SYSTEM.md, "Tokens", is the source: unchanged from 1.3 except that
/// the coral family now has one deep (`coralDeep`) for small coral text.
enum Brand {
    /// The page. Every screen, sheet and the tab bar.
    static let paper = rgb(0xF6, 0xF3, 0xEE)
    /// Cards, rows, slabs, search fields.
    static let surface = Color.white
    /// The 1 pt line round every card and above the tab bar.
    static let hairline = rgb(0xEA, 0xE4, 0xDA)
    /// Text.
    static let ink = rgb(0x19, 0x15, 0x10)
    /// Secondary and meta text: 5.3:1 on paper, 5.9:1 on white.
    static let inkSecondary = rgb(0x6E, 0x65, 0x5A)
    /// Decorative marks only (2.4:1) — never information.
    static let inkFaint = rgb(0xA3, 0x9A, 0x8D)
    /// The one accent: the + button, primary buttons, the Done pill.
    static let coral = rgb(0xFF, 0x5A, 0x2D)
    /// Coral text on paper or white (quiet buttons, the selected tab): 6.6:1.
    static let coralDeep = rgb(0xAE, 0x35, 0x12)
    /// Sheet grabbers.
    static let grabber = rgb(0xDB, 0xD2, 0xC4)
    /// Dashed outlines ("+ Tag", "New topic").
    static let dashed = rgb(0xD7, 0xCD, 0xBD)
    /// Sand: avatar circles, off tag pills, the "not filed" tint.
    static let sand = rgb(0xEC, 0xE5, 0xD8)
    /// Sand's text colour (the Sand row's deep).
    static let sandInk = rgb(0x5A, 0x4E, 0x38)
    /// The ground under clay art: covers, topic tiles, the topic banner.
    static let clayGround = rgb(0xE8, 0xE0, 0xCB)
    /// Muted fills (segmented track, inactive controls).
    static let mutedControl = rgb(0xEE, 0xE8, 0xDE)
    /// "More…" slab on the wheel.
    static let offWhite = rgb(0xFB, 0xF8, 0xF2)
    /// Toast background and the toast's check.
    static let toast = rgb(0x19, 0x15, 0x10)
    static let toastCheck = rgb(0x7B, 0xE3, 0xA4)
    /// Warm shadow colour for things that float (slabs, hub, sheets).
    static let shadow = rgb(0x78, 0x54, 0x32)

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }
}
