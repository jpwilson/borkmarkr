import Foundation

// The clay palette: every topic's three colours, from its hue.
//
// Foundation only, so `swiftc` compiles it on a Mac with no simulator
// (Scripts/test_clay_palette.swift), and so `docs/palette.js` can be a
// line-for-line port. The two must agree byte for byte; the fixture
// `Scripts/fixtures/clay_palette_cases.json` is what holds them together.
//
// **The recipe** (design/SYSTEM.md, "Topic colours: the clay palette"):
//
// 1. A topic keeps its own hue. Its stored hue h (degrees, `Topic.hue`,
//    `CustomTopic.hue`) is turned into today's dot colour, sRGB HSB(h, .5, .7),
//    and that colour's OKLCH hue is where the topic sits on the circle.
// 2. The anchor table is the seven coloured rows of SYSTEM.md, each measured in
//    OKLCH and pinned at the circle position of the topic the row was drawn for
//    (Health → Rose, Cars & motors → Terracotta, Recipes → Ochre, Garden → Sage,
//    Nutrition → Teal, Travel → Dusty blue, AI → Lilac). Between two anchors,
//    L, C and H of each role (tint, mid, deep) are interpolated linearly,
//    wrapping round the circle. So those seven topics land on their rows, and
//    every other hue lands between the two rows either side of it.
// 3. Back to sRGB. A colour outside the gamut keeps its L and H and has its
//    chroma binary-searched down (24 halvings, deterministic).
// 4. Gamma-encode, round each channel to 8 bits.
//
// Sand is not on the circle: it is the "not filed" colour (Unfiled, More…, the
// ground under clay art) and is the SYSTEM.md row exactly.
//
// Contrast (pinned by the tests over every integer hue, every built-in and
// Sand): deep on tint ≥ 4.5:1 and white on deep ≥ 4.5:1. White never sits on
// mid — mid is for dots, rings and small fills.

/// One sRGB colour, 8 bits a channel.
struct ClayRGB: Equatable, Hashable, Sendable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    /// `"#RRGGBB"` or `"RRGGBB"`. Anything else is black, never a crash.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = digits.count == 6 ? (UInt32(digits, radix: 16) ?? 0) : 0
        r = UInt8((value >> 16) & 0xFF)
        g = UInt8((value >> 8) & 0xFF)
        b = UInt8(value & 0xFF)
    }

    /// `"#RRGGBB"`, upper case — the form the fixture and `palette.js` use.
    var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Channels as 0…1, for `Color(.sRGB, red:green:blue:)`.
    var red: Double { Double(r) / 255 }
    var green: Double { Double(g) / 255 }
    var blue: Double { Double(b) / 255 }

    static let white = ClayRGB(r: 255, g: 255, b: 255)
}

/// A topic's three colours.
struct ClayColours: Equatable, Sendable {
    /// Surfaces: chips, slabs, the tint footer. Text on it is `deep`.
    let tint: ClayRGB
    /// The 8 pt dot, rings, small fills. Never under white text.
    let mid: ClayRGB
    /// Text on `tint`; the fill behind white text (a selected chip, a lit slab).
    let deep: ClayRGB
}

enum ClayRecipe {

    // MARK: The reference rows (design/SYSTEM.md)

    /// A SYSTEM.md row and the stored topic hue it is pinned to.
    struct Reference: Sendable {
        let family: String
        /// The built-in topic hue that lands on this row; nil for Sand.
        let topicHue: Double?
        let colours: ClayColours
    }

    private static func row(_ family: String, _ hue: Double?, _ tint: String, _ mid: String, _ deep: String) -> Reference {
        Reference(family: family, topicHue: hue,
                  colours: ClayColours(tint: ClayRGB(hex: tint), mid: ClayRGB(hex: mid), deep: ClayRGB(hex: deep)))
    }

    /// The anchors, in SYSTEM.md's words, then Sand. Hues are the topics in
    /// `Core/Taxonomy.swift`: Health 352, Cars & motors 11, Recipes 42,
    /// Garden 96, Nutrition 146, Travel 202, AI 256.
    static let references: [Reference] = [
        row("Rose", 352, "#F4DCDD", "#D48A8F", "#7A3338"),
        row("Terracotta", 11, "#F3DDD2", "#C8674A", "#7A3420"),
        row("Ochre", 42, "#F4E6C4", "#D9A441", "#6E4E0E"),
        row("Sage", 96, "#E3EADB", "#8FA37E", "#3F5237"),
        row("Teal", 146, "#D8EAE6", "#6FA89C", "#2C5A50"),
        row("Dusty blue", 202, "#DCE7F0", "#7FA3C2", "#2F4E68"),
        row("Lilac", 256, "#E6DFF0", "#9A86BF", "#4A3A70"),
        row("Sand", nil, "#ECE5D8", "#B5A68A", "#5A4E38"),
    ]

    /// Not filed yet, More…, the ground under clay art: the Sand row exactly.
    static let neutral = ClayColours(
        tint: ClayRGB(hex: "#ECE5D8"), mid: ClayRGB(hex: "#B5A68A"), deep: ClayRGB(hex: "#5A4E38"))

    // MARK: The recipe

    /// A role's colour in OKLCH: lightness, chroma, hue in degrees.
    private struct LCH { let l: Double; let c: Double; let h: Double }

