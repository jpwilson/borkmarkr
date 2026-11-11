import SwiftUI

// MARK: - Covers

/// The cover a save wears when it has no picture of its own: its topic's clay
/// art on the clay ground (design/SYSTEM.md: "never an empty box, never a
/// gradient").
///
/// Looks for the art in order: the bundled `topic{Id}` scene (built-ins), the
/// App Group thumbnail the app keeps for every topic including custom ones
/// (`QuickFileArt`), then `remote` (a custom topic's server scene). With no
/// topic, or nothing found, it is the compass on the clay ground.
///
/// Reports no intrinsic size: give it a frame (or an aspect ratio) and it
/// fills it. Decorative — hidden from VoiceOver.
struct ClayCover: View {
    let topicID: String?
    var remote: URL? = nil

    init(topicID: String?, remote: URL? = nil) {
        self.topicID = topicID
        self.remote = remote
    }

    var body: some View {
        Tokens.clayGround
            .overlay { art }
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var art: some View {
        if let topicID, let image = UIImage(named: TopicMotif.asset(for: topicID)) ?? QuickFileArt.image(for: topicID) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else if let remote {
            RemoteImage(url: remote) { compass }
        } else {
            compass
        }
    }

    private var compass: some View {
        ClayArtImage(source: .quest(.compass))
    }
}

/// A real thumbnail when there is one, the topic's `ClayCover` underneath and
/// in its place when there isn't (or until it arrives — it cross-fades in).
///
/// The bitmap is an overlay, so it takes the cover's bounds and contributes no
/// intrinsic size: a loaded image can never enlarge the card (28 Sep zoom bug).
struct CoverImage: View {
    let url: URL?
    let topicID: String?

    init(url: URL?, topicID: String?) {
        self.url = url
        self.topicID = topicID
    }

    /// 1.3's signature. The palette can't say which topic's art to draw, so a
    /// missing picture shows the compass; move callers to `init(url:topicID:)`.
    init(url: URL?, palette: CategoryPalette) {
        self.url = url
        self.topicID = nil
    }

    var body: some View {
        ClayCover(topicID: topicID)
            .overlay {
                if let url { RemoteImage(url: url) }
            }
            .frame(maxWidth: .infinity)
            .clipped()
    }
}

// MARK: - Badges

/// Brand mark, not a two-letter tile. Letters read as a placeholder; these
/// are the shapes people actually recognise: X, IG camera, Shorts portrait
/// play, TikTok note, a globe (or the site favicon) for the open web.
struct PlatformBadge: View {
    let platform: Platform
    var size: CGFloat = 22
    var pageURL: URL? = nil

    var body: some View {
        let radius = size * (platform == .shorts ? 0.34 : 0.30)
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
        if platform == .web {
            webMark
        } else {
            PlatformMarks.Mark(
                platform: platform,
                canvas: size,
                optical: PlatformMarks.Size.optical(for: size)
            )
        }
    }

    @ViewBuilder
    private var webMark: some View {
        if let host = pageURL?.host, let icon = Self.faviconURL(for: host) {
            RemoteImage(url: icon, contentMode: .fit, inset: size * 0.16) { webFallback }
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

/// The save card (grid): one shape for every kind of save (SYSTEM.md, Main.dc).
///
/// White, hairline, radius 18, no shadow. A 4:3 cover flush to the top — the
/// save's picture, or its topic's clay art (text posts from X and Threads too)
/// — with the platform mark top-left and the running time bottom-right when
/// known. Under it: the title, 15/20 semibold, always two lines' worth of
/// space; then an 8 pt dot in the topic's mid and "Fitness › Mobility".
///
/// Every card in a row is the same height at a given width and text size, so
/// the Library's grid lines up. VoiceOver reads it as one element.
struct BookmarkCard: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.displayTitle)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BookmarkFiling(bookmark: bookmark)
            }
            .padding(.top, 9)
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .waitingForAnAccount(bookmark.isWaiting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BookmarkCard.spoken(bookmark))
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { CoverImage(url: bookmark.imageURL, topicID: bookmark.category?.id) }
            .overlay(alignment: .topLeading) {
                PlatformBadge(platform: bookmark.platform, size: 22, pageURL: bookmark.url)
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = bookmark.durationLabel {
                    DurationChip(text: duration).padding(8)
                }
            }
            .clipped()
    }

    /// One sentence for VoiceOver: title, where it's filed, where it's from.
    static func spoken(_ bookmark: Bookmark) -> String {
        var parts = [bookmark.displayTitle]
        parts.append(bookmark.isWaiting ? "Waiting for an account" : bookmark.filingPath)
        parts.append(bookmark.platform.name)
        if let duration = bookmark.durationLabel { parts.append("video, \(duration)") }
        if bookmark.hasNote { parts.append("has a note") }
        return parts.joined(separator: ", ")
    }

