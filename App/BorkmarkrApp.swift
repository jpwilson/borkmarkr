import SwiftUI
import SwiftData

@main
struct BorkmarkrApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Store.shared)
    }
}
