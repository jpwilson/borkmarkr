import SwiftUI
import SwiftData

/// Library (and You) door into the weekly read.
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
        Group {
            if compact { compactCard } else { heroCard }
        }
    }

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Copy.insightsQuestion)
                    .font(Typo.display(18, .bold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(report.count == 0 ? Copy.insightsFallback : report.headline)
                    .font(Typo.ui(13, .semibold))
                    .foregroundStyle(accent.deep)
                    .fixedSize(horizontal: false, vertical: true)

                if report.count > 0 {
                    Text(report.summary)
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            QuestArt(motif: .scroll)
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [accent.tint, accent.tint.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.base.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: accent.base.opacity(0.12), radius: 16, y: 8)
    }

    private var compactCard: some View {
        HStack(spacing: 11) {
            QuestArt(motif: .scroll)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.insightsQuestion)
                    .font(Typo.ui(14, .bold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                Text(report.count == 0 ? Copy.insightsFallback : report.headline)
                    .font(Typo.ui(12, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tokens.inkFaint)
        }
        .padding(14)
        .cardSurface(radius: 18)
    }
}
