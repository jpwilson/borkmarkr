import SwiftUI
import UIKit

// MARK: - The dial

/// Quick File's click wheel: the best guess in the centre, six more round the
/// ring, More… at 10:30, and one more tap to file.
///
/// It is built to feel like a hardware control. Turning is relative, like a
/// click wheel: drag round the ring anywhere and every 45° is one detent, with
/// 8° of slack so a resting thumb never chatters between two. Each detent
/// ticks (`.selection`, never closer than 45 ms), the lit slab fills with its
/// topic's deep colour and lifts a few points off the ring, and the centre
/// slides 6 pt the way you turned. A tap files: the centre files what it
/// shows, a slab files that topic. Filing presses the hub in, folds the ring
/// away, closes the evidence ring and draws the check, with one firm `.impact`.
///
/// The look is design/SYSTEM.md's direction B, "Quiet clay": eight clay slabs
/// in their topics' tints, each with its clay object in a disc and the topic
/// and subtopic in the deep colour; a raised white hub with the topic's art.
/// No gradients, no backplate, no bead: the lit slab is the cue.
///
/// The ring never rotates and its slabs never reorder under a thumb. With
/// Reduce Motion everything is a short crossfade; at accessibility text sizes
/// the dial becomes a ranked list; under VoiceOver it is one adjustable
/// element (swipe up or down to turn, double-tap to file).
///
/// On the Add and share sheets (`QuickFileModel.Mode.refine`) a filing
/// chooses rather than folds: the ring stays live, the chosen topic's slab
/// wears a small check, and the hub shows the choice with its check whenever
/// the light is on it. Turning away shows another topic, which a tap files
/// instead.
struct QuickFileDial: View {
    let model: QuickFileModel
    var style: QuickFileStyle
    var diameter: CGFloat
    /// VoiceOver's "Not now" action. Nil leaves it out.
    var onLater: (() -> Void)?
    /// VoiceOver's "Done" action once something is chosen. Nil leaves it out.
    var onDone: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: QuickFileModel, style: QuickFileStyle = .system, diameter: CGFloat = 300,
         onLater: (() -> Void)? = nil, onDone: (() -> Void)? = nil) {
        self.model = model
        self.style = style
        self.diameter = diameter
        self.onLater = onLater
        self.onDone = onDone
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            QuickFileRankedList(model: model, style: style)
        } else {
            QuickFileRing(model: model, style: style, diameter: diameter, onLater: onLater, onDone: onDone)
                // Fixed geometry: the slabs can't grow with the text.
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }
}

// MARK: - Geometry

/// Where everything on a dial of a given diameter sits. Angles are measured
/// clockwise from 12 o'clock.
///
/// Referenced to direction B's 360 pt artboard (B-QuickFile.dc.html), so its
/// numbers copy straight across: B draws each slab to r 159 / r 85 with an
/// 18 pt round-join stroke, so the visible slab runs from 76 to 168 with 9 pt
/// corners and a 7 pt parallel gap. Hit regions follow the same radii
/// (`Tests/QuickFileDialGeometryTests.swift` pins them).
struct QuickFileDialGeometry {
    let size: CGFloat

    /// B's artboard.
    static let reference: CGFloat = 360

    init(diameter: CGFloat) { size = diameter }

    /// 1 at the 360 pt reference size.
    var scale: CGFloat { size / Self.reference }
    var centre: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    /// The slabs' outer edge, leaving room at the rim for the lit one to lift.
    var outer: CGFloat { 168 * scale }
    var inner: CGFloat { 76 * scale }
    /// The raised white hub (B: a 132 pt disc).
    var hub: CGFloat { 66 * scale }
    /// Between neighbouring slabs, parallel-sided.
    var gap: CGFloat { 7 * scale }
    var corner: CGFloat { 9 * scale }
    /// How far a lit or chosen slab lifts off the ring, outward.
    var lift: CGFloat { 5 * scale }
    /// The evidence ring: 2 pt, just outside the hub.
    var ringWidth: CGFloat { 2 }
    var ringRadius: CGFloat { hub + 3 * scale }
    /// The clay object on each slab, and the hub's.
    var slabArt: CGFloat { 36 * scale }
    var hubArt: CGFloat { 84 * scale }
    var badge: CGFloat { 30 * scale }
    var labelWidth: CGFloat { 96 * scale }
    var labelHeight: CGFloat { 84 * scale }
    /// The slab labels' text follows the dial down only so far: on a small
    /// dial (triage, a short sheet) B's 9.5 pt caps would fall under 8.2 pt.
    /// Past that, the label's minimum scale factor fits the box instead.
    var textScale: CGFloat { max(scale, 0.86) }
    /// Closer to the centre than this, a finger's angle is too jumpy to turn by.
    var steadyRadius: CGFloat { size * 0.12 }

    /// A centre tap: inside the hub and halfway across the gap to the slabs.
    var hubReach: CGFloat { (hub + inner) / 2 }
    /// Taps a little past the rim still count as the slab's.
    var rimReach: CGFloat { outer + 16 * scale }

    /// The label's centre. B sets the 96 × 84 label boxes a little further out
    /// at 12 and 6 o'clock (r 124) than at 3 and 9 (r 117), so the tall stack
    /// sits square in the slab whichever way it runs.
    func labelRadius(seat: Int) -> CGFloat {
        (121 + 3.5 * CGFloat(cos(Double(seat) * .pi / 2))) * scale
    }

