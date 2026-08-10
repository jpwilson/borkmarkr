import Foundation

/// Launch-argument overrides used only when capturing App Store screenshots.
///
/// Screenshots have to be retaken every time the UI changes, so the capture
/// needs to be a script, not a person tapping through the simulator and hoping
/// they land on the same state. `DebugSeed` already handles "put a realistic
/// library in the store"; this handles the few screens that also need a bit of
/// UI state — Search looks empty and lifeless until something is typed in it.
///
/// Compiles in Release and returns the real defaults there: the arguments
/// aren't parsed at all outside DEBUG, so no launch argument can put a shipped
/// build into a screenshot state.
enum ScreenshotDefaults {

    /// `-query "protein"` pre-fills Search so the capture shows results rather
    /// than the empty state.
    static var searchQuery: String { value(for: "-query") ?? "" }

    private static func value(for flag: String) -> String? {
        #if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        let next = arguments[index + 1]
        return next.hasPrefix("-") ? nil : next
        #else
        return nil
        #endif
    }
}
