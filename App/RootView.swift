import SwiftUI
import SwiftData

/// The five tabs from the design: Feed, Explore, Add, Search, You.
/// Add sits in the middle as the primary action — the brief's "the main two
/// things you're doing is adding links and scrolling your links".
struct RootView: View {
    @AppStorage("startingTab") private var startingTabRaw = Tab.feed.rawValue
    @State private var tab: Tab = .feed
    @State private var showingAdd = false

    enum Tab: String, CaseIterable {
        case feed, explore, search, you

        var title: String {
            switch self {
            case .feed: "Feed"
            case .explore: "Explore"
            case .search: "Search"
            case .you: "You"
            }
        }

        var symbol: String {
            switch self {
            case .feed: "square.stack.fill"
            case .explore: "square.grid.2x2.fill"
            case .search: "magnifyingglass"
            case .you: "person.fill"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                FeedView().tag(Tab.feed)
                    .tabItem { Label(Tab.feed.title, systemImage: Tab.feed.symbol) }
                ExploreView().tag(Tab.explore)
                    .tabItem { Label(Tab.explore.title, systemImage: Tab.explore.symbol) }
                SearchView().tag(Tab.search)
                    .tabItem { Label(Tab.search.title, systemImage: Tab.search.symbol) }
                YouView().tag(Tab.you)
                    .tabItem { Label(Tab.you.title, systemImage: Tab.you.symbol) }
            }

            AddButton { showingAdd = true }
                .padding(.bottom, 52)
        }
        .sheet(isPresented: $showingAdd) {
            AddView()
        }
        .onAppear {
            if let saved = Tab(rawValue: startingTabRaw) { tab = saved }
        }
    }
}

/// Floating "+" — deliberately overlapping the tab bar so adding is always one
/// tap from anywhere.
private struct AddButton: View {
    @Environment(\.brandAccent) private var accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(accent, in: Circle())
                .shadow(color: accent.opacity(0.4), radius: 12, y: 6)
        }
        .accessibilityLabel("Add a link")
    }
}