    func labelPoint(seat: Int) -> CGPoint {
        point(degrees: Double(seat) * 45, radius: labelRadius(seat: seat))
    }

    /// The lit slab's offset: straight out from the centre.
    func liftOffset(seat: Int) -> CGSize {
        let p = point(degrees: Double(seat) * 45, radius: lift)
        return CGSize(width: p.x - centre.x, height: p.y - centre.y)
    }

    func distance(_ point: CGPoint) -> CGFloat {
        hypot(point.x - centre.x, point.y - centre.y)
    }

    /// Radians clockwise from 12 o'clock, −π…π.
    func angle(of point: CGPoint) -> Double {
        atan2(Double(point.x - centre.x), Double(centre.y - point.y))
    }

    func point(degrees: Double, radius: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: centre.x + radius * CGFloat(sin(radians)),
                       y: centre.y - radius * CGFloat(cos(radians)))
    }

    func region(at point: CGPoint) -> QuickFileDialRegion {
        let r = distance(point)
        if r <= hubReach { return .hub }
        guard r <= rimReach else { return .outside }
        let degrees = angle(of: point) * 180 / .pi
        let turned = (degrees + 22.5 + 720).truncatingRemainder(dividingBy: 360)
        return .seat(Int(turned / 45) % 8)
    }
}

enum QuickFileDialRegion: Equatable {
    case hub, seat(Int), outside
}

/// The drag maths, in a reference type so following a finger doesn't
/// re-render the dial; only a detent does.
@MainActor
final class QuickFileDragTracker {
    private(set) var active = false
    var turning = false
    private(set) var region: QuickFileDialRegion = .outside
    private var lastAngle: Double?
    private var turned: Double = 0
    private var detents = 0

    static let detent = Double.pi / 4
    static let slack = 8 * Double.pi / 180
    /// Under this, a touch is a tap.
    static let tapTravel: CGFloat = 10

    func begin(at point: CGPoint, geometry g: QuickFileDialGeometry) {
        active = true
        turning = false
        region = g.region(at: point)
        turned = 0
        detents = 0
        lastAngle = g.distance(point) > g.steadyRadius ? g.angle(of: point) : nil
    }

    /// Follows the finger and returns the detents it crossed (signed).
    func follow(_ point: CGPoint, geometry g: QuickFileDialGeometry) -> Int {
        guard g.distance(point) > g.steadyRadius else {
            lastAngle = nil
            return 0
        }
        let angle = g.angle(of: point)
        if let last = lastAngle {
            var delta = angle - last
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            turned += delta
        }
        lastAngle = angle
        guard turning else { return 0 }
        var crossed = 0
        while turned > (Double(detents) + 0.5) * Self.detent + Self.slack { detents += 1; crossed += 1 }
        while turned < (Double(detents) - 0.5) * Self.detent - Self.slack { detents -= 1; crossed -= 1 }
        return crossed
    }

    func reset() {
        active = false
        turning = false
        region = .outside
        lastAngle = nil
        turned = 0
        detents = 0
    }
}

// MARK: - Shapes

/// One slab of the ring: an annular sector with parallel-sided gaps to its
/// neighbours and softly rounded corners, like a keycap of clay.
struct QuickFileSlab: Shape {
    var seat: Int
    var inner: CGFloat
    var outer: CGFloat
    var gap: CGFloat
    var corner: CGFloat

    init(seat: Int, geometry g: QuickFileDialGeometry) {
        self.init(seat: seat, inner: g.inner, outer: g.outer, gap: g.gap, corner: g.corner)
    }

    init(seat: Int, inner: CGFloat, outer: CGFloat, gap: CGFloat, corner: CGFloat) {
        self.seat = seat
        self.inner = inner
        self.outer = outer
        self.gap = gap
        self.corner = corner
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI angles: 0 at 3 o'clock, increasing clockwise on screen.
        let mid = (Double(seat) * 45 - 90) * .pi / 180
        let half = 22.5 * .pi / 180
        let inset = Double(gap / 2)
        let a0o = mid - half + asin(inset / Double(outer)), a1o = mid + half - asin(inset / Double(outer))
        let a0i = mid - half + asin(inset / Double(inner)), a1i = mid + half - asin(inset / Double(inner))

        func at(_ angle: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: c.x + radius * CGFloat(cos(angle)), y: c.y + radius * CGFloat(sin(angle)))
        }
        func unit(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y
            let length = max(hypot(dx, dy), 0.0001)
            return CGPoint(x: dx / length, y: dy / length)
        }
        func step(_ p: CGPoint, _ d: CGPoint, _ length: CGFloat) -> CGPoint {
            CGPoint(x: p.x + d.x * length, y: p.y + d.y * length)
        }

        let outerStart = at(a0o, outer), outerEnd = at(a1o, outer)
        let innerEnd = at(a1i, inner), innerStart = at(a0i, inner)
        let reach = corner * 2
        let r = min(corner, (outer - inner) / 3)

