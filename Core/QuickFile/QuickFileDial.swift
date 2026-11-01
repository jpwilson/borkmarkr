import SwiftUI
import UIKit

// MARK: - The dial

/// Quick File's click wheel: the best guess in the centre, six more round the
/// ring, More… at 10:30, and one more tap to file.
///
/// It is built to feel like a hardware control. Turning is relative, like a
/// click wheel: drag round the ring anywhere and every 45° is one detent, with
/// 8° of slack so a resting thumb never chatters between two. Each detent
/// ticks (`.selection`, never closer than 45 ms), a coral bead springs round
/// the rim to the lit key, and the centre slides 6 pt the way you turned. A
/// tap files: the centre files what it shows, a key files that key. Filing
/// presses the hub in, folds the ring away, closes the evidence ring and
/// draws a coral check, with one firm `.impact`.
///
/// The ring never rotates and its keys never reorder under a thumb. With
/// Reduce Motion everything is a short crossfade; at accessibility text sizes
/// the dial becomes a ranked list; under VoiceOver it is one adjustable
/// element (swipe up or down to turn, double-tap to file).
struct QuickFileDial: View {
    let model: QuickFileModel
    var style: QuickFileStyle
    var diameter: CGFloat
    /// VoiceOver's "Not now" action. Nil leaves it out.
    var onLater: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: QuickFileModel, style: QuickFileStyle = .system, diameter: CGFloat = 300,
         onLater: (() -> Void)? = nil) {
        self.model = model
        self.style = style
        self.diameter = diameter
        self.onLater = onLater
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            QuickFileRankedList(model: model, style: style)
        } else {
            QuickFileRing(model: model, style: style, diameter: diameter, onLater: onLater)
                // Fixed geometry: the keys can't grow with the text.
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }
}

// MARK: - Geometry

/// Where everything on a dial of a given diameter sits. Angles are measured
/// clockwise from 12 o'clock.
struct QuickFileDialGeometry {
    let size: CGFloat

    init(diameter: CGFloat) { size = diameter }

    /// 1 at the 300 pt reference size.
    var scale: CGFloat { size / 300 }
    var centre: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    /// Room at the rim for the lit key to lift into.
    var outer: CGFloat { size / 2 - 4 * scale }
    var inner: CGFloat { size * 0.235 }
    var hub: CGFloat { size * 0.205 }
    var gap: CGFloat { 4 * scale }
    var corner: CGFloat { 9 * scale }
    var ringWidth: CGFloat { 5 * scale }
    /// Between the hub's edge and the evidence ring.
    var ringGap: CGFloat { 1 * scale }
    var art: CGFloat { 56 * scale }
    var labelRadius: CGFloat { (inner + outer) / 2 + 1 * scale }
    var labelWidth: CGFloat { 66 * scale }
    var labelHeight: CGFloat { 58 * scale }
    var beadRadius: CGFloat { outer - 9 * scale }
    /// Closer to the centre than this, a finger's angle is too jumpy to turn by.
    var steadyRadius: CGFloat { size * 0.12 }

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
        if r <= (hub + inner) / 2 { return .hub }
        guard r <= outer + 16 * scale else { return .outside }
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

/// One key of the ring: an annular sector with parallel-sided gaps to its
/// neighbours and softly rounded corners, like a keycap.
struct QuickFileRingKey: Shape {
    var seat: Int
    var inner: CGFloat
    var outer: CGFloat
    var gap: CGFloat
    var corner: CGFloat

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

/// A topic's clay picture in a circle, or its colour disc and initial when
/// there is no picture to be had.
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
                    LinearGradient(colors: [palette.tint, palette.dot.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(QuickFileCopy.initial(topicID))
                        .font(style.display(size * 0.44))
                        .foregroundStyle(palette.deep)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - The ring

private struct QuickFileRing: View {
    let model: QuickFileModel
    let style: QuickFileStyle
    let diameter: CGFloat
    let onLater: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var held: QuickFileDialRegion?
    @State private var tracker = QuickFileDragTracker()
    @State private var beadAngle: Double = 0
    @State private var ringClosed: CGFloat = 0
    @State private var checkDrawn: CGFloat = 0
    @State private var bump: CGFloat = 1
    @State private var showsHint = QuickFileSettings.showsTapHint

    var body: some View {
        let g = QuickFileDialGeometry(diameter: diameter)
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: g.outer * 2 + 4 * g.scale, height: g.outer * 2 + 4 * g.scale)
                .overlay(Circle().strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
                .shadow(color: QuickFileStyle.ink.opacity(0.04), radius: 2, y: 1)
                .shadow(color: QuickFileStyle.ink.opacity(0.10), radius: 18, y: 10)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
                .animation(appearAnimation(delay: 0), value: appeared)
            ForEach(0..<8, id: \.self) { seat in
                key(seat, g)
            }
            // Above the lit key, which lifts to z 1.
            bead(g)
                .zIndex(2)
            hub(g)
                .zIndex(3)
        }
        .frame(width: g.size, height: g.size)
        .contentShape(Rectangle())
        .gesture(drag(g))
        .onAppear { appear() }
        .onChange(of: model.highlighted) { _, seat in moveBead(to: seat) }
        .onChange(of: model.filed) { _, filed in filedChanged(filed) }
        .onChange(of: model.revision) { _, _ in
            if let line = model.updateAnnouncement {
                UIAccessibility.post(notification: .announcement, argument: line)
            }
        }
        .sensoryFeedback(.selection, trigger: model.tick)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.confirmations)
        .sensoryFeedback(.selection, trigger: model.undos)
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
            if model.filed != nil {
                Button(QuickFileCopy.undo) { model.undo() }
            } else {
                Button(QuickFileCopy.moreTopics) { model.more() }
                if let onLater {
                    Button(QuickFileCopy.notNow) { onLater() }
                }
            }
        }
    }

