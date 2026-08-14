import SwiftUI

/// A real thumbnail when we have one, the category-hue gradient when we don't.
///
/// The gradient isn't a placeholder to be embarrassed about — Instagram and
/// TikTok don't publish metadata to unauthenticated requests, so for those it's
/// permanent. It stays deliberately handsome for that reason, and the image
/// cross-fades in when it does arrive rather than popping.
struct CoverImage: View {
    let url: URL?
    let palette: CategoryPalette

    var body: some View {
        ZStack {
            gradient
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.22))) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private var gradient: some View {
        LinearGradient(colors: [palette.coverTop, palette.coverBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(colors: [.white.opacity(0.16), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 180)
            )
    }
}

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
            } else if bookmark.isMedia {
                mediaCard
            } else {
                articleCard
            }
        }
        .cardSurface(strong: bookmark.isMedia)
    }

    // MARK: Text post — X / Threads

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PlatformBadge(platform: bookmark.platform, size: 20)
                Text(bookmark.author ?? bookmark.platform.name)
                    .font(Typo.ui(11.5, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
                    .lineLimit(1)
            }

            Text(bookmark.text ?? bookmark.displayTitle)
                .font(Typo.ui(13.5, .regular))
                .foregroundStyle(Tokens.bodyOnWhite)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            footer(label: bookmark.category?.name)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Media cover — TikTok / IG / Shorts / YouTube / Pinterest

    /// Title sits *under* the cover, not painted on it. Overlay titles with
    /// `fixedSize` escaped a fixed-height ZStack and drew on the next card —
    /// that's the squash the Library was showing.
    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                CoverImage(url: bookmark.imageURL, palette: palette)
                    .frame(height: bookmark.coverHeight)
                    .frame(maxWidth: .infinity)
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
            }
            .frame(height: bookmark.coverHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(bookmark.displayTitle)
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                footer(label: bookmark.subcategory ?? bookmark.category?.name)
            }
            .padding(11)
        }
    }

    // MARK: Article — web

    private var articleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Articles get a cover too when the page publishes an og:image —
            // a wall of text-only cards is exactly the flat look we're avoiding.
            if bookmark.imageURL != nil {
                CoverImage(url: bookmark.imageURL, palette: palette)
                    .frame(height: 112)
                    .clipped()
            }
            articleBody
        }
    }

    private var articleBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(palette.dot).frame(width: 7, height: 7)
                Text((bookmark.author ?? "web").uppercased())
                    .font(Typo.ui(10, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Tokens.mutedHeading)
                    .lineLimit(1)
            }

            Text(bookmark.displayTitle)
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
        let title = bookmark.displayTitle

        if bookmark.isTextPost {
            let body = bookmark.text ?? title
            let charsPerLine = max(1, Int(columnWidth / 7.2))
            let lines = min(8, max(1, Int(ceil(Double(body.count) / Double(charsPerLine)))))
            return 26 + CGFloat(lines) * 18 + footerHeight + 26
        }

        if bookmark.isMedia {
            let charsPerLine = max(1, Int(columnWidth / 7.2))
            let lines = min(3, max(1, Int(ceil(Double(title.count) / Double(charsPerLine)))))
            return bookmark.coverHeight + 11 + CGFloat(lines) * 18 + footerHeight + 11
        }

        let charsPerLine = max(1, Int(columnWidth / 7.4))
        let lines = min(3, max(1, Int(ceil(Double(title.count) / Double(charsPerLine)))))
        let cover: CGFloat = bookmark.imageURL != nil ? 112 : 0
        return cover + 22 + CGFloat(lines) * 19 + footerHeight + 24
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
                if bookmark.isTextPost && bookmark.imageURL == nil {
                    LinearGradient(colors: [Color(hex: "2A2C33"), Color(hex: "111318")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "quote.opening")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    CoverImage(url: bookmark.imageURL, palette: palette)
                    if bookmark.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.4), radius: 3)
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

                Text(bookmark.displayTitle)
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
