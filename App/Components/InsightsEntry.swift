import SwiftUI
import SwiftData

/// The door into the weekly read: the hero card on You, the compact row at the
/// top of Revisit (it left the Library in 1.4).
///
/// The question is the label. The live headline is the pop — it names the
/// actual thread in the last seven days, not a marketing heading.
struct InsightsEntry: View {
    let bookmarks: [Bookmark]
    var compact: Bool = false

    @Environment(\.accent) private var accent

    private var report: SmartInsights.Report {
        let week = SmartInsights.slice(bookmarks, window: .week)
        return SmartInsights.offline(week, window: .week)
    }

    var body: some View {
        // Built once per render. As a computed property it was rebuilt on
        // every read — three or four full passes over the week per render.
        let report = self.report
        Group {
            if compact { compactCard(report) } else { heroCard(report) }
        }
    }

    private func heroCard(_ report: SmartInsights.Report) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.insightsQuestion)
                    .textRole(.sectionTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(report.count == 0 ? Copy.insightsFallback : report.headline)
                    .textRole(.cardTitle, color: accent.deep)
                    .fixedSize(horizontal: false, vertical: true)

                if report.count > 0 {
                    Text(report.summary)
                        .textRole(.meta)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ClayArtImage(source: .quest(.scroll))
                .frame(width: 76, height: 76)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    /// Revisit's opener: the question and this week's thread on one white row.
    private func compactCard(_ report: SmartInsights.Report) -> some View {
        HStack(spacing: 12) {
            ClayArtImage(source: .quest(.scroll))
                .frame(width: 44, height: 44)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(Copy.insightsQuestion)
                    .textRole(.cardTitle, color: Tokens.ink)
                    .lineLimit(2)
                Text(report.count == 0 ? Copy.insightsFallback : report.headline)
                    .textRole(.meta, color: accent.deep)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.inkSecondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
