import SwiftUI
import SwiftData

@main
struct BorkmarkrApp: App {
    init() {
        // Custom topics resolve through `Taxonomy`'s installed extras, and the
        // first frame of cards is drawn before RootView's onAppear installs
        // them — so on a cold launch a "Trail running › Races" card read
        // "Races" until something else redrew it. Install before any view.
        let context = Store.shared.mainContext
        let topics = ((try? context.fetch(FetchDescriptor<CustomTopic>())) ?? []).filter { $0.deletedAt == nil }
        if !topics.isEmpty { _ = MergedTaxonomy(topics: topics) }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // `-quickFileShare <url>`: the Share Extension's Quick File screen, in the app.
            if let url = QuickFileHarness.launchURL { QuickFileHarness(url: url) } else { RootView() }
            #else
            RootView()
            #endif
        }
        .modelContainer(Store.shared)
    }
}