        var path = Path()
        path.move(to: CGPoint(x: (innerStart.x + outerStart.x) / 2, y: (innerStart.y + outerStart.y) / 2))
        // Up the leading edge, round onto the rim.
        path.addArc(tangent1End: outerStart,
                    tangent2End: step(outerStart, CGPoint(x: -sin(a0o), y: cos(a0o)), reach), radius: r)
        path.addArc(center: c, radius: outer,
                    startAngle: .radians(a0o + Double(r / outer)), endAngle: .radians(a1o - Double(r / outer)),
                    clockwise: false)
        // Round down the trailing edge.
        path.addArc(tangent1End: outerEnd, tangent2End: step(outerEnd, unit(outerEnd, innerEnd), reach), radius: r)
        path.addArc(tangent1End: innerEnd,
                    tangent2End: step(innerEnd, CGPoint(x: sin(a1i), y: -cos(a1i)), reach), radius: r)
        path.addArc(center: c, radius: inner,
                    startAngle: .radians(a1i - Double(r / inner)), endAngle: .radians(a0i + Double(r / inner)),
                    clockwise: true)
        path.addArc(tangent1End: innerStart, tangent2End: step(innerStart, unit(innerStart, outerStart), reach),
                    radius: r)
        path.closeSubpath()
        return path
    }
}

/// A shape's top edge, `depth` deep: what is left of it once a copy moved
/// down by `depth` is cut away. B's `inset 0 1px 0 rgba(255,255,255,.7)`
/// highlight (its `bInner` filter), drawn as a path rather than a filter.
struct QuickFileTopEdge<Base: Shape>: Shape {
    var base: Base
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        let full = base.path(in: rect)
        return full.subtracting(full.offsetBy(dx: 0, dy: depth))
    }
}

/// The confirm tick, drawn by trimming.
struct QuickFileCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.41, y: rect.minY + rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.22))
        return path
    }
}

/// A topic's clay picture in a circle, or its tint and initial when there is
/// no picture to be had.
struct QuickFileArtDisc: View {
    let topicID: String
    let size: CGFloat
    var style: QuickFileStyle = .system

    var body: some View {
        let palette = QuickFileStyle.palette(for: topicID)
        Group {
            if let image = style.art(topicID) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    palette.tint
                    Text(QuickFileCopy.initial(topicID))
                        .font(style.display(size * 0.44))
                        .foregroundStyle(palette.deep)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// B's shadows, in Core so the Share Extension draws the same depth as the
/// app (the app's `Lift` lives in App/, which the extension doesn't compile).
enum QuickFileDepth {
    static let warm = Brand.shadow
    /// The ring of resting slabs: `feDropShadow dy 8, σ 9, .16`.
    static let ringOpacity = 0.16
    /// A lit slab, in its own deep colour: `dy 8, σ 7, .28`.
    static let litOpacity = 0.28
}

// MARK: - The ring

private struct QuickFileRing: View {
    let model: QuickFileModel
    let style: QuickFileStyle
    let diameter: CGFloat
    let onLater: (() -> Void)?
    let onDone: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var held: QuickFileDialRegion?
    @State private var tracker = QuickFileDragTracker()
    @State private var ringClosed: CGFloat = 0
    @State private var checkDrawn: CGFloat = 0
    @State private var bump: CGFloat = 1
    @State private var showsHint = QuickFileSettings.showsTapHint

    var body: some View {
        let g = QuickFileDialGeometry(diameter: diameter)
        ZStack {
            // One shadow for the whole ring, not eight.
            ZStack {
                ForEach(0..<8, id: \.self) { seat in
                    slab(seat, g)
                }
            }
            .frame(width: g.size, height: g.size)
            .compositingGroup()
            .shadow(color: QuickFileDepth.warm.opacity(QuickFileDepth.ringOpacity), radius: 9, y: 8)
            ForEach(0..<8, id: \.self) { seat in
                label(seat, g)
            }
            ForEach(0..<8, id: \.self) { seat in
                mark(seat, g)
            }
            hub(g)
                .zIndex(3)
        }
        .frame(width: g.size, height: g.size)
        .contentShape(Rectangle())
        .gesture(drag(g))
        .onAppear { appear() }
        .onChange(of: model.confirmations) { _, _ in landCheck() }
        .onChange(of: model.showsCheck) { _, shows in checkShown(shows) }
        .onChange(of: model.refinements) { _, _ in
            if let filed = model.filed { UIAccessibility.post(notification: .announcement, argument: QuickFileCopy.filed(filed)) }
        }
        .onChange(of: model.revision) { _, _ in
            if let line = model.updateAnnouncement {
                UIAccessibility.post(notification: .announcement, argument: line)
            }
        }
        .sensoryFeedback(.selection, trigger: model.tick)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.confirmations)
        .sensoryFeedback(.selection, trigger: model.undos)
        .sensoryFeedback(.selection, trigger: model.refinements)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuickFileCopy.dialLabel)
        .accessibilityValue(model.spokenValue)
        .accessibilityHint(model.centre.flatMap { model.reason(for: $0) } ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.turn(1)
            case .decrement: model.turn(-1)
            @unknown default: break
            }
        }
        .accessibilityAction { model.confirm() }
        .accessibilityActions {
            if model.isFolded {
                Button(QuickFileCopy.undo) { model.undo() }
            } else if model.isChosen {
                if let onDone {
                    Button(QuickFileCopy.done) { onDone() }
                }
                Button(QuickFileCopy.moreTopics) { model.more() }
            } else {
                Button(QuickFileCopy.moreTopics) { model.more() }
                if let onLater {
                    Button(QuickFileCopy.notNow) { onLater() }
                }
            }
        }
    }

