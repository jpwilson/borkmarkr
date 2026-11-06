import SwiftUI

// Moved verbatim from App/DesignSystem/Tokens.swift so the Share Extension,
// which compiles Core but not App, draws topics in exactly the app's colours.
// Quick File's dial, its chips and its picker all colour from here.

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
