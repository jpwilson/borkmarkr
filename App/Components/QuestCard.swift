import SwiftUI

/// Shared side-quest chrome, on the save card's rules (design/SYSTEM.md):
/// flat, a 1 pt hairline, radius 18, no shadow.
///
/// - **Rail** (Library, Revisit, the side-quest guide): the quest's clay art
///   on top, its topic's clay tint underneath with the title and a count.
/// - **Row** (Browse › Side quests): the save row's shape with a larger art
///   thumb — white, the art at the left, title and filing line beside it.
struct QuestCard: View {
    enum Layout {
        case rail
        case row
    }

    let title: String
    let count: Int
    let palette: CategoryPalette
    var motif: QuestMotif = .compass
    /// Preferred over `motif` when set — `QuestCover.resolve` can land on a
    /// topic's clay scene, which no motif names. `motif` stays for callers
    /// that only have one.
    var cover: QuestCover? = nil
    var layout: Layout = .rail
    var suggested: Bool = false
    /// The "New side quest" slot at the end of a rail: a dashed tile of the
    /// same size, never a coloured block.
    var dashed: Bool = false
    var quiet: Bool = false
    var habit: Bool = false
    var topicName: String? = nil
    var blurb: String? = nil
    /// Footer text for a card that is neither a quest nor a seed — the
    /// guide's samples say what tapping does instead of counting borks.
    var caption: String? = nil
    /// The row draws its own white card unless something around it does
    /// (Browse's habit quests put the week strip in the same card).
    var framed: Bool = true

    /// The rail card's width. Its height follows the text size.
    static let railWidth: CGFloat = 168

    private var art: QuestCover { cover ?? .motif(motif) }

    var body: some View {
        switch layout {
        case .rail: rail
        case .row: row
        }
    }

    // MARK: Rail

    private var rail: some View {
        Group {
            if dashed {
                // Measured from the real card's skeleton, so the slot is
                // exactly as tall as its neighbours at every text size.
                railSkeleton
                    .hidden()
                    .overlay { dashedFace }
            } else {
                railCard
            }
        }
        .frame(width: Self.railWidth, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var railCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Tokens.clayGround
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { QuestCoverArt(cover: art) }
                .overlay(alignment: .topLeading) { badges.padding(8) }
                .clipped()
            railText
                .background(palette.tint)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Tokens.hairline, lineWidth: 1)
        )
    }

    private var railSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
            railText
        }
    }

    private var railText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .textRole(.cardTitle, color: Tokens.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
            Text(footerLine)
                .textRole(.meta, color: palette.deep)
                .lineLimit(1)
        }
        .padding(.top, 9)
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dashedFace: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Tokens.inkSecondary)
                .frame(width: 40, height: 40)
                .background(Tokens.surface, in: Circle())
                .overlay(Circle().strokeBorder(Tokens.hairline, lineWidth: 1))
            Text(title)
                .textRole(.cardTitle, color: Tokens.ink)
                .multilineTextAlignment(.center)
            Text(footerLine)
                .textRole(.meta)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
    }

    // MARK: Row (Browse)

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            QuestCoverArt(cover: art)
                .frame(width: 72, height: 72)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if topicName != nil { TopicDot(palette: palette) }
                    Text(rowMeta)
                        .textRole(.meta)
                        .lineLimit(1)
                }
                if habit {
                    Label("Daily habit", systemImage: "flame.fill")
                        .textRole(.meta, color: palette.deep)
                        .labelStyle(TightLabel())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if framed {
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .fill(Tokens.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                            .strokeBorder(Tokens.hairline, lineWidth: 1)
                    )
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Shared

    private var rowMeta: String {
        var parts: [String] = []
        if let topicName { parts.append(topicName) }
        parts.append(Copy.countedBorks(count))
        if quiet { parts.append("Quiet") }
        return parts.joined(separator: " · ")
    }

    private var footerLine: String {
        if let blurb, suggested { return blurb }
        if let caption { return caption }
        if dashed { return "Name what you’re after" }
        return Copy.countedBorks(count)
    }

    private var spoken: String {
        if dashed { return title }
        var parts = [title]
        if suggested { parts.append("suggested from your library") }
        if let topicName { parts.append(topicName) }
        parts.append(footerLine)
        if quiet { parts.append("quiet lately") }
        if habit { parts.append("daily habit") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var badges: some View {
        if suggested {
            badge(Copy.fromYourLibrary)
        } else if quiet {
            badge("Quiet")
        } else if habit {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.deep)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.9), in: Circle())
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.custom("Instrument Sans", size: 11.5, relativeTo: .caption2).weight(.semibold))
            .foregroundStyle(palette.deep)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(.white.opacity(0.9), in: Capsule())
    }
}

/// Icon and text 4 pt apart, for one-line labels inside rows.
private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .bold))
            configuration.title
        }
    }
}

/// Suggested quest from the library — hook + evidence + start. The save
/// row's shape: white, hairline, the clay scene at the left, and the start
/// as a quiet coral line rather than a filled pill.
struct QuestSeedRow: View {
    let seed: Mission.Seed
    @Environment(\.accent) private var accent

    private var cover: QuestCover {
        QuestCover.resolve(title: seed.title, categoryID: seed.categoryID, subcategory: seed.subcategory)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            QuestCoverArt(cover: cover)
                .frame(width: 72, height: 72)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(seed.title)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(seed.blurb)
                    .textRole(.meta)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let sample = seed.sampleTitles.first, !sample.isEmpty {
                    Text("“\(sample)”")
                        .textRole(.meta)
                        .italic()
                        .lineLimit(1)
                }
                HStack(spacing: 2) {
                    Text(Copy.startThisQuest)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                .foregroundStyle(accent.deep)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
