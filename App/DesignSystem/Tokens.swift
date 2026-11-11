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

/// Design tokens — "Quiet clay" (design/SYSTEM.md, 1.4).
///
/// The brand colours themselves live in `Brand` (Core/BrandTokens.swift) so the
/// Share Extension shares them; `Tokens` re-exports them under the names the
/// app has always used and adds the app-only shape, spacing and size tokens.
///
/// **Small-text contrast.** Secondary and meta text are both `#6E655A`
/// (5.3:1 on paper); the old spec's `#A39A8D` survives only as `inkFaint`, for
/// purely decorative marks.
enum Tokens {

    // MARK: Base
    static let paper = Brand.paper
    static let surface = Brand.surface
    static let hairline = Brand.hairline
    static let divider = Color(hex: "F1EBE1")
    static let mutedControl = Brand.mutedControl
    static let segmentTrack = Color(hex: "ECE6DC")
    static let grabber = Brand.grabber
    static let dashed = Brand.dashed
    /// Avatar circles, off tag pills, the "not filed" tint.
    static let sand = Brand.sand
    /// Text on sand.
    static let sandInk = Brand.sandInk
    /// The ground under clay art (covers, tiles, the topic banner).
    static let clayGround = Brand.clayGround
    /// "More…" on the wheel.
    static let offWhite = Brand.offWhite

    // MARK: Ink
    static let ink = Brand.ink
    static let inkSecondary = Brand.inkSecondary
    /// Informational small text — the same as `inkSecondary` (≥ 4.5:1).
    static let inkMeta = Brand.inkSecondary
    /// Decorative only — never put information at this contrast.
    static let inkFaint = Brand.inkFaint
    static let bodyOnWhite = Color(hex: "332C23")
    /// Small-caps labels. Was #8A8072 (3.6:1); now secondary, which passes.
    static let mutedHeading = Brand.inkSecondary

    // MARK: Accent (the default ramp; `\.accent` carries the person's pick)
    static let coral = Brand.coral
    /// Small coral text on paper or white.
    static let coralDeep = Brand.coralDeep

    static let destructive = Color(hex: "C2545A")
    static let toastBG = Brand.toast
    static let toastCheck = Brand.toastCheck

    // MARK: Note (amber)
    static let noteTop = Color(hex: "FFFBEA")
    static let noteBottom = Color(hex: "FFF5D8")
    static let noteBorder = Color(hex: "F0E0AC")
    static let noteIconBG = Color(hex: "FFE7A0")
    static let noteInk = Color(hex: "5C4E25")
    static let noteMeta = Color(hex: "9A7B1A")

    // MARK: Shape
    /// Cards, rows, slim action rows, topic tiles.
    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 18
    /// Sheets (`.claySheet()`).
    static let sheetRadius: CGFloat = 28
    /// The refine panel and other floating slabs.
    static let slabRadius: CGFloat = 28
    /// Small thumbnails: a row's 56 pt cover, a slim row's 36 pt art.
    static let thumbRadius: CGFloat = 10
    /// Search fields.
    static let searchRadius: CGFloat = 14
    static let fieldRadius: CGFloat = 14
    /// Legacy rectangular buttons; the new buttons are pills.
    static let buttonRadius: CGFloat = 16
    /// 1.3's floating dock. Unused by the flat tab bar.
    static let dockRadius: CGFloat = 24

    // MARK: Spacing
    /// Side gutter on every screen.
    static let gutter: CGFloat = 20
    /// Between sections.
    static let sectionGap: CGFloat = 28
    /// Between cards in a grid (SYSTEM.md allows 10–12; Main.dc uses 12).
    static let gridGap: CGFloat = 12
    /// Between chips.
    static let chipGap: CGFloat = 8

    // MARK: Sizes
    /// Filter chips' visual height (Main.dc: 34).
    static let chipHeight: CGFloat = 36
    /// A slim action row's minimum height (Main.dc: 54–56).
    static let slimRowHeight: CGFloat = 56
    /// The tab bar's row, above the home indicator.
    static let tabBarHeight: CGFloat = 56
    /// The + in the tab bar.
    static let addButton: CGFloat = 52
    /// Primary buttons in sheets (54–58).
    static let primaryButtonHeight: CGFloat = 54

