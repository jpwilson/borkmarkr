import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Hashable {
    case library, browse, search, you

    var title: String {
        switch self {
        case .library: "Library"
        case .browse: "Browse"
        case .search: "Search"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .library: "square.stack.fill"
        case .browse: "square.grid.2x2.fill"
        case .search: "magnifyingglass"
        case .you: "person.fill"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("accentKey") private var accentKey = AccentRamp.fallback.key
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("startingTab") private var startingTabRaw = AppTab.library.rawValue
    @AppStorage("interests") private var interestsRaw = ""

    @State private var tab: AppTab = .library
    @State private var showingAdd = false
    @State private var toast: String?
    @StateObject private var account = Account()

    /// Deep-link target when a category chip is tapped from a detail sheet.
    @State private var pendingTopic: String?

    private var accent: AccentRamp { AccentRamp.named(accentKey) }
    private var interests: [String] {
        interestsRaw.split(separator: ",").map(String.init)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Tokens.paper.ignoresSafeArea()

            Group {
                switch tab {
                case .library: LibraryView(onAdd: { showingAdd = true })
                case .browse: BrowseView(interests: interests, pendingTopic: $pendingTopic)
                case .search: SearchView()
                case .you: YouView(onReplayTour: { hasOnboarded = false }, account: account)
                }
            }
            .environment(\.accent, accent)

            TabDock(tab: $tab, onAdd: { showingAdd = true })
                .environment(\.accent, accent)

            if let toast {
                ToastView(text: toast)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.accent, accent)
        .tint(accent.base)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingAdd) {
            AddSheet(onSaved: { message in
                showToast(message)
                tab = .library
            })
            .environment(\.accent, accent)
        }
        .fullScreenCover(isPresented: .constant(!hasOnboarded)) {
            OnboardingView(
                accentKey: $accentKey,
                onFinish: { picked in
                    interestsRaw = picked.joined(separator: ",")
                    hasOnboarded = true
                }
            )
            .environment(\.accent, accent)
        }
        .onAppear {
            if let saved = AppTab(rawValue: startingTabRaw) { tab = saved }
            #if DEBUG
            if DebugSeed.isRequested {
                DebugSeed.run(in: context)
                hasOnboarded = true
            }
            #endif
            drain()
            Task { await account.sync(context: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            // The Share Extension queues saves while we're backgrounded; pick
            // them up the moment we're visible again.
            if phase == .active {
                drain()
                Task { await account.sync(context: context) }
            }
        }
        .onChange(of: pendingTopic) { _, value in
            if value != nil { tab = .browse }
        }
    }

    private func drain() {
        let count = Store.drainInbox(into: context)
        if count > 0 {
            showToast(count == 1 ? "1 new save" : "\(count) new saves")
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.1))
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

/// Floating dock: Library · Browse · [+] · Search · You.
struct TabDock: View {
    @Binding var tab: AppTab
    let onAdd: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                item(.library)
                item(.browse)
                Spacer().frame(width: 62)
                item(.search)
                item(.you)
            }
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                            .stroke(Tokens.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "191510").opacity(0.30), radius: 22, y: 14)
            )

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(accent.base, in: Circle())
                    .overlay(Circle().stroke(Tokens.paper, lineWidth: 3))
                    .shadow(color: accent.base.opacity(0.45), radius: 10, y: 6)
            }
            .offset(y: -24)
            .accessibilityLabel("Save a link")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func item(_ target: AppTab) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 3) {
                Image(systemName: target.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(target.title)
                    .font(Typo.ui(9.5, .semibold))
            }
            .foregroundStyle(tab == target ? accent.base : Tokens.inkFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == target ? [.isSelected] : [])
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tokens.toastCheck)
            Text(text)
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Tokens.toastBG, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}
