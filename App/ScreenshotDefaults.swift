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

    /// `-topic fitness` opens Browse straight onto a topic page.
    ///
    /// The topic page is reachable only by tapping a tile, so without this
    /// there is no reproducible way to capture it — and the hero band and the
    /// share card both live there.
    static var openTopic: String? { value(for: "-topic") }

    /// `-dumpShareCard <path>` writes the rendered share card to a PNG.
    ///
    /// The card is an `ImageRenderer` product, not a screen: nothing exists
    /// for `simctl io screenshot` to point at until someone has opened the
    /// share sheet. This writes exactly the image that gets shared.
    static var shareCardDumpPath: String? { value(for: "-dumpShareCard") }

    // MARK: - Save-limit states

    /// `-borks 18` seeds exactly that many live borks instead of the full set.
    ///
    /// The save-limit surfaces are the first thing in the app whose appearance
    /// depends on *how many* borks there are — the countdown at 15, the wall at
    /// 20 — and the seed's fixed ~38 is past both. Without this there is no
    /// reproducible way to photograph "5 saves left".
    static var seedBorks: Int? { value(for: "-borks").flatMap(Int.init) }

    /// `-waiting 3` adds that many borks flagged `waitingSince`, on top of
    /// whatever `-borks` seeded. Waiting borks arrive from the Share Extension
    /// over the limit, which a simulator cannot reproduce on demand.
    static var seedWaiting: Int { value(for: "-waiting").flatMap(Int.init) ?? 0 }

    /// `-signedOut` ignores any real session in the Keychain.
    static var forceSignedOut: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-signedOut")
        #else
        return false
        #endif
    }

    /// `-signedIn` fakes a session, so the signed-in screens — where none of
    /// the limit exists — can be captured without an emailed code. The token
    /// is nonsense and every network call it makes will fail, which is fine:
    /// what is being photographed is what the UI does with `isSignedIn`.
    static var fakeSession: Supabase.Session? {
        #if DEBUG
        guard CommandLine.arguments.contains("-signedIn") else { return nil }
        return Supabase.Session(
            accessToken: "debug", refreshToken: "debug",
            expiresAt: .now.addingTimeInterval(3600),
            userID: "00000000-0000-0000-0000-000000000000",
            email: "you@bookmarker.lol"
        )
        #else
        return nil
        #endif
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
