import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else { self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1); return }
        self.init(
            .sRGB,
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255,
            opacity: 1
        )
    }
}

/// v2 design tokens, taken from the handoff.
///
/// **One deliberate deviation — small-text contrast.** The spec's tertiary ink
/// `#A39A8D` on the `#F6F3EE` paper is roughly 2.4:1, well under the WCAG AA
/// floor of 4.5:1, and the spec pairs it with 10–10.5px type. That combination
/// is genuinely hard to read for anyone over about 40 or outdoors. `inkMeta`
/// below is darkened to `#6E655A` (~4.9:1) for anything carrying information;
/// the original stays as `inkFaint` for purely decorative marks. Same visual
/// family, legible.
enum Tokens {

    // MARK: Base
    static let paper = Color(hex: "F6F3EE")
    static let surface = Color.white
    static let hairline = Color(hex: "EAE4DA")
    static let divider = Color(hex: "F1EBE1")
    static let mutedControl = Color(hex: "EEE8DE")
    static let segmentTrack = Color(hex: "ECE6DC")
    static let grabber = Color(hex: "DBD2C4")
    static let dashed = Color(hex: "D7CDBD")

    // MARK: Ink
    static let ink = Color(hex: "191510")
    static let inkSecondary = Color(hex: "6E655A")
    /// Informational small text. Darkened from the spec's #A39A8D for contrast.
    static let inkMeta = Color(hex: "6E655A")
    /// Decorative only — never put information at this contrast.
    static let inkFaint = Color(hex: "A39A8D")
    static let bodyOnWhite = Color(hex: "332C23")
    static let mutedHeading = Color(hex: "8A8072")

    static let destructive = Color(hex: "C2545A")
    static let toastBG = Color(hex: "191510")
    static let toastCheck = Color(hex: "7BE3A4")

    // MARK: Note (amber)
    static let noteTop = Color(hex: "FFFBEA")
    static let noteBottom = Color(hex: "FFF5D8")
    static let noteBorder = Color(hex: "F0E0AC")
    static let noteIconBG = Color(hex: "FFE7A0")
    static let noteInk = Color(hex: "5C4E25")
    static let noteMeta = Color(hex: "9A7B1A")

    // MARK: Shape
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 20
    static let sheetRadius: CGFloat = 30
    static let buttonRadius: CGFloat = 16
    static let dockRadius: CGFloat = 24

    /// Minimum tap target. The spec's chips are ~24pt tall; Apple's floor is 44.
    /// Views keep the small visual size and expand the hit area instead.
    static let minTapTarget: CGFloat = 44
}

/// The four accent ramps. Picked in onboarding, persisted, applied app-wide.
struct AccentRamp: Equatable, Sendable {
    let key: String
    let name: String
    let base: Color
    let dark: Color
    let tint: Color
    let deep: Color

    static let all: [AccentRamp] = [
        AccentRamp(key: "FF5A2D", name: "Coral",
                   base: Color(hex: "FF5A2D"), dark: Color(hex: "E8451C"),
                   tint: Color(hex: "FFE7DE"), deep: Color(hex: "AE3512")),
        AccentRamp(key: "7C5CFC", name: "Violet",
                   base: Color(hex: "7C5CFC"), dark: Color(hex: "6A47F0"),
                   tint: Color(hex: "ECE7FF"), deep: Color(hex: "5538C9")),
        AccentRamp(key: "2E8CF0", name: "Blue",
                   base: Color(hex: "2E8CF0"), dark: Color(hex: "1F77D6"),
                   tint: Color(hex: "E2F0FF"), deep: Color(hex: "1E66B8")),
        AccentRamp(key: "1FA971", name: "Green",
                   base: Color(hex: "1FA971"), dark: Color(hex: "178A5C"),
                   tint: Color(hex: "DFF4EA"), deep: Color(hex: "147A52")),
    ]

    static let fallback = all[0]

    /// Unknown persisted values fall back rather than crashing or rendering
    /// black — the spec does the same guard.
    static func named(_ key: String) -> AccentRamp {
        all.first { $0.key == key } ?? fallback
    }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentRamp.fallback
}