    private struct Anchor {
        /// Where the anchor sits on the circle: `okHue(forTopicHue:)` of its topic.
        let at: Double
        let tint: LCH
        let mid: LCH
        let deep: LCH
    }

    /// Built once, in circle order.
    private static let anchors: [Anchor] = references
        .compactMap { ref -> Anchor? in
            guard let hue = ref.topicHue else { return nil }
            return Anchor(at: okHue(forTopicHue: hue),
                          tint: lch(ref.colours.tint), mid: lch(ref.colours.mid), deep: lch(ref.colours.deep))
        }
        .sorted { $0.at < $1.at }

    /// The OKLCH hue (0..<360) of sRGB HSB(h, 0.5, 0.7) — today's dot colour.
    static func okHue(forTopicHue hue: Double) -> Double {
        let (r, g, b) = hsb(hue, 0.5, 0.7)
        let lab = toOKLab(r, g, b)
        return degrees(lab.a, lab.b)
    }

    /// A topic's colours from its stored hue.
    static func colours(hue: Double) -> ClayColours {
        let at = okHue(forTopicHue: hue)
        return ClayColours(
            tint: encode(role(at, \.tint)),
            mid: encode(role(at, \.mid)),
            deep: encode(role(at, \.deep)))
    }

    /// WCAG 2 contrast ratio, 1…21.
    static func contrast(_ a: ClayRGB, _ b: ClayRGB) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    // MARK: Interpolation

    /// One role's colour at circle position `at`, between the anchors either side.
    private static func role(_ at: Double, _ pick: KeyPath<Anchor, LCH>) -> LCH {
        let n = anchors.count
        var i = n - 1
        for j in 0..<n where anchors[j].at <= at { i = j }
        let a = anchors[i], b = anchors[(i + 1) % n]
        let h0 = a.at
        var h1 = b.at
        if h1 <= h0 { h1 += 360 }
        var x = at
        if x < h0 { x += 360 }
        let t = (x - h0) / (h1 - h0)
        let p = a[keyPath: pick], q = b[keyPath: pick]
        var qh = q.h
        if qh < p.h { qh += 360 }
        let h = (p.h + (qh - p.h) * t).truncatingRemainder(dividingBy: 360)
        return LCH(l: p.l + (q.l - p.l) * t, c: p.c + (q.c - p.c) * t, h: h)
    }

    // MARK: Colour maths (OKLab, Björn Ottosson 2020)

    private static func lch(_ rgb: ClayRGB) -> LCH {
        let lab = toOKLab(rgb.red, rgb.green, rgb.blue)
        return LCH(l: lab.l, c: (lab.a * lab.a + lab.b * lab.b).squareRoot(), h: degrees(lab.a, lab.b))
    }

    /// OKLCH → 8-bit sRGB, chroma reduced until it fits.
    private static func encode(_ colour: LCH) -> ClayRGB {
        let rad = colour.h * Double.pi / 180
        let ca = cos(rad), sa = sin(rad)
        func linear(_ c: Double) -> (Double, Double, Double) {
            fromOKLab(colour.l, c * ca, c * sa)
        }
        var rgb = linear(colour.c)
        if !inGamut(rgb) {
            var lo = 0.0, hi = colour.c
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if inGamut(linear(mid)) { lo = mid } else { hi = mid }
            }
            rgb = linear(lo)
        }
        return ClayRGB(r: byte(rgb.0), g: byte(rgb.1), b: byte(rgb.2))
    }

    private static func inGamut(_ c: (Double, Double, Double)) -> Bool {
        c.0 >= 0 && c.0 <= 1 && c.1 >= 0 && c.1 <= 1 && c.2 >= 0 && c.2 <= 1
    }

    /// Linear-light channel → 8-bit sRGB.
    private static func byte(_ linear: Double) -> UInt8 {
        let c = min(1, max(0, linear))
        let encoded = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8((min(1, max(0, encoded)) * 255).rounded())
    }

    private static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Gamma-encoded sRGB (0…1) → OKLab.
    private static func toOKLab(_ red: Double, _ green: Double, _ blue: Double) -> (l: Double, a: Double, b: Double) {
        let r = toLinear(red), g = toLinear(green), b = toLinear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// OKLab → linear-light sRGB (may fall outside 0…1).
    private static func fromOKLab(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let l1 = L + 0.3963377774 * a + 0.2158037573 * b
        let m1 = L - 0.1055613458 * a - 0.0638541728 * b
        let s1 = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l1 * l1 * l1, m = m1 * m1 * m1, s = s1 * s1 * s1
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// HSB (HSV) → sRGB 0…1, as SwiftUI's `Color(hue:saturation:brightness:)`.
    private static func hsb(_ hue: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let wrapped = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let x = wrapped / 60
        let i = Int(x.rounded(.down))
        let f = x - Double(i)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// atan2 in degrees, 0..<360.
    private static func degrees(_ a: Double, _ b: Double) -> Double {
        let d = atan2(b, a) * 180 / Double.pi
        return d < 0 ? d + 360 : d
    }

    private static func luminance(_ c: ClayRGB) -> Double {
        0.2126 * toLinear(c.red) + 0.7152 * toLinear(c.green) + 0.0722 * toLinear(c.blue)
    }
}
