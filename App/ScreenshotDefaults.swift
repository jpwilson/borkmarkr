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

    /// `-query "protein"` pre-fills the search field at the top of Browse, so
    /// the capture shows results rather than the topic grid.
    static var searchQuery: String { value(for: "-query") ?? "" }

    /// `-scopes "tags"` (or `"topics,tags"`) pre-selects the scope chips under
    /// the field. Scoped results are the thing 1.1 added and the thing a
    /// screenshot has to show; there is no launch state that produces them
    /// otherwise, and tapping two chips by hand is exactly the unrepeatable
    /// step this file exists to remove.
    static var searchScopes: SearchScope {
        guard let raw = value(for: "-scopes") else { return [] }
        return raw
            .split(separator: ",")
            .reduce(into: SearchScope()) { scopes, name in
                switch name.trimmingCharacters(in: .whitespaces).lowercased() {
                case "topics": scopes.insert(.topics)
                case "subtopics": scopes.insert(.subtopics)
                case "tags": scopes.insert(.tags)
                default: break
                }
            }
    }

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
