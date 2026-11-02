#if DEBUG
import SwiftUI
import UIKit

/// `-quickFileShare <url>` (DEBUG builds only) opens the Share Extension's
/// Quick File screen inside the app, in a sheet over a stand-in host app, so
/// it can be seen, turned and photographed in the Simulator. A share
/// extension can't be launched from a script.
///
/// It runs the extension's own code — `BookmarkDraft.handedOver`,
/// `QuickFileShareSession`, `QuickFileShareView` — with three differences:
/// the inbox writes are printed, not written, so nothing lands in the
/// library; topic art falls back to the app's bundled scenes when the App
/// Group has no thumbnails yet; and the page and the model are asked with
/// the app's own session (refreshed if it must be), not a borrowed one.
/// Memory is the App Group snapshot when the app has written one, otherwise
/// a small made-up history (@kaylawalks filed under Fitness three times) so
/// the learned state shows without a seeded library.
///
///     -caption "<text>"     what the host app sent along with the link
///     -quickFileNoMemory    a first share, with no history at all
struct QuickFileHarness: View {
    let url: URL

    /// One share. The sheet is bound to this rather than to a flag, so it can
    /// never open on a stale (empty) session.
    private struct Share: Identifiable {
        let id = UUID()
        let session: QuickFileShareSession
    }

    @State private var share: Share?
    @State private var outcome: String?
    @StateObject private var account = Account()

    static var launchURL: URL? { argument(after: "-quickFileShare").flatMap { URL(string: $0) } }

    private static func argument(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// The extension's look, with the bundled clay scenes standing in for
    /// thumbnails the app hasn't copied over yet.
    private static let style: QuickFileStyle = {
        var style = QuickFileStyle.system
        style.art = { topicID in QuickFileArt.image(for: topicID) ?? UIImage(named: TopicMotif.asset(for: topicID)) }
        return style
    }()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Quick File harness")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                Text(outcome ?? url.absoluteString)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("Share it again") { startShare() }
                    .buttonStyle(.borderedProminent)
                    .tint(QuickFileStyle.coral)
            }
            .padding(32)
        }
        .sheet(item: $share, onDismiss: {
            if outcome == nil { outcome = "Swiped away. The save stays, filed as our guess." }
        }) { share in
            QuickFileShareView(
                session: share.session,
                style: Self.style,
                onNotNow: { close("Not now: kept \(Self.describe(share.session.kept)).") },
                onDone: { close("Filed to \(QuickFileCopy.label($0)) as your pick.") }
            )
            .presentationDetents([.large])
            .onDisappear { share.session.close() }
        }
        .onAppear { if share == nil, outcome == nil { startShare() } }
        .preferredColorScheme(.light)
    }

    private func startShare() {
        let draft = BookmarkDraft.handedOver(url: url, caption: Self.argument(after: "-caption"))
        print("[QuickFileHarness] tap 1 would enqueue \(Self.describe(draft))")
        let snapshot: FilingSnapshot? = CommandLine.arguments.contains("-quickFileNoMemory")
            ? nil
            : FilingSnapshot.loadShared() ?? Self.demoSnapshot(now: .now)
        let session = QuickFileShareSession(saved: draft, snapshot: snapshot) { draft in
            print("[QuickFileHarness] would enqueue \(Self.describe(draft))")
        }
        outcome = nil
        share = Share(session: session)
        Task { session.startEnriching(with: await account.currentSession()) }
    }

    private func close(_ line: String) {
        share?.session.close()
        outcome = line
        share = nil
    }

    private static func describe(_ draft: BookmarkDraft) -> String {
        let topic = draft.categoryID.map { QuickFileCopy.topicName($0) } ?? "unfiled"
        let sub = draft.subcategory.map { " › \($0)" } ?? ""
        return "\(topic)\(sub) (\(draft.filingSource ?? "automatic"))"
    }

    /// Three filings of @kaylawalks (two Mobility, one Running) and two
    /// habits, so a share of her video arrives strong.
    private static func demoSnapshot(now: Date) -> FilingSnapshot {
        func filing(_ topic: String, _ sub: String, creator: String? = nil, daysAgo: Double) -> FilingHistoryItem {
            FilingHistoryItem(categoryID: topic, subcategory: sub, creator: creator, domain: nil,
                              at: now.addingTimeInterval(-daysAgo * 86_400))
        }
        let history = [
            filing("fitness", "Mobility", creator: "kaylawalks", daysAgo: 2),
            filing("fitness", "Mobility", creator: "kaylawalks", daysAgo: 9),
            filing("fitness", "Running", creator: "kaylawalks", daysAgo: 20),
            filing("recipes", "Meal prep", daysAgo: 3),
            filing("money", "Budgeting", daysAgo: 12),
        ]
        return FilingSnapshot(memory: .build(from: history, now: now), customTopics: [], customSubs: [:])
    }
}
#endif
