import Foundation

/// What Quick File remembers, kept in the App Group's defaults so a choice
/// made in the app reaches the Share Extension.
///
/// The You page's toggle binds straight to the key:
/// `@AppStorage(QuickFileSettings.askAfterShareKey, store: QuickFileSettings.store) var ask = true`.
enum QuickFileSettings {
    static let askAfterShareKey = "quickFile.askAfterShare"
    static let filedCountKey = "quickFile.filedCount"
    /// "Tap to file" shows under the hub until this many filings.
    static let tapHintUses = 3

    static var store: UserDefaults? { UserDefaults(suiteName: Store.appGroupID) }

    /// "Ask where it goes after sharing". On unless turned off: off brings
    /// back the one-tap share that saves and leaves.
    static var askAfterShare: Bool {
        get { store?.object(forKey: askAfterShareKey) as? Bool ?? true }
        set { store?.set(newValue, forKey: askAfterShareKey) }
    }

    /// Filings made on the dial, counted only as far as the hint needs.
    static var filedCount: Int { store?.integer(forKey: filedCountKey) ?? 0 }

    static var showsTapHint: Bool { filedCount < tapHintUses }

    static func noteFiled() {
        guard let store else { return }
        let count = store.integer(forKey: filedCountKey)
        if count < tapHintUses { store.set(count + 1, forKey: filedCountKey) }
    }
}
