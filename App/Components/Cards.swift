import SwiftUI

/// Platform badge — small rounded square, 7.5–12px/800 label.
struct PlatformBadge: View {
    let platform: Platform
    var size: CGFloat = 22

    var body: some View {
        Text(platform.short)
            .font(Typo.ui(size * 0.42, .heavy))
            .foregroundStyle(platform.badgeInk)
            .frame(width: size, height: size)
            // A single-colour "gradient" of two identical stops keeps this one
            // ShapeStyle type, so it can go straight into `background(_:in:)`.
            .background(
                LinearGradient(
                    colors: platform.badgeColors.count > 1
                        ? platform.badgeColors
                        : [platform.badgeColors[0], platform.badgeColors[0]],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            )
            .accessibilityLabel(platform.name)
    }
}

/// Small pill.
struct Pill: View {
    let text: String
    var fg: Color = Tokens.inkSecondary
    var bg: Color = Tokens.mutedControl
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(Typo.ui(11.5, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(bg, in: Capsule())
    }
}

/// A dot marking that an item carries a note.
struct NoteDot: View {
    var body: some View {
        Circle()
            .fill(Tokens.noteIconBG)
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(Tokens.noteBorder, lineWidth: 1))
            .accessibilityLabel("Has a note")
    }
}

/// The masonry card. Its form follows the content type — the "content-native
/// card system" the handoff calls the visual signature.
struct BookmarkCard: View {
    let bookmark: Bookmark

    private var palette: CategoryPalette {
        bookmark.category?.palette ?? NeutralPalette.value
    }

    var body: some View {
        Group {
            if bookmark.isTextPost {
                textCard
            } else if bookmark.isArticle {
                articleCard
            } else {
                mediaCard
            }
        }
        .cardSurface(strong: bookmark.isMedia)
    }

    // MARK: Text post — X / Threads

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                PlatformBadge(platform: bookmark.platform, size: 20)
                Text(bookmark.author ?? bookmark.platform.name)
                    .font(Typo.ui(11.5, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
                    .lineLimit(1)
            }

            Text(bookmark.text ?? bookmark.title)
                .font(Typo.ui(13, .regular))
                .foregroundStyle(Tokens.bodyOnWhite)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            footer(label: bookmark.category?.name)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Media cover — TikTok / IG / Shorts / YouTube / Pinterest

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [palette.coverTop, palette.coverBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        RadialGradient(colors: [.white.opacity(0.16), .clear],
                                       center: .topLeading, startRadius: 0, endRadius: 180)
                    )
                    .overlay(
                        LinearGradient(colors: [.clear, Color(hex: "0A0602").opacity(0.52)],
                                       startPoint: .center, endPoint: .bottom)
                    )
                    .frame(height: bookmark.coverHeight)
                    .clipped()

                HStack(alignment: .top) {
                    PlatformBadge(platform: bookmark.platform, size: 22)
                    Spacer()
                    if let duration = bookmark.durationLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                            Text(duration).font(Typo.ui(10.5, .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                    }
                }
                .padding(9)

                VStack {
                    Spacer()
                    Text(bookmark.title)
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(11)
                .frame(height: bookmark.coverHeight, alignment: .bottom)
            }
            .frame(height: bookmark.coverHeight)

            footer(label: bookmark.subcategory ?? bookmark.category?.name)
                .padding(11)
        }
    }

    // MARK: Article — web

    private var articleCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(palette.dot).frame(width: 7, height: 7)
                Text((bookmark.author ?? "web").uppercased())
                    .font(Typo.ui(10, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Tokens.mutedHeading)
                    .lineLimit(1)
            }

            Text(bookmark.title)
                .font(Typo.display(14.5, .semibold))
                .foregroundStyle(Tokens.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            footer(label: bookmark.category?.name)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared footer

    private func footer(label: String?) -> some View {
        HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(Typo.ui(10.5, .semibold))
                    .foregroundStyle(palette.deep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette.tint, in: Capsule())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(RelativeDate.label(for: bookmark.savedAt))
                .font(Typo.ui(10.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
            if bookmark.hasNote { NoteDot() }
        }
    }

    /// Estimated height for masonry packing. Approximate by design — it only
    /// has to rank cards against each other, not match the final frame.
    static func estimatedHeight(for bookmark: Bookmark, columnWidth: CGFloat) -> CGFloat {
        let footerHeight: CGFloat = 30

        if bookmark.isTextPost {
            let body = bookmark.text ?? bookmark.title
            let charsPerLine = max(1, Int(columnWidth / 6.6))
            let lines = min(6, max(1, Int(ceil(Double(body.count) / Double(charsPerLine)))))
            return 24 + CGFloat(lines) * 17 + footerHeight + 24
        }

        if bookmark.isArticle {
            let charsPerLine = max(1, Int(columnWidth / 7.4))
            let lines = min(3, max(1, Int(ceil(Double(bookmark.title.count) / Double(charsPerLine)))))
            return 22 + CGFloat(lines) * 19 + footerHeight + 24
        }

        return bookmark.coverHeight + footerHeight + 22
    }
}

/// Uniform row used by list density and by Topic / Source pages.
struct BookmarkRow: View {
    let bookmark: Bookmark
    var showPlatformBadge: Bool = true

    private var palette: CategoryPalette {
        bookmark.category?.palette ?? NeutralPalette.value
    }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                if bookmark.isTextPost {
                    LinearGradient(colors: [Color(hex: "2A2C33"), Color(hex: "111318")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "quote.opening")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    LinearGradient(colors: [palette.coverTop, palette.coverBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if bookmark.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if showPlatformBadge {
                        PlatformBadge(platform: bookmark.platform, size: 16)
                    }
                    Text(bookmark.author ?? bookmark.platform.name)
                        .font(Typo.ui(11, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Tokens.inkFaint)
                    Text(RelativeDate.label(for: bookmark.savedAt))
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }

                Text(bookmark.title)
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    if let category = bookmark.category {
                        Text(bookmark.subcategory.map { "\(category.name) · \($0)" } ?? category.name)
                            .font(Typo.ui(10.5, .semibold))
                            .foregroundStyle(palette.deep)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(palette.tint, in: Capsule())
                            .lineLimit(1)
                    }
                    if bookmark.hasNote { NoteDot() }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 18)
    }
}

/// Relative dates: Today / Yesterday / `Nd` under a week / `MMM D` beyond.
///
/// Uses calendar day differences rather than the prototype's trick of anchoring
/// both dates to noon and rounding the millisecond gap — that approach drifts
/// across DST boundaries and in timezones with non-hour offsets.
enum RelativeDate {
    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days)d"
        default:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