    // MARK: Slabs

    private struct SeatState {
        let candidate: FilingCandidate?
        let isMore: Bool
        let lit: Bool
        let pressed: Bool
        let palette: CategoryPalette

        /// Resting: the topic's tint; More… off-white; an empty seat paper.
        var rest: Color {
            if isMore { return Brand.offWhite }
            return candidate != nil ? palette.tint : Brand.paper
        }
        /// Lit: the deep colour, behind white text.
        var deep: Color { isMore ? Brand.sandInk : palette.deep }
        /// Text on the resting slab.
        var ink: Color { isMore ? Brand.sandInk : palette.deep }
    }

    private func state(_ seat: Int) -> SeatState {
        let candidate = model.candidate(at: seat)
        return SeatState(
            candidate: candidate,
            isMore: seat == QuickFileModel.moreSlot,
            lit: !model.isFolded && model.highlighted == seat,
            pressed: held == .seat(seat),
            palette: candidate.map { QuickFileStyle.palette(for: $0.categoryID) } ?? NeutralPalette.value
        )
    }

    private func slab(_ seat: Int, _ g: QuickFileDialGeometry) -> some View {
        let s = state(seat)
        let shape = QuickFileSlab(seat: seat, geometry: g)
        return ZStack {
            shape.fill(s.rest)
            shape.fill(s.deep).opacity(s.lit ? 1 : 0)
            QuickFileTopEdge(base: shape, depth: 1.5 * g.scale)
                .fill(Color.white.opacity(s.lit ? 0.32 : 0.7))
        }
        .frame(width: g.size, height: g.size)
        .shadow(color: s.deep.opacity(s.lit ? QuickFileDepth.litOpacity : 0), radius: s.lit ? 7 : 0, y: s.lit ? 8 : 0)
        .modifier(seatMotion(seat, s, g))
        .zIndex(s.lit ? 1 : 0)
    }

    private func label(_ seat: Int, _ g: QuickFileDialGeometry) -> some View {
        let s = state(seat)
        let k = g.scale
        let colour = s.lit ? Color.white : s.ink
        return VStack(spacing: 0) {
            if s.isMore {
                ZStack {
                    Circle().fill(Color.white)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16 * k, weight: .medium))
                        .foregroundStyle(Brand.sandInk)
                }
                .frame(width: g.slabArt, height: g.slabArt)
                .shadow(color: QuickFileDepth.warm.opacity(0.16), radius: 5 * k, y: 4 * k)
                Color.clear.frame(height: 6 * k)
                caps(QuickFileCopy.allTopics, k: g.textScale, lit: s.lit)
                Color.clear.frame(height: 1 * k)
                Text("More…")
                    .font(style.ui(13.5 * g.textScale, .bold))
                    .lineLimit(1)
            } else if let candidate = s.candidate {
                QuickFileArtDisc(topicID: candidate.categoryID, size: g.slabArt, style: style)
                    .background(Circle().fill(Color.white).padding(-2 * k))
                    .shadow(color: QuickFileDepth.warm.opacity(0.20), radius: 5 * k, y: 4 * k)
                Color.clear.frame(height: 6 * k)
                let name = QuickFileCopy.topicName(candidate.categoryID)
                if let sub = candidate.subcategory {
                    caps(name, k: g.textScale, lit: s.lit)
                    Color.clear.frame(height: 1 * k)
                    Text(sub)
                        .font(style.ui(13.5 * g.textScale, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    Text(name)
                        .font(style.ui(13.5 * g.textScale, .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .foregroundStyle(colour)
        .multilineTextAlignment(.center)
        .frame(width: g.labelWidth, height: g.labelHeight)
        .id("\(seat)-\(model.revision)")
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.16), value: model.revision)
        .position(g.labelPoint(seat: seat))
        .frame(width: g.size, height: g.size)
        .modifier(seatMotion(seat, s, g))
        .zIndex(s.lit ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// The topic in small caps over its subtopic: 9.5 bold, +0.07 em.
    private func caps(_ text: String, k: CGFloat, lit: Bool) -> some View {
        Text(text.uppercased())
            .font(style.ui(9.5 * k, .bold))
            .tracking(0.665 * k)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .opacity(lit ? 0.86 : 1)
    }

    /// The chosen topic's small deep check once the light has turned away
    /// from its slab; otherwise a late ✨ for a topic the model just added.
    @ViewBuilder
    private func mark(_ seat: Int, _ g: QuickFileDialGeometry) -> some View {
        let s = state(seat)
        let chosenHere = model.isChosen && !s.lit && s.candidate != nil
            && model.filed?.categoryID == s.candidate?.categoryID
        let at = g.point(degrees: Double(seat) * 45 + 13, radius: g.outer - 14 * g.scale)
        ZStack {
            if chosenHere {
                slabCheck(g, palette: s.palette)
                    .position(at)
                    .transition(.scale.combined(with: .opacity))
            } else if let candidate = s.candidate, !model.isFolded, model.sparkle == candidate.categoryID {
                Text("✨")
                    .font(.system(size: 11 * g.scale))
                    .frame(width: 20 * g.scale, height: 20 * g.scale)
                    .background(Circle().fill(Color.white))
                    .shadow(color: QuickFileDepth.warm.opacity(0.2), radius: 3, y: 1)
                    .position(at)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: g.size, height: g.size)
        .animation(.easeOut(duration: 0.2), value: model.sparkle)
        .animation(.easeOut(duration: 0.18), value: chosenHere)
        .modifier(seatMotion(seat, s, g))
        .zIndex(2)
        .allowsHitTesting(false)
    }

    private func slabCheck(_ g: QuickFileDialGeometry, palette: CategoryPalette) -> some View {
        ZStack {
            Circle().fill(palette.deep)
            Circle().strokeBorder(Color.white, lineWidth: 2 * g.scale)
            QuickFileCheck()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2 * g.scale, lineCap: .round, lineJoin: .round))
                .frame(width: 9 * g.scale, height: 9 * g.scale)
        }
        .frame(width: 22 * g.scale, height: 22 * g.scale)
        .shadow(color: palette.deep.opacity(0.25), radius: 3, y: 2)
    }

    /// Lit lifts out; pressed sinks a little; appear, fold and Reduce Motion
    /// are the same for a slab, its label and its mark.
    private func seatMotion(_ seat: Int, _ s: SeatState, _ g: QuickFileDialGeometry) -> SeatMotion {
        SeatMotion(lift: s.lit ? g.liftOffset(seat: seat) : .zero, lit: s.lit, pressed: s.pressed,
                   folded: model.isFolded, appeared: appeared, reduceMotion: reduceMotion,
                   appearAnimation: appearAnimation(delay: Double(seat) * 0.018),
                   foldAnimation: model.isFolded ? .easeIn(duration: reduceMotion ? 0.12 : 0.16) : appearAnimation(delay: 0))
    }

    private struct SeatMotion: ViewModifier {
        let lift: CGSize
        let lit: Bool
        let pressed: Bool
        let folded: Bool
        let appeared: Bool
        let reduceMotion: Bool
        let appearAnimation: Animation
        let foldAnimation: Animation

        func body(content: Content) -> some View {
            content
                .offset(lift)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.74),
                           value: lit)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.1), value: pressed)
                .scaleEffect(reduceMotion ? 1 : (folded ? 0.82 : (appeared ? 1 : 0.9)))
                .opacity(folded ? 0 : (appeared ? 1 : 0))
                .animation(foldAnimation, value: folded)
                .animation(appearAnimation, value: appeared)
        }
    }

