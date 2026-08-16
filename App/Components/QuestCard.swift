import SwiftUI

/// Shared side-quest chrome. Library is a poster; Browse is a wide row
/// with the same clay scene. Poster is the only style.
struct QuestCard: View {
    enum Layout {
        case rail
        case row
    }

    let title: String
    let count: Int
    let palette: CategoryPalette
    var motif: QuestMotif = .compass
    var layout: Layout = .rail
    var suggested: Bool = false
    var dashed: Bool = false
    var quiet: Bool = false
    var habit: Bool = false
    var topicName: String? = nil
    var blurb: String? = nil
    var sample: String? = nil

    var body: some View {
        switch layout {
        case .rail: rail
        case .row: row
        }
    }

    // MARK: Rail (Library)

    private var rail: some View {
        posterRail
            .frame(width: 176, height: 204, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(dashed ? Tokens.dashed : palette.deep.opacity(0.10),
                                  style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
            )
    }

    private var posterRail: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if dashed {
                    palette.tint
                } else {
                    QuestArt(motif: motif)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                badges
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 118)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typo.display(15, .bold))
                    .foregroundStyle(Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footerLine)
                    .font(Typo.ui(11, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.tint)
        }
    }

    // MARK: Row (Browse)

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Typo.display(18, .bold))
                    .foregroundStyle(Tokens.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let topicName {
                        Text(topicName)
                            .font(Typo.ui(11, .semibold))
                            .foregroundStyle(palette.deep)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.55), in: Capsule())
                    }
                    Text(Copy.countedBorks(count))
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                    if quiet {
                        Text("Quiet")
                            .font(Typo.ui(10, .bold))
                            .foregroundStyle(Tokens.inkMeta)
                    }
                }
            }
            Spacer(minLength: 4)

            if !dashed {
                QuestArt(motif: motif)
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [palette.tint, palette.tint.opacity(0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.deep.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: Shared

    private var footerLine: String {
        if let blurb, suggested { return blurb }
        if dashed { return "Name what you’re after" }
        return Copy.countedBorks(count)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if suggested {
                Text(Copy.fromYourLibrary)
                    .font(Typo.ui(10, .bold))
                    .foregroundStyle(palette.deep)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.72), in: Capsule())
            } else if quiet {
                Text("Quiet")
                    .font(Typo.ui(10, .bold))
                    .foregroundStyle(Tokens.inkMeta)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.72), in: Capsule())
            } else if habit {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.deep)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Suggested quest from the library — hook + evidence + start.
struct QuestSeedRow: View {
    let seed: Mission.Seed
    @Environment(\.accent) private var accent

    private var motif: QuestMotif {
        QuestMotif.resolve(title: seed.title, categoryID: seed.categoryID, subcategory: seed.subcategory)
    }

    private var palette: CategoryPalette {
        Taxonomy.category(id: seed.categoryID)?.palette ?? NeutralPalette.value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            QuestArt(motif: motif)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(seed.title)
                    .font(Typo.display(16, .bold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(seed.blurb)
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sample = seed.sampleTitles.first, !sample.isEmpty {
                    Text("“\(sample)”")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(Copy.startThisQuest)
                .font(Typo.ui(12.5, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(accent.base, in: Capsule())
        }
        .padding(14)
        .cardSurface(radius: 20)
    }
}