    /// Minimum tap target. Chips keep their small visual size and expand the
    /// hit area instead.
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

// `CategoryPalette`, `Topic.palette` and `NeutralPalette` live in
// Core/QuickFile/TopicPalette.swift, so the Share Extension can use them too.

// MARK: - Platform brand

extension Platform {
    /// Badge background. Instagram is a gradient, everything else a flat fill.
    var badgeColors: [Color] {
        switch self {
        case .x: [Color(hex: "0F1014")]
        case .instagram: [Color(hex: "833AB4"), Color(hex: "C13584"), Color(hex: "F77737")]
        case .tiktok: [Color(hex: "0D0E12")]
        case .youtube: [Color(hex: "CC1B2B")]
        case .shorts: [Color(hex: "FF0033")]
        case .threads: [Color(hex: "141416")]
        case .pinterest: [Color(hex: "B8121F")]
        case .grok: [Color(hex: "111113")]
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
        case .instagram: [Color(hex: "833AB4"), Color(hex: "C13584"), Color(hex: "F77737")]
        case .youtube: [Color(hex: "B3121F"), Color(hex: "5E0A12")]
        case .shorts: [Color(hex: "C11723"), Color(hex: "5E0A12")]
        case .threads: [Color(hex: "1B1B1E"), Color(hex: "000000")]
        case .pinterest: [Color(hex: "A50F1B"), Color(hex: "4E070D")]
        case .grok: [Color(hex: "1A1A1D"), Color(hex: "000000")]
        case .web: [Color(hex: "3E4550"), Color(hex: "20242B")]
        }
    }
}

// MARK: - Reusable surfaces

/// A card or row: white, a 1 pt hairline, radius 18, **no shadow**
/// (SYSTEM.md: "Calm surfaces"). Only things that truly float cast a shadow —
/// see `Lift`.
///
/// `strong:` is ignored; it is kept so 1.3 call sites still compile.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Tokens.cardRadius
    var strong: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            .background(Tokens.surface, in: shape)
            .overlay(shape.strokeBorder(Tokens.hairline, lineWidth: 1))
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

/// The two bundled faces (App/Fonts, `UIAppFonts` in project.yml): Bricolage
/// Grotesque for display, Instrument Sans for everything else.
///
/// **Nothing bolder than 700.** `.heavy` and `.black` are mapped to `.bold`
/// here, so every 1.3 call site that asked for 800/900 now gets 700 without
/// being touched. New code should use `TextRole` instead of sizes.
enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Bricolage Grotesque", size: size).weight(capped(weight))
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Instrument Sans", size: size).weight(capped(weight))
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// 800 and 900 become 700.
    static func capped(_ weight: Font.Weight) -> Font.Weight {
        weight == .heavy || weight == .black ? .bold : weight
    }
}

/// The type roles of design/SYSTEM.md. Use `.textRole(_:)` on a `Text` (or any
/// view) rather than picking sizes; every role scales with Dynamic Type through
/// `Font.custom(_:size:relativeTo:)`.
///
/// | role | face | size/line | relative to |
/// |---|---|---|---|
/// | screenTitle | Bricolage 700 | 30/34, −0.6 tracking | largeTitle |
/// | sectionTitle | Bricolage 700 | 19/24 | title3 |
/// | cardTitle | Instrument 600 | 15/20 | subheadline |
/// | body | Instrument 500 | 15/21 | body |
/// | meta | Instrument 500 | 13/18, secondary | footnote |
/// | label | Instrument 700 | 11/14, +0.88 tracking, caps | caption2 |
/// | chip | Instrument 600 | 14/18 | subheadline |
/// | button | Instrument 600 | 16/20 | body |
enum TextRole: CaseIterable, Sendable {
    case screenTitle, sectionTitle, cardTitle, body, meta, label, chip, button

    var size: CGFloat {
        switch self {
        case .screenTitle: 30
        case .sectionTitle: 19
        case .cardTitle, .body: 15
        case .meta: 13
        case .label: 11
        case .chip: 14
        case .button: 16
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .screenTitle: 34
        case .sectionTitle: 24
        case .cardTitle: 20
        case .body: 21
        case .meta: 18
        case .label: 14
        case .chip: 18
        case .button: 20
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenTitle, .sectionTitle, .label: .bold
        case .cardTitle, .chip, .button: .semibold
        case .body, .meta: .medium
        }
    }