    // MARK: Hub

    private var hubKey: String {
        let shown = model.shown
        let seat = model.showsCheck ? "filed" : (model.highlighted.map(String.init) ?? "none")
        return "\(seat)|\(shown?.categoryID ?? "")|\(shown?.subcategory ?? "")|\(model.revision)"
    }

    private var hubTransition: AnyTransition {
        guard !reduceMotion, model.slides else { return .opacity }
        let shift = 6 * CGFloat(model.direction)
        return .asymmetric(insertion: .offset(x: -shift).combined(with: .opacity),
                           removal: .offset(x: shift).combined(with: .opacity))
    }

    /// How the hub lays out what it shows: the art alone (a slab is lit and
    /// says the rest), the art over the topic's name (nothing on the ring is
    /// lit, so the hub must say it), or the art over the first-use hint.
    private enum HubLayout { case art, named, hint }

    private func hubLayout(_ shown: FilingCandidate) -> HubLayout {
        if showsHint && model.filed == nil { return .hint }
        guard let seat = model.highlighted, let lit = model.candidate(at: seat),
              lit.categoryID == shown.categoryID else { return .named }
        return .art
    }

    /// The art's size and its centre's height above the hub's, per layout.
    private func hubArt(_ layout: HubLayout, _ g: QuickFileDialGeometry) -> (size: CGFloat, y: CGFloat) {
        switch layout {
        case .art: (g.hubArt, 0)
        case .named: (60 * g.scale, -13 * g.scale)
        case .hint: (66 * g.scale, -9 * g.scale)
        }
    }