    /// Kept for the Library's masonry until it moves to a grid: every card is
    /// now the same height at a given width — the 4:3 cover plus the text
    /// block (9 + 40 + 4 + 18 + 11).
    @MainActor
    static func cachedEstimate(for bookmark: Bookmark, columnWidth: CGFloat) -> CGFloat {
        estimatedHeight(for: bookmark, columnWidth: columnWidth)
    }

    static func estimatedHeight(for bookmark: Bookmark, columnWidth: CGFloat) -> CGFloat {
        columnWidth * 0.75 + 82
    }
}

/// The running time on a cover: 20 pt, radius 6, ink at 72 %, white 11.5/600
/// tabular figures.
struct DurationChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.custom("Instrument Sans", size: 11.5, relativeTo: .caption2).weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minHeight: 20)
            .background(Tokens.ink.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Video, \(text)")
    }
}

/// The save row (list / compact density, Topic and Source pages, search): the
/// card's content in one row — a 56 pt cover at radius 10, the title, the
/// filing line and a meta line. White, hairline, radius 18, no shadow.
struct BookmarkRow: View {
    let bookmark: Bookmark
    var showPlatformBadge: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverImage(url: bookmark.imageURL, topicID: bookmark.category?.id)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.displayTitle)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                BookmarkFiling(bookmark: bookmark)
                HStack(spacing: 5) {
                    if showPlatformBadge {
                        PlatformBadge(platform: bookmark.platform, size: 16, pageURL: bookmark.url)
                    }
                    Text(metaLine)
                        .textRole(.meta)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .waitingForAnAccount(bookmark.isWaiting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BookmarkCard.spoken(bookmark))
    }

    private var metaLine: String {
        let when = RelativeDate.cardLine(saved: bookmark.savedAt, posted: bookmark.postedAt)
        guard let author = bookmark.displayAuthor else { return when }
        return "\(author) · \(when)"
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

/// The mark on a bork that is saved but not yet counted — it arrived over the
/// signed-out limit and is waiting for an account or for room. See `SaveLimit`.
///
/// Small and factual. "Waiting" rather than "Locked" or "Blocked", because
/// nothing was refused: the bork is right there, on the phone, and the only
/// thing it is short of is a slot.
struct WaitingPill: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock").font(.system(size: 8, weight: .black))
            Text("Waiting").font(Typo.ui(10, .heavy))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(Tokens.inkSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Tokens.mutedControl, in: Capsule())
        .accessibilityLabel("Waiting — sign up to keep this bork")
    }
}

/// Select mode's mark on a card: a hollow ring until tapped, a filled tick
/// after. Top-right, where every platform puts it, and on top of everything
/// else on the card — in select mode the only question is "this one?".
struct SelectionMark: View {
    let selected: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? accent.base : Tokens.surface.opacity(0.92))
            Circle()
                .stroke(selected ? accent.base : Tokens.inkFaint, lineWidth: 1.5)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(selected ? 0.18 : 0.10), radius: 4, y: 2)
        .animation(Motion.snap, value: selected)
        .accessibilityHidden(true)
    }
}

private struct Selectable: ViewModifier {
    let active: Bool
    let selected: Bool
    let radius: CGFloat
    @Environment(\.accent) private var accent

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && selected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(accent.base, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if active {
                    SelectionMark(selected: selected).padding(8)
                }
            }
            .accessibilityAddTraits(active && selected ? .isSelected : [])
            .accessibilityHint(active ? (selected ? "Tap to leave it out" : "Tap to include it in the link") : "")
    }
}

extension View {
    /// Select mode for a card or row: a ring in the corner, a tick and an
    /// outline once picked. Off (`active == false`) it draws nothing, so the
    /// feed is the same view in both modes and never re-lays out to switch.
    func selectable(_ active: Bool, selected: Bool, radius: CGFloat = Tokens.cardRadius) -> some View {
        modifier(Selectable(active: active, selected: selected, radius: radius))
    }

    /// Greys a bork that is waiting on an account.
    ///
    /// Colour is what the Library uses to mean "filed under something", so a
    /// waiting bork having none is the difference a glance can read. Desaturate
    /// rather than fade to near-nothing: the card still has to be legible and
    /// still has to be tappable, because deleting one of *these* is one of the
    /// ways a person makes room.
    @ViewBuilder
    func waitingForAnAccount(_ waiting: Bool) -> some View {
        if waiting {
            self.saturation(0).opacity(0.72)
        } else {
            self
        }
    }
}

/// The filing line on every card and row: an 8 pt dot in the topic's mid and
/// "Topic › Subtopic" in meta (13/18 secondary), one line. A waiting bork shows
/// the Waiting pill instead; a bork with a note gets the note dot at the end.
struct BookmarkFiling: View {
    let bookmark: Bookmark

    var body: some View {
        HStack(spacing: 6) {
            if bookmark.isWaiting {
                WaitingPill()
            } else {
                TopicDot(palette: bookmark.category?.palette ?? NeutralPalette.value)
                Text(bookmark.filingPath)
                    .textRole(.meta)
                    .lineLimit(1)
            }
            if bookmark.hasNote { NoteDot() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
