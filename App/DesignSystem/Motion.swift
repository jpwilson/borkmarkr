import SwiftUI
import UIKit

/// The difference between an app that looks designed and one that feels
/// designed is almost entirely here: things respond when you touch them.
///
/// Static screenshots can't show it, which is why prototypes rarely specify it —
/// but a card that doesn't move under your thumb reads as a picture of an app.

/// Presses in slightly and dims. Applied to every tappable card and row.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Chips and pills — snappier and shallower than a card.
struct ChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Standard easing for anything that isn't a press. Kept in one place so the
/// app moves at a consistent speed rather than each screen inventing its own.
enum Motion {
    static let snap = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let gentle = Animation.easeOut(duration: 0.22)
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

/// Physical feedback for the moments that matter — saving, ticking a habit,
/// switching a filter. Deliberately sparse: haptics everywhere is noise, and
/// noise is worse than silence.
/// Generators are created per call rather than held as statics: UIKit feedback
/// generators are main-actor isolated, and a `static let` of one is global
/// mutable state that Swift 6 strict concurrency rightly rejects. Construction
/// is cheap.
@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// A soft radial glow behind a hero element. Cheap depth — the flat, evenly-lit
/// look is what made the first build read as a wireframe.
struct Glow: ViewModifier {
    var color: Color
    var radius: CGFloat = 90
    var opacity: Double = 0.22

    func body(content: Content) -> some View {
        content.background(
            Circle()
                .fill(color.opacity(opacity))
                .frame(width: radius * 2, height: radius * 2)
                .blur(radius: radius * 0.7)
        )
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 90, opacity: Double = 0.22) -> some View {
        modifier(Glow(color: color, radius: radius, opacity: opacity))
    }

    /// Fades and slides content up as it appears — used for feed items so a
    /// screen assembles rather than snapping into place.
    func riseIn(_ index: Int = 0) -> some View {
        modifier(RiseIn(index: index))
    }
}

private struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                // Stagger only the first handful — a long list shouldn't take
                // two seconds to finish arriving.
                let delay = Double(min(index, 6)) * 0.035
                withAnimation(.easeOut(duration: 0.32).delay(delay)) { shown = true }
            }
    }
}