    private func hub(_ g: QuickFileDialGeometry) -> some View {
        let shown = model.shown
        let onMore = shown == nil && model.isOnMore && !model.isFolded
        let art = shown.map { hubArt(hubLayout($0), g) } ?? (g.hubArt, 0)
        return ZStack {
            hubDisc(g)
            evidenceRing(g, shown: shown, onMore: onMore)
            hubContent(g, shown: shown, onMore: onMore)
                .id(hubKey)
                .transition(hubTransition)
            if model.showsCheck, let shown {
                checkBadge(g, palette: QuickFileStyle.palette(for: shown.categoryID), art: art)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: g.hub * 2, height: g.hub * 2)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.14), value: hubKey)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.62),
                   value: model.showsCheck)
        .scaleEffect(held == .hub && !reduceMotion ? 0.95 : bump)
        .animation(.easeOut(duration: 0.1), value: held == .hub)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(appearAnimation(delay: 0.04), value: appeared)
        .allowsHitTesting(false)
    }

    /// B's raised disc: white, a soft shade inside its lower edge, and two
    /// warm drops (`0 14 28 / .20`, `0 2 4 / .10`).
    private func hubDisc(_ g: QuickFileDialGeometry) -> some View {
        let k = g.scale
        return Circle()
            .fill(Color.white)
            .overlay {
                // inset 0 -3px 6px rgba(120,84,50,.08)
                Circle()
                    .stroke(QuickFileDepth.warm.opacity(0.10), lineWidth: 8 * k)
                    .padding(-4 * k)
                    .offset(y: -3 * k)
                    .blur(radius: 3 * k)
                    .mask(Circle())
            }
            .shadow(color: QuickFileDepth.warm.opacity(0.10), radius: 2 * k, y: 2 * k)
            .shadow(color: QuickFileDepth.warm.opacity(0.20), radius: 14 * k, y: 14 * k)
    }

    private enum RingLook { case solid, dashed, faint }

    private func ringLook(_ shown: FilingCandidate?, onMore: Bool) -> RingLook {
        guard let shown, !onMore else { return .faint }
        if model.showsCheck || shown.reasons.first == .yours { return .solid }
        return model.showsBestGuess && model.ranking.evidence == .strong ? .solid : .dashed
    }

    /// How sure the guess is, as a 2 pt line round the hub in the topic's
    /// mid: solid when it's yours or strong, dashed for a thin guess, faint
    /// when the hub shows nothing to be sure of.
    private func evidenceRing(_ g: QuickFileDialGeometry, shown: FilingCandidate?, onMore: Bool) -> some View {
        let diameter = g.ringRadius * 2
        let colour = shown.map { QuickFileStyle.palette(for: $0.categoryID).mid } ?? QuickFileStyle.inkFaint
        return ZStack {
            switch ringLook(shown, onMore: onMore) {
            case .solid:
                Circle().stroke(colour, lineWidth: g.ringWidth)
            case .dashed:
                Circle().stroke(colour, style: StrokeStyle(lineWidth: g.ringWidth, dash: [5 * g.scale, 4 * g.scale]))
            case .faint:
                Circle().stroke(QuickFileStyle.inkFaint.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            Circle()
                .trim(from: 0, to: ringClosed)
                .stroke(colour, style: StrokeStyle(lineWidth: g.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.16), value: model.showsBestGuess)
    }

    @ViewBuilder
    private func hubContent(_ g: QuickFileDialGeometry, shown: FilingCandidate?, onMore: Bool) -> some View {
        let k = g.scale
        let width = g.hub * 1.6
        if onMore {
            VStack(spacing: 5 * k) {
                ZStack {
                    Circle().fill(Brand.offWhite)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22 * k, weight: .medium))
                        .foregroundStyle(Brand.sandInk)
                }
                .frame(width: 56 * k, height: 56 * k)
                Text(QuickFileCopy.moreTopics)
                    .font(style.display(16 * k))
                    .foregroundStyle(QuickFileStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: width)
        } else if let shown {
            let layout = hubLayout(shown)
            let art = hubArt(layout, g)
            let palette = QuickFileStyle.palette(for: shown.categoryID)
            // Placed, not stacked, so the badge can find the art (`checkBadge`).
            ZStack {
                QuickFileArtDisc(topicID: shown.categoryID, size: art.size, style: style)
                    .offset(y: art.y)
                switch layout {
                case .art:
                    EmptyView()
                case .named:
                    Text(QuickFileCopy.topicName(shown.categoryID))
                        .font(style.display(17 * k))
                        .foregroundStyle(palette.deep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 100 * k)
                        .offset(y: art.y + art.size / 2 + 14 * k)
                case .hint:
                    Text(QuickFileCopy.tapToFile)
                        .font(style.ui(11 * k, .bold))
                        .foregroundStyle(style.accentDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 96 * k)
                        .offset(y: art.y + art.size / 2 + 11 * k)
                }
            }
            .frame(width: width, height: g.hub * 2)
        } else {
            VStack(spacing: 6 * k) {
                ZStack {
                    Circle().fill(QuickFileStyle.paper)
                    Circle().strokeBorder(QuickFileStyle.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    Text("?")
                        .font(style.display(26 * k))
                        .foregroundStyle(QuickFileStyle.inkSecondary)
                }
                .frame(width: 56 * k, height: 56 * k)
                Text(QuickFileCopy.turnToChoose)
                    .font(style.ui(12.5 * k, .semibold))
                    .foregroundStyle(QuickFileStyle.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: width)
        }
    }

    /// The chosen topic's check, in its deep colour with a 3 pt white ring,
    /// at the art's lower right (B: right −4, bottom −2 on the 84 pt art).
    private func checkBadge(_ g: QuickFileDialGeometry, palette: CategoryPalette,
                            art: (size: CGFloat, y: CGFloat)) -> some View {
        let size = g.badge * max(0.8, art.size / g.hubArt)
        return ZStack {
            Circle().fill(Color.white).padding(-3 * g.scale)
            Circle().fill(palette.deep)
            QuickFileCheck()
                .trim(from: 0, to: checkDrawn)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5 * g.scale, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: palette.deep.opacity(0.25), radius: 4 * g.scale, y: 4 * g.scale)
        .offset(x: art.size / 2 * 0.738, y: art.y + art.size / 2 * 0.69)
    }

    // MARK: Gesture

    private func drag(_ g: QuickFileDialGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let tracker = self.tracker
                if !tracker.active {
                    tracker.begin(at: value.startLocation, geometry: g)
                    model.touch()
                    if tracker.region != .outside, !model.isFolded { held = tracker.region }
                }
                if !tracker.turning,
                   hypot(value.translation.width, value.translation.height) >= QuickFileDragTracker.tapTravel {
                    tracker.turning = true
                    if held != nil { held = nil }
                }
                let crossed = tracker.follow(value.location, geometry: g)
                if crossed != 0 { model.turn(crossed) }
            }
            .onEnded { _ in
                let tracker = self.tracker
                let region = tracker.region
                let tapped = tracker.active && !tracker.turning
                tracker.reset()
                if held != nil { held = nil }
                guard tapped else { return }
                switch region {
                case .hub: model.confirm()
                case .seat(let seat): model.tap(seat)
                case .outside: break
                }
            }
    }

    // MARK: Motion

    private func appearAnimation(delay: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.78).delay(delay)
    }

    private func appear() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            if model.showsCheck { ringClosed = 1; checkDrawn = 1 }
        }
        appeared = true
    }

    /// The check comes and goes with what the hub shows: in `.refine`,
    /// turning off the chosen topic takes it away and turning back brings it.
    private func checkShown(_ shows: Bool) {
        guard !shows || ringClosed == 0 else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            ringClosed = shows ? 1 : 0
            checkDrawn = shows ? 1 : 0
        }
    }

    /// A filing, or a choice of a new topic: the hub presses in and the
    /// check draws.
    private func landCheck() {
        guard model.filed != nil else { return }
        if model.mode == .refine, let filed = model.filed {
            UIAccessibility.post(notification: .announcement, argument: QuickFileCopy.chosen(filed))
        }
        if reduceMotion {
            ringClosed = 1
            checkDrawn = 1
            return
        }
        ringClosed = 0
        checkDrawn = 0
        withAnimation(.easeOut(duration: 0.22)) { ringClosed = 1 }
        withAnimation(.easeOut(duration: 0.22).delay(0.06)) { checkDrawn = 1 }
        withAnimation(.easeOut(duration: 0.1)) {
            bump = 1.05
        } completion: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { bump = 1 }
        }
    }
}

