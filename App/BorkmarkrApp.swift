import SwiftUI
import SwiftData

@main
struct BorkmarkrApp: App {
    @AppStorage("accentHex") private var accentHex = Theme.defaultAccentHex

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.brandAccent, Color(hex: accentHex))
                .tint(Color(hex: accentHex))
                .preferredColorScheme(.light)
        }
        .modelContainer(Store.shared)
    }
}
