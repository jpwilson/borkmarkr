import SwiftUI

// A topic's colours as SwiftUI `Color`s, for the app and the Share Extension
// (which compiles Core but not App). The maths is `ClayRecipe` in
// Core/ClayPalette.swift — Foundation only, ported line for line to
// docs/palette.js — so a topic is the same colour on the phone and the web.

// MARK: - Topic colour

/// A topic's clay colours (design/SYSTEM.md, "Topic colours: the clay palette").
///
/// - `tint`: surfaces — chips, slabs, tile footers. Text on it is `deep`.
/// - `mid`: the 8 pt dot, rings, small fills. **Never put white text on it.**
/// - `deep`: text on `tint`, and the fill behind white text (selected chip,
///   lit slab, check badge).
///
/// Built from the exact bytes `ClayRecipe` gives, via `Color(.sRGB, …)`, so the
/// phone draws the hex the web draws. Built once per built-in topic (see
/// `Topic.palettes`).
struct CategoryPalette: Sendable {
    let tint: Color
    let mid: Color
    let deep: Color
    /// The bytes behind the colours, for contrast checks and the web.
    let clay: ClayColours

    init(_ clay: ClayColours) {
        self.clay = clay
        tint = Self.color(clay.tint)
        mid = Self.color(clay.mid)
        deep = Self.color(clay.deep)
    }

    init(hue: Double) {
        self.init(ClayRecipe.colours(hue: hue))
    }

    /// The dot colour — the old name for `mid`.
    var dot: Color { mid }

    /// Covers now use clay art, never a gradient. Kept so 1.3 call sites
    /// compile until their owners move off them; the lead removes these last.
    @available(*, deprecated, message: "Covers use ClayCover / clay art now; use mid.")
    var coverTop: Color { mid }
    @available(*, deprecated, message: "Covers use ClayCover / clay art now; use deep.")
    var coverBottom: Color { deep }

    /// Sand: Unfiled, More…, the ground under clay art.
    static let neutral = CategoryPalette(ClayRecipe.neutral)

    private static func color(_ c: ClayRGB) -> Color {
        Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }
}

extension Topic {
    /// Built once for all 50 topics, immutably — a `static let` is initialised
    /// lazily and thread-safely by the runtime, so this needs no lock and is
    /// concurrency-safe under Swift 6 strict checking.
    private static let palettes: [String: CategoryPalette] = Dictionary(
        uniqueKeysWithValues: Taxonomy.all.map { ($0.id, CategoryPalette(hue: $0.hue)) }
    )

    var palette: CategoryPalette {
        Topic.palettes[id] ?? CategoryPalette(hue: hue)
    }
}

/// The palette for things not filed yet: Sand, deliberately quiet, so it reads
/// as "not filed" rather than as a topic of its own.
enum NeutralPalette {
    static let value = CategoryPalette.neutral
}
