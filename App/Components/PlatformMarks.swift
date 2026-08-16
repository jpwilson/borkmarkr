import SwiftUI

/// Brand marks at the sizes we actually ship. Instagram’s camera is the
/// quality bar — everything else has to read that clearly.
enum PlatformMarks {
    enum Size {
        case small, large
        static func optical(for point: CGFloat) -> Size { point >= 34 ? .large : .small }
    }

    struct Mark: View {
        let platform: Platform
        let canvas: CGFloat
        var optical: Size = .small

        var body: some View {
            switch platform {
            case .x: XMark(size: canvas)
            case .instagram: InstagramMark(size: canvas, detailed: optical == .large)
            case .tiktok: TikTokMark(size: canvas)
            case .youtube: YouTubeMark(size: canvas)
            case .shorts: ShortsMark(size: canvas)
            case .threads: ThreadsMark(size: canvas)
            case .pinterest: PinterestMark(size: canvas)
            case .grok: GrokMark(size: canvas)
            case .web: EmptyView()
            }
        }
    }
}

/// Official X geometry (24×24 cut-out mark), scaled. A two-bar multiply is not an X.
private struct XMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let pad = s * 0.20
            let scale = (s - pad * 2) / 24
            let transform = CGAffineTransform(translationX: pad, y: pad).scaledBy(x: scale, y: scale)

            var mark = Path()
            mark.move(to: CGPoint(x: 18.244, y: 2.25))
            mark.addLine(to: CGPoint(x: 21.552, y: 2.25))
            mark.addLine(to: CGPoint(x: 14.325, y: 10.51))
            mark.addLine(to: CGPoint(x: 22.827, y: 21.75))
            mark.addLine(to: CGPoint(x: 16.17, y: 21.75))
            mark.addLine(to: CGPoint(x: 11.456, y: 15.519))
            mark.addLine(to: CGPoint(x: 6.055, y: 21.75))
            mark.addLine(to: CGPoint(x: 2.744, y: 21.75))
            mark.addLine(to: CGPoint(x: 10.471, y: 12.917))
            mark.addLine(to: CGPoint(x: 1.254, y: 2.25))
            mark.addLine(to: CGPoint(x: 8.08, y: 2.25))
            mark.addLine(to: CGPoint(x: 12.333, y: 7.872))
            mark.closeSubpath()

            mark.move(to: CGPoint(x: 17.083, y: 19.77))
            mark.addLine(to: CGPoint(x: 18.916, y: 19.77))
            mark.addLine(to: CGPoint(x: 7.084, y: 4.126))
            mark.addLine(to: CGPoint(x: 5.117, y: 4.126))
            mark.closeSubpath()

            context.fill(mark.applying(transform), with: .color(.white), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
    }
}

private struct InstagramMark: View {
    let size: CGFloat
    let detailed: Bool

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let stroke = detailed ? s * 0.075 : s * 0.10
            let inset = s * 0.20
            let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
            context.stroke(Path(roundedRect: body, cornerRadius: s * 0.22, style: .continuous),
                           with: .color(.white), lineWidth: stroke)

            let lens = s * (detailed ? 0.34 : 0.36)
            let lensRect = CGRect(x: (s - lens) / 2, y: (s - lens) / 2, width: lens, height: lens)
            context.stroke(Path(ellipseIn: lensRect), with: .color(.white), lineWidth: stroke)

            if detailed {
                let flash = s * 0.08
                context.fill(Path(ellipseIn: CGRect(x: s * 0.64, y: s * 0.22, width: flash, height: flash)),
                             with: .color(.white))
            }
        }
        .frame(width: size, height: size)
    }
}

/// White play on red. The badge *is* the red field — never a white landscape bezel.
private struct YouTubeMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            var play = Path()
            play.move(to: CGPoint(x: s * 0.36, y: s * 0.30))
            play.addLine(to: CGPoint(x: s * 0.72, y: s * 0.50))
            play.addLine(to: CGPoint(x: s * 0.36, y: s * 0.70))
            play.closeSubpath()
            context.fill(play, with: .color(.white))
        }
        .frame(width: size, height: size)
    }
}

/// Shorts: white play inside a portrait frame *stroke*. No filled white rectangles.
private struct ShortsMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let frame = CGRect(x: s * 0.30, y: s * 0.16, width: s * 0.40, height: s * 0.68)
            context.stroke(
                Path(roundedRect: frame, cornerRadius: s * 0.12, style: .continuous),
                with: .color(.white),
                lineWidth: s * 0.07
            )
            var play = Path()
            play.move(to: CGPoint(x: s * 0.42, y: s * 0.38))
            play.addLine(to: CGPoint(x: s * 0.62, y: s * 0.50))
            play.addLine(to: CGPoint(x: s * 0.42, y: s * 0.62))
            play.closeSubpath()
            context.fill(play, with: .color(.white))
        }
        .frame(width: size, height: size)
    }
}

/// TikTok note: stem + oval head + flag, with the cyan/magenta ghost.
private struct TikTokMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            note(color: Color(hex: "25F4EE")).offset(x: -size * 0.055, y: size * 0.02)
            note(color: Color(hex: "FE2C55")).offset(x: size * 0.055, y: -size * 0.02)
            note(color: .white)
        }
        .frame(width: size, height: size)
    }

    private func note(color: Color) -> some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            var path = Path()
            let head = CGRect(x: s * 0.22, y: s * 0.52, width: s * 0.34, height: s * 0.26)
            path.addEllipse(in: head)
            path.addRoundedRect(in: CGRect(x: s * 0.50, y: s * 0.18, width: s * 0.09, height: s * 0.50),
                                cornerSize: CGSize(width: s * 0.04, height: s * 0.04))
            var flag = Path()
            flag.move(to: CGPoint(x: s * 0.56, y: s * 0.18))
            flag.addQuadCurve(to: CGPoint(x: s * 0.78, y: s * 0.38),
                              control: CGPoint(x: s * 0.80, y: s * 0.16))
            flag.addQuadCurve(to: CGPoint(x: s * 0.59, y: s * 0.34),
                              control: CGPoint(x: s * 0.74, y: s * 0.30))
            flag.closeSubpath()
            context.fill(path, with: .color(color))
            context.fill(flag, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// Threads @ — a single-stroke loop with an inner ring.
private struct ThreadsMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let stroke = s * 0.09
            let style = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)

            var outer = Path()
            outer.addArc(center: CGPoint(x: s * 0.50, y: s * 0.50),
                         radius: s * 0.24,
                         startAngle: .degrees(50),
                         endAngle: .degrees(400),
                         clockwise: false)
            context.stroke(outer, with: .color(.white), style: style)

            var inner = Path()
            inner.addArc(center: CGPoint(x: s * 0.50, y: s * 0.50),
                         radius: s * 0.11,
                         startAngle: .degrees(200),
                         endAngle: .degrees(480),
                         clockwise: false)
            context.stroke(inner, with: .color(.white), style: StrokeStyle(lineWidth: stroke * 0.9, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Pinterest P with the descending tail — not a system letter.
private struct PinterestMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let stroke = s * 0.11
            var stem = Path()
            stem.move(to: CGPoint(x: s * 0.36, y: s * 0.22))
            stem.addLine(to: CGPoint(x: s * 0.36, y: s * 0.82))
            context.stroke(stem, with: .color(.white),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            var bowl = Path()
            bowl.addArc(center: CGPoint(x: s * 0.50, y: s * 0.40),
                        radius: s * 0.18,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(90),
                        clockwise: false)
            context.stroke(bowl, with: .color(.white),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

/// Grok — a six-point spark, white on ink.
private struct GrokMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
    }
}
