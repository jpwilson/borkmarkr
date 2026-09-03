import StoreKit
import SwiftUI

/// When bookmarker is allowed to ask for an App Store rating.
///
/// Apple shows the system prompt at most **three times per user per 365 days**
/// and silently swallows every call past that. So a badly timed ask doesn't just
/// irritate someone — it spends one of three chances a year on a shrug. The
/// policy is therefore: never on launch, never while someone is mid-task, and
/// only at a moment the app has visibly just worked.
///
/// The three moments, and why they're the ones:
/// - **An import finished.** Years of saves became a searchable library in one
///   step. It's the best thing the app does and the user has just watched it.
/// - **The 10th bork saved in the app.** Ten is past "trying it" and into
///   "using it", and it's reached by choice rather than by time passing.
/// - **The first bork opened from a search result.** This is the whole promise:
///   you went looking for something you saved months ago and it was there.
///
/// Two guards sit in front of all three. Nothing is asked until the app has been
/// installed three days — day-one enthusiasm isn't an opinion worth collecting —
/// and at most once per `CFBundleShortVersionString`, so someone who declines on
/// 1.0.1 isn't asked again until there's a new version worth rating.
@MainActor
enum ReviewPrompter {

    /// A moment where the app has just demonstrably worked.
    enum Moment {
        case importFinished(count: Int)
        case borkSaved
        case searchResultOpened
    }

    private static let firstLaunchKey = "firstLaunchAt"
    private static let promptedVersionKey = "reviewPromptedVersion"
    private static let saveCountKey = "inAppSaveCount"
    private static let saveMomentUsedKey = "reviewSaveMomentUsed"
    private static let searchMomentUsedKey = "reviewSearchMomentUsed"

    /// How long the app has to have been installed before it may ask.
    private static let minimumDaysInstalled = 3.0
    /// Which save counts as the milestone.
    private static let saveMilestone = 10

    /// Records the install date, once, on a path that always runs. Without a
    /// floor the three-day guard would pass on a fresh install.
    static func recordLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: firstLaunchKey) == nil else { return }
        defaults.set(Date.now, forKey: firstLaunchKey)
    }

    /// A found-it moment happened. Decides whether it counts, whether the guards
    /// allow an ask, and asks.
    static func reached(_ moment: Moment, _ request: RequestReviewAction) {
        let defaults = UserDefaults.standard

        // The counter runs whether or not we're allowed to ask: the tenth save
        // is the tenth save regardless of what day it lands on.
        if case .borkSaved = moment {
            defaults.set(defaults.integer(forKey: saveCountKey) + 1, forKey: saveCountKey)
        }

        guard qualifies(moment), guardsAllow else { return }

        // A moment is only spent when it actually produces an ask. If the
        // three-day guard blocked the tenth save, the eleventh carries it —
        // otherwise the moment is silently swallowed by a different rule.
        switch moment {
        case .importFinished: break
        case .borkSaved: defaults.set(true, forKey: saveMomentUsedKey)
        case .searchResultOpened: defaults.set(true, forKey: searchMomentUsedKey)
        }
        defaults.set(currentVersion, forKey: promptedVersionKey)

        // Every one of these moments coincides with a sheet closing or opening.
        // StoreKit presents into the active scene, and a prompt raised in the
        // middle of that transition is quietly dropped. Let it land first.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            request()
        }
    }

    private static func qualifies(_ moment: Moment) -> Bool {
        let defaults = UserDefaults.standard
        switch moment {
        case .importFinished(let count):
            return count >= 1
        case .borkSaved:
            return defaults.integer(forKey: saveCountKey) >= saveMilestone
                && !defaults.bool(forKey: saveMomentUsedKey)
        case .searchResultOpened:
            return !defaults.bool(forKey: searchMomentUsedKey)
        }
    }

    private static var guardsAllow: Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: promptedVersionKey) != currentVersion else { return false }
        guard let installed = defaults.object(forKey: firstLaunchKey) as? Date else { return false }
        return Date.now.timeIntervalSince(installed) >= minimumDaysInstalled * 86_400
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