// MARK: - Header and footer

/// The line above the dial: "Sorted for you", "Our best guess — turn to
/// change", "Where does this go?" or "Filed by you".
struct QuickFileHeader: View {
    let model: QuickFileModel
    var style: QuickFileStyle

    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 13.5

    init(model: QuickFileModel, style: QuickFileStyle = .system) {
        self.model = model
        self.style = style
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: QuickFileCopy.headerSymbol(model.ranking, yours: model.yours))
                .font(.system(size: size * 0.9, weight: .semibold))
            Text(model.header)
                .font(style.ui(size, .semibold))
        }
        .foregroundStyle(style.accentDeep)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .animation(.easeOut(duration: 0.2), value: model.header)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Under the dial: why the lit topic is there, its subtopics as one-tap
/// chips, and the "Also likely" chip when a late answer couldn't join a
/// frozen ring. Keeps a steady height so nothing below it jumps.
struct QuickFileDialFooter: View {
    let model: QuickFileModel
    var style: QuickFileStyle

    @ScaledMetric(relativeTo: .footnote) private var lineFont: CGFloat = 13.5
    @ScaledMetric(relativeTo: .subheadline) private var chipFont: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 36

    init(model: QuickFileModel, style: QuickFileStyle = .system) {
        self.model = model
        self.style = style
    }

    /// The chips for a candidate: its other subtopics with evidence (up to
    /// three), topped up from the topic's own list (most-saved first) until
    /// there are three chips counting "Just Fitness".
    static func chipSubs(for candidate: FilingCandidate) -> [String] {
        var subs = Array(candidate.altSubs.filter { $0 != candidate.subcategory }.prefix(3))
        let room = candidate.subcategory == nil ? 3 : 2
        if subs.count < room, let topic = Taxonomy.category(id: candidate.categoryID) {
            for sub in topic.subs where sub != candidate.subcategory && !subs.contains(sub) {
                subs.append(sub)
                if subs.count == room { break }
            }
        }
        return subs
    }