    // MARK: Keys

    @ViewBuilder
    private func key(_ seat: Int, _ g: QuickFileDialGeometry) -> some View {
        let candidate = model.candidate(at: seat)
        let isMore = seat == QuickFileModel.moreSlot
        let folded = model.filed != nil
        let lit = !folded && model.highlighted == seat
        let pressed = held == .seat(seat)
        let palette = candidate.map { QuickFileStyle.palette(for: $0.categoryID) } ?? NeutralPalette.value
        let shape = QuickFileRingKey(seat: seat, inner: g.inner, outer: g.outer, gap: g.gap, corner: g.corner)

        ZStack {
            shape.fill(Color.white)
            if isMore {
                shape.fill(QuickFileStyle.mutedControl)
            } else if candidate != nil {
                shape.fill(RadialGradient(colors: [palette.tint.opacity(0.26), palette.tint.opacity(0.66)],
                                          center: .center, startRadius: g.inner, endRadius: g.outer))
            } else {
                shape.fill(QuickFileStyle.paper)
            }
            shape
                .fill(RadialGradient(colors: isMore ? [QuickFileStyle.ink, Color(white: 0.30)]
                                                    : [palette.coverBottom, palette.coverTop],
                                     center: .center, startRadius: g.inner, endRadius: g.outer))
                .opacity(lit ? 1 : 0)
            label(seat, candidate: candidate, palette: palette, lit: lit, g: g)
                .id("\(seat)-\(model.revision)")
                .transition(.opacity)
            if let candidate, !folded, model.sparkle == candidate.categoryID {
                Text("✨")
                    .font(.system(size: 11 * g.scale))
                    .frame(width: 20 * g.scale, height: 20 * g.scale)
                    .background(Circle().fill(Color.white))
                    .shadow(color: QuickFileStyle.ink.opacity(0.18), radius: 3, y: 1)
                    .position(g.point(degrees: Double(seat) * 45 + 13, radius: g.outer - 13 * g.scale))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: g.size, height: g.size)
        .shadow(color: (isMore ? QuickFileStyle.ink : palette.deep).opacity(lit ? 0.28 : 0),
                radius: lit ? 9 : 0, y: lit ? 4 : 0)
        .scaleEffect(lit && !reduceMotion ? 1.035 : (pressed && !reduceMotion ? 0.97 : 1))
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.74), value: lit)
        .animation(.easeOut(duration: 0.1), value: pressed)
        .animation(.easeInOut(duration: 0.16), value: model.revision)
        .animation(.easeOut(duration: 0.2), value: model.sparkle)
        .zIndex(lit ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (folded ? 0.82 : (appeared ? 1 : 0.9)))
        .opacity(folded ? 0 : (appeared ? 1 : 0))
        .animation(folded ? .easeIn(duration: reduceMotion ? 0.12 : 0.16) : appearAnimation(delay: 0), value: folded)
        .animation(appearAnimation(delay: Double(seat) * 0.018), value: appeared)
        .allowsHitTesting(false)
    }

