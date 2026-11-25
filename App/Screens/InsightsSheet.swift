import SwiftUI
import SwiftData

/// Day / week / month read of the library. Offline instantly; Sonnet 5
/// sharpens it when signed in.
struct InsightsSheet: View {
    let bookmarks: [Bookmark]
    var account: Account?
    var onStartQuest: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    @State private var window = SmartInsights.Window.week
    @State private var report: SmartInsights.Report?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            ClaySheetHeader(title: "What's interesting") { dismiss() }
                .padding(.horizontal, Tokens.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ClaySegmented(
                        selection: $window,
                        options: SmartInsights.Window.allCases.map { ($0, $0.label) }
                    )
                    .padding(.bottom, 4)
                    if let report {
                        reportView(report)
                    } else if loading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(Tokens.paper)
        .task(id: window) { await refresh() }
        .presentationDetents([.large])
        .claySheet()
    }

    @ViewBuilder
    private func reportView(_ report: SmartInsights.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.headline)
                .textRole(.screenTitle, color: Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.summary)
                .textRole(.body, color: Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(Copy.countedBorks(report.count))
                    .textRole(.meta, color: accent.deep)
                if report.fromModel {
                    Text("· Read by Sonnet 5").textRole(.meta)
                } else if account?.isSignedIn != true {
                    Text("· Sign up for a sharper read").textRole(.meta)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)

        if let spike = report.spike, !spike.isEmpty {
            Text(spike)
                .textRole(.cardTitle, color: Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }

        if !report.themes.isEmpty {
            Text("Themes")
                .textRole(.label, color: Tokens.inkSecondary)
                .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(Array(report.themes.enumerated()), id: \.offset) { offset, theme in
                    if offset > 0 { Tokens.hairline.frame(height: 1).padding(.leading, 64) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(theme.count)")
                            .textRole(.sectionTitle, color: accent.deep)
                            .monospacedDigit()
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.name)
                                .textRole(.cardTitle, color: Tokens.ink)
                            if !theme.why.isEmpty {
                                Text(theme.why)
                                    .textRole(.meta)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .cardSurface()
        }

        if let quest = report.suggestedQuest, !quest.isEmpty {
            Button {
                onStartQuest?(quest)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    ClayArtImage(source: .quest(.compass))
                        .frame(width: 44, height: 44)
                        .background(Tokens.clayGround)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Start a side quest").textRole(.meta)
                        Text(quest)
                            .textRole(.cardTitle, color: Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.deep)
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
                .frame(minHeight: Tokens.slimRowHeight)
                .cardSurface()
            }
            .buttonStyle(PressableStyle(scale: 0.99))
            .padding(.top, 8)
        }
    }

    private func refresh() async {
        loading = report == nil
        let next = await SmartInsights.analyze(bookmarks, window: window, session: await account?.currentSession())
        withAnimation(.easeOut(duration: 0.2)) {
            report = next
            loading = false
        }
    }
}