    var body: some View {
        VStack(spacing: 10) {
            reasonLine
            chipsRow
                .frame(height: max(44, chipHeight + 8))
            if let suggestion = model.aiChip, model.filed == nil {
                alsoLikely(suggestion)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.aiChip)
        // The ring above it is fixed; past this the chips would crowd it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var reasonContent: (symbol: String?, text: String) {
        if model.filed != nil { return (nil, "") }
        if model.isOnMore { return ("magnifyingglass", QuickFileCopy.moreReason) }
        guard let centre = model.centre else { return (nil, QuickFileCopy.chooseHint) }
        guard let line = model.reason(for: centre) else { return (nil, "") }
        return (QuickFileCopy.reasonSymbol(centre, input: model.input), line)
    }

    private var reasonLine: some View {
        let content = reasonContent
        return HStack(spacing: 6) {
            if let symbol = content.symbol {
                Image(systemName: symbol)
                    .font(.system(size: lineFont * 0.9, weight: .semibold))
            }
            Text(content.text)
                .font(style.ui(lineFont, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(QuickFileStyle.inkSecondary)
        .frame(minHeight: 20)
        .id(content.text)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: content.text)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chipsRow: some View {
        if model.filed == nil, let centre = model.centre {
            let subs = Self.chipSubs(for: centre)
            // Too wide for the row: drop the last subtopics rather than clip
            // a chip at the edge. "Just Fitness" always stays.
            ViewThatFits(in: .horizontal) {
                chips(subs, centre: centre)
                chips(Array(subs.dropLast()), centre: centre)
                chips(Array(subs.prefix(1)), centre: centre)
                ScrollView(.horizontal, showsIndicators: false) {
                    chips(subs, centre: centre).padding(.horizontal, 2)
                }
            }
            .id("\(centre.categoryID)|\(centre.subcategory ?? "")|\(model.revision)")
            .transition(.opacity)
            .animation(.easeOut(duration: 0.12), value: centre)
        } else {
            Color.clear
        }
    }

    private func chips(_ subs: [String], centre: FilingCandidate) -> some View {
        HStack(spacing: 8) {
            ForEach(subs, id: \.self) { sub in
                chip(sub, topicID: centre.categoryID, muted: false) {
                    model.file(model.candidate(topicID: centre.categoryID, subcategory: sub))
                }
            }
            if centre.subcategory != nil {
                chip(QuickFileCopy.just(centre.categoryID), topicID: centre.categoryID, muted: true) {
                    model.file(model.candidate(topicID: centre.categoryID, subcategory: nil))
                }
            }
        }
    }

    private func chip(_ title: String, topicID: String, muted: Bool, action: @escaping () -> Void) -> some View {
        let palette = QuickFileStyle.palette(for: topicID)
        return Button(action: action) {
            Text(title)
                .font(style.ui(chipFont, .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(muted ? Brand.sandInk : palette.deep)
                .padding(.horizontal, 14)
                .frame(height: chipHeight)
                .background(muted ? Brand.sand : palette.tint, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityLabel(muted ? QuickFileCopy.fileUnder(topicID, nil) : QuickFileCopy.fileUnder(topicID, title))
    }

    private func alsoLikely(_ candidate: FilingCandidate) -> some View {
        let palette = QuickFileStyle.palette(for: candidate.categoryID)
        return Button { model.file(candidate) } label: {
            HStack(spacing: 6) {
                Text("✨")
                Text(QuickFileCopy.alsoLikely(candidate))
                    .font(style.ui(chipFont, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(palette.deep)
            .padding(.horizontal, 14)
            .frame(height: chipHeight)
            .background(palette.tint, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.mid.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityLabel(QuickFileCopy.fileUnder(candidate.categoryID, candidate.subcategory))
    }
}

// MARK: - Ranked list (accessibility text sizes)

/// The dial as a list, for text too large for a ring: the same candidates in
/// rank order, each one tap to file, then More…. Each row is a clay slab in
/// its topic's tint; the lit one fills with the deep colour, as on the ring.
private struct QuickFileRankedList: View {
    let model: QuickFileModel
    let style: QuickFileStyle

    @ScaledMetric(relativeTo: .headline) private var art: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var reasonSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { seat, candidate in
                Button { model.tap(seat) } label: { row(candidate, seat: seat) }
                    .buttonStyle(QuickFilePressStyle())
                    .disabled(model.isFolded)
                    .accessibilityAddTraits(model.highlighted == seat || model.filed?.categoryID == candidate.categoryID
                                            ? .isSelected : [])
            }
            Button { model.more() } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.white)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: art * 0.45, weight: .medium))
                            .foregroundStyle(Brand.sandInk)
                    }
                    .frame(width: art, height: art)
                    Text(QuickFileCopy.moreTopics)
                        .font(style.ui(titleSize, .bold))
                        .foregroundStyle(Brand.sandInk)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Brand.offWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
            }
            .buttonStyle(QuickFilePressStyle())
            .disabled(model.isFolded)
        }
    }

    private func row(_ candidate: FilingCandidate, seat: Int) -> some View {
        let palette = QuickFileStyle.palette(for: candidate.categoryID)
        let filedHere = model.filed?.categoryID == candidate.categoryID
        let lit = model.highlighted == seat
        let text = lit ? Color.white : palette.deep
        return HStack(spacing: 12) {
            QuickFileArtDisc(topicID: candidate.categoryID, size: art, style: style)
                .background(Circle().fill(Color.white).padding(-2))
            VStack(alignment: .leading, spacing: 2) {
                Text(QuickFileCopy.label(candidate))
                    .font(style.ui(titleSize, .bold))
                    .foregroundStyle(text)
                if let reason = model.reason(for: candidate) {
                    Text(reason)
                        .font(style.ui(reasonSize, .medium))
                        .foregroundStyle(text)
                }
            }
            Spacer(minLength: 0)
            if filedHere {
                ZStack {
                    Circle().fill(lit ? Color.white : palette.deep)
                    Image(systemName: "checkmark")
                        .font(.system(size: art * 0.36, weight: .bold))
                        .foregroundStyle(lit ? palette.deep : Color.white)
                }
                .frame(width: art * 0.8, height: art * 0.8)
            }
        }
        .padding(12)
        .background(lit ? palette.deep : palette.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(seat == model.ranking.preselect ? "Suggested" : "")
    }
}
