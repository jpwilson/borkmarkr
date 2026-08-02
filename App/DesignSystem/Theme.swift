import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Playful & friendly, one bright accent on near-white — the visual direction
/// locked in during the design session. Accent is user-adjustable (it was one
/// of the three "tweak knobs" in the prototype), so read it from here rather
/// than hardcoding a colour in a view.
enum Theme {
    /// Accent options offered in You > Appearance.
    static let accents: [(name: String, hex: String)] = [
        ("Coral", "FF5A36"),
        ("Violet", "6C4CF1"),
        ("Emerald", "0FA968"),
        ("Blue", "1F6FEB"),
        ("Pink", "EC4899"),
    ]

    static let defaultAccentHex = "FF5A36"

    static let background = Color(hex: "FAF9F7")
    static let surface = Color.white
    static let ink = Color(hex: "15130F")
    static let inkSoft = Color(hex: "6B665E")
    static let hairline = Color(hex: "ECE8E1")

    static let cardRadius: CGFloat = 22
    static let chipRadius: CGFloat = 12
}

/// Accent flows through the environment so every screen picks up a change
/// immediately, including sheets.
private struct AccentKey: EnvironmentKey {
    static let defaultValue = Color(hex: Theme.defaultAccentHex)
}

extension EnvironmentValues {
    var brandAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

/// Rounded card used by the feed, detail and explore screens.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

/// Small pill — platform source, category, tag.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = Theme.inkSoft

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
