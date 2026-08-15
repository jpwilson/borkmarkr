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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    picker
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
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Tokens.paper)
            .navigationTitle("What's interesting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task(id: window) { await refresh() }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    private var picker: some View {
        HStack(spacing: 3) {
            ForEach(SmartInsights.Window.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { window = option }
                } label: {
                    Text(option.label)
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(window == option ? Tokens.ink : Tokens.inkMeta)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(window == option ? Tokens.surface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Tokens.segmentTrack, in: Capsule())
    }

    @ViewBuilder
    private func reportView(_ report: SmartInsights.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(report.headline)
                .font(Typo.display(24, .heavy))
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.summary)
                .font(Typo.ui(15))
                .foregroundStyle(Tokens.bodyOnWhite)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(Copy.countedBorks(report.count))
                    .font(Typo.ui(11.5, .semibold))
                    .foregroundStyle(accent.deep)
                if report.fromModel {
                    Text("Read by Sonnet 5")
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                } else if account?.isSignedIn != true {
                    Text("Sign in for a sharper read")
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.base.opacity(0.2), lineWidth: 1)
        )

        if let spike = report.spike, !spike.isEmpty {
            Text(spike)
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(Tokens.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 16)
        }

        if !report.themes.isEmpty {
            Text("THEMES")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            ForEach(report.themes) { theme in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(theme.count)")
                        .font(Typo.display(18, .heavy))
                        .foregroundStyle(accent.deep)
                        .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.name)
                            .font(Typo.ui(14.5, .semibold))
                            .foregroundStyle(Tokens.ink)
                        if !theme.why.isEmpty {
                            Text(theme.why)
                                .font(Typo.ui(12.5))
                                .foregroundStyle(Tokens.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .cardSurface(radius: 16)
            }
        }

        if let quest = report.suggestedQuest, !quest.isEmpty {
            Button {
                onStartQuest?(quest)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start a side quest")
                            .font(Typo.ui(11.5, .semibold))
                            .foregroundStyle(accent.deep)
                        Text(quest)
                            .font(Typo.display(16, .bold))
                            .foregroundStyle(Tokens.ink)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent.base)
                }
                .padding(14)
                .cardSurface(radius: 16)
            }
            .buttonStyle(PressableStyle())
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