    var tracking: CGFloat {
        switch self {
        case .screenTitle: -0.6
        case .label: 0.88
        default: 0
        }
    }

    var isDisplay: Bool { self == .screenTitle || self == .sectionTitle }

    var textStyle: Font.TextStyle {
        switch self {
        case .screenTitle: .largeTitle
        case .sectionTitle: .title3
        case .cardTitle, .chip: .subheadline
        case .body, .button: .body
        case .meta: .footnote
        case .label: .caption2
        }
    }

    /// The colour the role carries by default; nil inherits.
    var defaultColor: Color? { self == .meta ? Tokens.inkSecondary : nil }

    /// The role's font, for `Text` concatenation and places a modifier can't go.
    var font: Font {
        .custom(isDisplay ? "Bricolage Grotesque" : "Instrument Sans", size: size, relativeTo: textStyle)
            .weight(weight)
    }
}

private struct TextRoleModifier: ViewModifier {
    let role: TextRole
    let color: Color?

    func body(content: Content) -> some View {
        let styled = content
            .font(role.font)
            .tracking(role.tracking)
            .lineSpacing(max(0, role.lineHeight - role.size * 1.2))
            .textCase(role == .label ? .uppercase : nil)
        if let color = color ?? role.defaultColor {
            styled.foregroundStyle(color)
        } else {
            styled
        }
    }
}

extension View {
    /// Sets a SYSTEM.md type role: font (Dynamic Type aware), tracking, line
    /// spacing, caps for `.label`, and the role's colour (`.meta` is
    /// secondary) unless `color` is given.
    func textRole(_ role: TextRole, color: Color? = nil) -> some View {
        modifier(TextRoleModifier(role: role, color: color))
    }
}

// MARK: - Elevation

/// The only shadows in the system: for things that truly float. Cards, rows,
/// chips and the tab bar never get one (SYSTEM.md, "Shadows").
enum Lift: Sendable {
    /// Wheel slabs and the refine panel: warm drop `0 10 24 rgba(120,84,50,.12)`
    /// plus, with `lift(_:in:)`, the inner top highlight.
    case slab
    /// Small raised pills on a slab (B's refine chips): `0 3 8 /.10`.
    case pill
    /// The wheel's hub: `0 14 28 /.20` + `0 2 4 /.10`.
    case hub
    /// A lit or chosen slab, in its own deep colour: `0 8 14 /.28`.
    case lit(Color)
    /// Sheets drawn in-page (not system sheets): `0 -8 30 rgba(25,21,16,.10)`.
    case sheet
    /// Toasts.
    case toast
}

private struct LiftModifier: ViewModifier {
    let lift: Lift

    func body(content: Content) -> some View {
        switch lift {
        case .slab:
            content.shadow(color: Brand.shadow.opacity(0.12), radius: 12, y: 10)
        case .pill:
            content.shadow(color: Brand.shadow.opacity(0.10), radius: 4, y: 3)
        case .hub:
            content
                .shadow(color: Brand.shadow.opacity(0.10), radius: 2, y: 2)
                .shadow(color: Brand.shadow.opacity(0.20), radius: 14, y: 14)
        case .lit(let colour):
            content.shadow(color: colour.opacity(0.28), radius: 7, y: 8)
        case .sheet:
            content.shadow(color: Brand.ink.opacity(0.10), radius: 15, y: -8)
        case .toast:
            content.shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
    }
}

extension View {
    /// Casts the `Lift`'s shadow. Use only on things that float.
    func lift(_ lift: Lift) -> some View {
        modifier(LiftModifier(lift: lift))
    }

    /// The shadow plus the inner top highlight
    /// (`inset 0 1px 0 rgba(255,255,255,.7)`) inside `shape`, as B's slabs,
    /// pills and hub have it.
    func lift<S: Shape>(_ lift: Lift, in shape: S) -> some View {
        self
            .overlay {
                shape
                    .stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14)),
                            lineWidth: 2)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .modifier(LiftModifier(lift: lift))
    }
}