extension EnvironmentValues {
    var accent: AccentRamp {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

// MARK: - Topic colour

/// Derived colours for a category hue.
///
/// **Performance note.** The spec expresses these as HSL strings recomputed per
/// render. With a masonry feed of hundreds of cards that's thousands of colour
/// conversions per scroll. These are computed once per category and cached —
/// 50 entries, built lazily on first use.
struct CategoryPalette: Sendable {
    let tint: Color
    let deep: Color
    let dot: Color
    let coverTop: Color
    let coverBottom: Color

    init(hue: Double) {
        let h = hue / 360
        tint = Color(hue: h, saturation: 0.55, brightness: 0.97)
        deep = Color(hue: h, saturation: 0.46, brightness: 0.42)
        dot = Color(hue: h, saturation: 0.50, brightness: 0.70)
        coverTop = Color(hue: h, saturation: 0.52, brightness: 0.62)
        coverBottom = Color(hue: h, saturation: 0.60, brightness: 0.30)
    }
}

extension Topic {
    /// Built once for all 50 topics, immutably — a `static let` is initialised
    /// lazily and thread-safely by the runtime, so this needs no lock and is
    /// concurrency-safe under Swift 6 strict checking. A mutable memo cache
    /// would be shared global state and would need isolation for no benefit:
    /// the table is tiny and fully enumerable up front.
    private static let palettes: [String: CategoryPalette] = Dictionary(
        uniqueKeysWithValues: Taxonomy.all.map { ($0.id, CategoryPalette(hue: $0.hue)) }
    )

    var palette: CategoryPalette {
        Topic.palettes[id] ?? CategoryPalette(hue: hue)
    }
}

/// Fallback palette for uncategorised items — neutral, deliberately dull so it
/// reads as "not filed yet" rather than as a category of its own.
enum NeutralPalette {
    static let value = CategoryPalette(hue: 40)
}

// MARK: - Platform brand

extension Platform {
    /// Badge background. Instagram is a gradient, everything else a flat fill.
    var badgeColors: [Color] {
        switch self {
        case .x: [Color(hex: "0F1014")]
        case .instagram: [Color(hex: "7B3FE4"), Color(hex: "DB2E7A"), Color(hex: "FF7A3D")]
        case .tiktok: [Color(hex: "0D0E12")]
        case .youtube: [Color(hex: "CC1B2B")]
        case .shorts: [Color(hex: "D5202F")]
        case .threads: [Color(hex: "141416")]
        case .pinterest: [Color(hex: "B8121F")]
        case .web: [Color(hex: "48505C")]
        }
    }

    var badgeInk: Color {
        self == .tiktok ? Color(hex: "5CE8E4") : .white
    }

    /// Full-bleed header gradient on the Source page.
    var headerColors: [Color] {
        switch self {
        case .x, .tiktok: [Color(hex: "17181D"), Color(hex: "000000")]
        case .instagram: [Color(hex: "7B3FE4"), Color(hex: "DB2E7A"), Color(hex: "FF7A3D")]
        case .youtube: [Color(hex: "B3121F"), Color(hex: "5E0A12")]
        case .shorts: [Color(hex: "C11723"), Color(hex: "5E0A12")]
        case .threads: [Color(hex: "1B1B1E"), Color(hex: "000000")]
        case .pinterest: [Color(hex: "A50F1B"), Color(hex: "4E070D")]
        case .web: [Color(hex: "3E4550"), Color(hex: "20242B")]
        }
    }
}

// MARK: - Reusable surfaces

struct CardSurface: ViewModifier {
    var radius: CGFloat = Tokens.cardRadius
    var strong: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            .background(Tokens.surface, in: shape)
            .overlay(shape.stroke(Tokens.hairline, lineWidth: 1))
            .shadow(color: Color(hex: "191510").opacity(0.03), radius: 2, y: 1)
            .shadow(color: Color(hex: "191510").opacity(strong ? 0.14 : 0.10), radius: 14, y: 10)
    }
}

extension View {
    func cardSurface(radius: CGFloat = Tokens.cardRadius, strong: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, strong: strong))
    }

    /// Keeps a chip visually small while meeting the 44pt tap minimum.
    func tappableChip() -> some View {
        contentShape(Rectangle())
            .frame(minHeight: Tokens.minTapTarget)
    }
}

// MARK: - Type

/// The spec calls for Bricolage Grotesque (display) and Instrument Sans (UI).
/// Neither is bundled — both are OFL-licensed Google Fonts and would need to be
/// added as binary assets. Until then these map to the system faces at matching
/// weights and tracking, which is close in feel and keeps Dynamic Type working.
/// Swapping in the real families means changing only this enum.
enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}
