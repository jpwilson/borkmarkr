import SwiftUI
import SwiftData

@main
struct BorkmarkrApp: App {
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
