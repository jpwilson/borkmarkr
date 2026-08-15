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
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
            }
        }
        // The bitmap must not decide layout width. `.fill` on a loose
        // proposal adopts the image's pixel size and the card blows out
        // of its masonry column, painting over the neighbour.
        .frame(maxWidth: .infinity)
        .clipped()
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

/// Brand mark, not a two-letter tile. Letters read as a placeholder; these
/// are the shapes people actually recognise: X, IG camera, Shorts portrait
/// play, TikTok note, a globe (or the site favicon) for the open web.
struct PlatformBadge: View {
    let platform: Platform
    var size: CGFloat = 22
    var pageURL: URL? = nil

    var body: some View {
        let radius = size * (platform == .shorts ? 0.38 : 0.32)
        ZStack {
            fill
            mark
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityLabel(platform.name)
    }

    @ViewBuilder
    private var fill: some View {
        if platform == .web, pageURL != nil {
            Color(hex: "2A3038")
        } else {
            LinearGradient(
                colors: platform.badgeColors.count > 1
                    ? platform.badgeColors
                    : [platform.badgeColors[0], platform.badgeColors[0]],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch platform {
        case .x:
            xMark
        case .instagram:
            instagramMark
        case .tiktok:
            tiktokMark
        case .youtube:
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        case .shorts:
            shortsMark
        case .threads:
            Text("@")
                .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case .pinterest:
            Text("P")
                .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        case .web:
            webMark
        }
    }

    private var xMark: some View {
        ZStack {
            Capsule().fill(.white).frame(width: size * 0.62, height: size * 0.12)
                .rotationEffect(.degrees(40))
            Capsule().fill(.white).frame(width: size * 0.62, height: size * 0.12)
                .rotationEffect(.degrees(-40))
        }
    }

    private var instagramMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.white, lineWidth: size * 0.075)
                .padding(size * 0.18)
            Circle()
                .stroke(.white, lineWidth: size * 0.075)
                .frame(width: size * 0.34, height: size * 0.34)
            Circle()
                .fill(.white)
                .frame(width: size * 0.085, height: size * 0.085)
                .offset(x: size * 0.18, y: -size * 0.18)
        }
    }

    private var tiktokMark: some View {
        ZStack {
            Image(systemName: "music.note")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(Color(hex: "25F4EE"))
                .offset(x: -size * 0.06, y: size * 0.02)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(Color(hex: "FE2C55"))
                .offset(x: size * 0.06, y: -size * 0.02)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var shortsMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(.white, lineWidth: size * 0.08)
                .padding(.horizontal, size * 0.24)
                .padding(.vertical, size * 0.12)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.26, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.015)
        }
    }

    @ViewBuilder
    private var webMark: some View {
        if let host = pageURL?.host, let icon = Self.faviconURL(for: host) {
            AsyncImage(url: icon) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.16)
                } else {
                    webFallback
                }
            }
        } else {
            webFallback
        }
    }

    private var webFallback: some View {
        ZStack {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: size * 0.56, weight: .medium))
                .foregroundStyle(Color(hex: "9BE7C4"))
            if let host = pageURL?.host,
               let initial = host.replacingOccurrences(of: "www.", with: "").first
            {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private static func faviconURL(for host: String) -> URL? {
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return URL(string: "https://www.google.com/s2/favicons?domain=\(cleaned)&sz=128")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(strong: bookmark.isMedia)
    }

    // MARK: Text post — X / Threads

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PlatformBadge(platform: bookmark.platform, size: 20, pageURL: bookmark.url)
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
                    PlatformBadge(platform: bookmark.platform, size: 22, pageURL: bookmark.url)
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
            VStack(alignment: .trailing, spacing: 1) {
                Text(RelativeDate.label(for: bookmark.savedAt))
                    .font(Typo.ui(10.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                if let posted = bookmark.postedAt,
                   !Calendar.current.isDate(posted, inSameDayAs: bookmark.savedAt) {
                    Text("Posted \(RelativeDate.calendar(posted))")
                        .font(Typo.ui(9.5, .medium))
                        .foregroundStyle(Tokens.inkFaint)
                }
            }
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
                        PlatformBadge(platform: bookmark.platform, size: 16, pageURL: bookmark.url)
                    }
                    Text(bookmark.author ?? bookmark.platform.name)
                        .font(Typo.ui(11, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Tokens.inkFaint)
                    Text(RelativeDate.cardLine(saved: bookmark.savedAt, posted: bookmark.postedAt))
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

    static func calendar(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Liked/saved date, plus posted date when the page published one.
    static func cardLine(saved: Date, posted: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        let liked = label(for: saved, now: now, calendar: calendar)
        guard let posted, !calendar.isDate(posted, inSameDayAs: saved) else { return liked }
        return "\(liked) · posted \(Self.calendar(posted))"
    }
}