    private func label(_ seat: Int, candidate: FilingCandidate?, palette: CategoryPalette, lit: Bool,
                       g: QuickFileDialGeometry) -> some View {
        let k = g.scale
        return VStack(spacing: 2 * k) {
            if seat == QuickFileModel.moreSlot {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15 * k, weight: .bold))
                Text("More…")
                    .font(style.ui(12.5 * k, .semibold))
            } else if let candidate {
                let name = QuickFileCopy.topicName(candidate.categoryID)
                if let sub = candidate.subcategory {
                    Text(name.uppercased())
                        .font(style.ui(9.5 * k, .heavy))
                        .tracking(0.4 * k)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(0.8)
                    Text(sub)
                        .font(style.ui(12.5 * k, .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(name)
                        .font(style.ui(12.5 * k, .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .foregroundStyle(lit ? Color.white : (seat == QuickFileModel.moreSlot ? QuickFileStyle.inkSecondary : palette.deep))
        .multilineTextAlignment(.center)
        .frame(width: g.labelWidth, height: g.labelHeight)
        .position(g.point(degrees: Double(seat) * 45, radius: g.labelRadius))
    }

    // MARK: Bead

    private func bead(_ g: QuickFileDialGeometry) -> some View {
        let size = 10 * g.scale
        let visible = model.highlighted != nil && model.filed == nil
        return Circle()
            .fill(style.accent)
            .overlay(Circle().stroke(Color.white, lineWidth: 2 * g.scale))
            .frame(width: size, height: size)
            .shadow(color: style.accent.opacity(0.45), radius: 3, y: 1)
            .scaleEffect(visible ? 1 : 0.3)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.14), value: visible)
            .offset(y: -g.beadRadius)
            .rotationEffect(.degrees(beadAngle))
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: beadAngle)
            .allowsHitTesting(false)
    }

    private func moveBead(to seat: Int?) {
        guard let seat else { return }
        var delta = (Double(seat) * 45 - beadAngle).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        beadAngle += delta
    }

    // MARK: Hub

    private var hubKey: String {
        let shown = model.filed ?? model.centre
        let seat = model.filed == nil ? (model.highlighted.map(String.init) ?? "none") : "filed"
        return "\(seat)|\(shown?.categoryID ?? "")|\(shown?.subcategory ?? "")|\(model.revision)"
    }

    private var hubTransition: AnyTransition {
        guard !reduceMotion, model.slides else { return .opacity }
        let shift = 6 * CGFloat(model.direction)
        return .asymmetric(insertion: .offset(x: -shift).combined(with: .opacity),
                           removal: .offset(x: shift).combined(with: .opacity))
    }

    private func hub(_ g: QuickFileDialGeometry) -> some View {
        let shown = model.filed ?? model.centre
        let onMore = model.filed == nil && model.isOnMore
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.white, QuickFileStyle.paper], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
                .shadow(color: QuickFileStyle.ink.opacity(0.06), radius: 1.5, y: 1)
                .shadow(color: QuickFileStyle.ink.opacity(0.13), radius: 12, y: 6)
            evidenceRing(g, shown: shown, onMore: onMore)
            hubContent(g, shown: shown, onMore: onMore)
                .id(hubKey)
                .transition(hubTransition)
            if model.filed != nil {
                checkBadge(g)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: g.hub * 2, height: g.hub * 2)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.14), value: hubKey)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.62),
                   value: model.filed != nil)
        .scaleEffect(held == .hub && !reduceMotion ? 0.95 : bump)
        .animation(.easeOut(duration: 0.1), value: held == .hub)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(appearAnimation(delay: 0.04), value: appeared)
        .allowsHitTesting(false)
    }

    private enum RingLook { case solid, dashed, faint }

    private func ringLook(_ shown: FilingCandidate?, onMore: Bool) -> RingLook {
        guard let shown, !onMore else { return .faint }
        if model.filed != nil || shown.reasons.first == .yours { return .solid }
        return model.showsBestGuess && model.ranking.evidence == .strong ? .solid : .dashed
    }

    private func evidenceRing(_ g: QuickFileDialGeometry, shown: FilingCandidate?, onMore: Bool) -> some View {
        let diameter = (g.hub + g.ringGap + g.ringWidth / 2) * 2
        let colour = shown.map { QuickFileStyle.palette(for: $0.categoryID).dot } ?? QuickFileStyle.inkFaint
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
        if onMore {
            VStack(spacing: 4 * k) {
                ZStack {
                    Circle().fill(QuickFileStyle.mutedControl)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22 * k, weight: .bold))
                        .foregroundStyle(QuickFileStyle.inkSecondary)
                }
                .frame(width: g.art * 0.9, height: g.art * 0.9)
                Text(QuickFileCopy.moreTopics)
                    .font(style.display(17 * k))
                    .foregroundStyle(QuickFileStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(QuickFileCopy.moreSubtitle)
                    .font(style.ui(12 * k, .semibold))
                    .foregroundStyle(QuickFileStyle.inkSecondary)
            }
            .frame(width: g.hub * 1.62)
        } else if let shown {
            ViewThatFits(in: .horizontal) {
                hubStack(shown, g: g, art: g.art, twoLines: false)
                hubStack(shown, g: g, art: g.art * 0.72, twoLines: true)
            }
            .frame(width: g.hub * 1.62)
        } else {
            VStack(spacing: 6 * k) {
                ZStack {
                    Circle().fill(QuickFileStyle.paper)
                    Circle().strokeBorder(QuickFileStyle.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    Text("?")
                        .font(style.display(26 * k))
                        .foregroundStyle(QuickFileStyle.inkSecondary)
                }
                .frame(width: g.art * 0.86, height: g.art * 0.86)
                Text(QuickFileCopy.turnToChoose)
                    .font(style.ui(13 * k, .semibold))
                    .foregroundStyle(QuickFileStyle.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: g.hub * 1.62)
        }
    }

    /// The centre's picture, name and subtopic, sized to stay inside the hub's
    /// circle: one-line names get the full 56 pt picture, two-line names a
    /// smaller one, and the first-use "Tap to file" line shrinks it a little.
    private func hubStack(_ shown: FilingCandidate, g: QuickFileDialGeometry, art: CGFloat, twoLines: Bool) -> some View {
        let k = g.scale
        let width = g.hub * 1.62
        let palette = QuickFileStyle.palette(for: shown.categoryID)
        let name = QuickFileCopy.topicName(shown.categoryID)
        let hint = showsHint && !twoLines && model.filed == nil
        return VStack(spacing: (hint || twoLines ? 2 : 3) * k) {
            QuickFileArtDisc(topicID: shown.categoryID, size: hint ? art * 0.86 : art, style: style)
            Group {
                if twoLines {
                    Text(name)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(width: width)
                } else {
                    Text(name)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(style.display((twoLines ? 17 : 19) * k))
            .foregroundStyle(palette.deep)
            .multilineTextAlignment(.center)
            if let sub = shown.subcategory {
                Text(sub)
                    .font(style.ui(13 * k, .semibold))
                    .foregroundStyle(QuickFileStyle.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: width * (twoLines ? 0.72 : 0.9))
            }
            if hint {
                Text(QuickFileCopy.tapToFile)
                    .font(style.ui(10.5 * k, .bold))
                    .foregroundStyle(style.accentDeep)
                    .lineLimit(1)
                    .frame(maxWidth: width * 0.7)
            }
        }
    }

    private func checkBadge(_ g: QuickFileDialGeometry) -> some View {
        let size = 26 * g.scale
        let radius = g.hub + g.ringGap + g.ringWidth / 2
        return ZStack {
            Circle()
                .fill(style.accent)
                .shadow(color: style.accent.opacity(0.45), radius: 4, y: 2)
            Circle().strokeBorder(Color.white, lineWidth: 2 * g.scale)
            QuickFileCheck()
                .trim(from: 0, to: checkDrawn)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.6 * g.scale, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
        .offset(x: radius * 0.7071, y: -radius * 0.7071)
    }

    // MARK: Gesture

    private func drag(_ g: QuickFileDialGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let tracker = self.tracker
                if !tracker.active {
                    tracker.begin(at: value.startLocation, geometry: g)
                    model.touch()
                    if tracker.region != .outside, model.filed == nil { held = tracker.region }
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
            beadAngle = Double(model.highlighted ?? 0) * 45
            if model.filed != nil { ringClosed = 1; checkDrawn = 1 }
        }
        appeared = true
    }

    private func filedChanged(_ filed: FilingCandidate?) {
        guard filed != nil else {
            withAnimation(.easeOut(duration: 0.18)) {
                ringClosed = 0
                checkDrawn = 0
            }
            return
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

    init(model: QuickFileModel, style: QuickFileStyle = .system) {
        self.model = model
        self.style = style
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: QuickFileCopy.headerSymbol(model.ranking, yours: model.yours))
                .font(.system(size: 12, weight: .bold))
            Text(model.header)
                .font(style.ui(13.5, .bold))
        }
        .foregroundStyle(style.accentDeep)
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
                .frame(height: 36)
            if let suggestion = model.aiChip, model.filed == nil {
                alsoLikely(suggestion)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.aiChip)
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
                    .font(.system(size: 12, weight: .bold))
            }
            Text(content.text)
                .font(style.ui(13.5, .medium))
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
            let chips = HStack(spacing: 8) {
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
            ViewThatFits(in: .horizontal) {
                chips
                ScrollView(.horizontal, showsIndicators: false) {
                    chips.padding(.horizontal, 2)
                }
            }
            .id("\(centre.categoryID)|\(centre.subcategory ?? "")|\(model.revision)")
            .transition(.opacity)
            .animation(.easeOut(duration: 0.12), value: centre)
        } else {
            Color.clear
        }
    }

    private func chip(_ title: String, topicID: String, muted: Bool, action: @escaping () -> Void) -> some View {
        let palette = QuickFileStyle.palette(for: topicID)
        return Button(action: action) {
            Text(title)
                .font(style.ui(13, .semibold))
                .lineLimit(1)
                .foregroundStyle(muted ? QuickFileStyle.inkSecondary : palette.deep)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(muted ? QuickFileStyle.mutedControl : palette.tint.opacity(0.55), in: Capsule())
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
                    .font(style.ui(13, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(palette.deep)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(palette.tint.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(palette.dot.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityLabel(QuickFileCopy.fileUnder(candidate.categoryID, candidate.subcategory))
    }
}

// MARK: - Ranked list (accessibility text sizes)

/// The dial as a list, for text too large for a ring: the same candidates in
/// rank order, each one tap to file, then More….
private struct QuickFileRankedList: View {
    let model: QuickFileModel
    let style: QuickFileStyle

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { seat, candidate in
                Button { model.tap(seat) } label: { row(candidate, seat: seat) }
                    .buttonStyle(QuickFilePressStyle())
                    .disabled(model.filed != nil)
                    .accessibilityAddTraits(model.highlighted == seat ? .isSelected : [])
            }
            Button { model.more() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(QuickFileStyle.inkSecondary)
                    Text(QuickFileCopy.moreTopics)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(QuickFileStyle.ink)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(QuickFileStyle.mutedControl, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(QuickFilePressStyle())
            .disabled(model.filed != nil)
        }
    }

    private func row(_ candidate: FilingCandidate, seat: Int) -> some View {
        let palette = QuickFileStyle.palette(for: candidate.categoryID)
        let filedHere = model.filed?.categoryID == candidate.categoryID
        return HStack(spacing: 12) {
            QuickFileArtDisc(topicID: candidate.categoryID, size: 44, style: style)
            VStack(alignment: .leading, spacing: 2) {
                Text(QuickFileCopy.label(candidate))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(QuickFileStyle.ink)
                if let reason = model.reason(for: candidate) {
                    Text(reason)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(QuickFileStyle.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            if filedHere {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(style.accent)
            }
        }
        .padding(12)
        .background(model.highlighted == seat ? palette.tint.opacity(0.5) : Color.white,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint(seat == model.ranking.preselect ? "Suggested" : "")
    }
}
