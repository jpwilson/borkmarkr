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

    /// `-add` opens the Add sheet on launch; `-add <url>` opens it with that
    /// link already in the field, so the capture lands on the details step.
    ///
    /// Same reason as `-topic`: the Add sheet is behind a tap on the dock's +,
    /// and its three most interesting states — the paste card, the paste card
    /// absent, and "Already in your library" — differ only by what is on the
    /// pasteboard and in the store. None of them is reachable from a launch
    /// argument otherwise, and all three have to be re-photographed whenever
    /// the sheet changes.
    static var openAdd: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-add")
        #else
        return false
        #endif
    }

    static var addURL: URL? { value(for: "-add").flatMap { URL(string: $0) } }

    /// `-triage` opens "Sort your borks" on launch; `-triage guesses` opens
    /// its second deck, "Check our guesses".
    ///
    /// Triage sits behind the Library's banner, a toast or a button on the
    /// "Not filed yet" page, so a capture of it needs a launch state of its
    /// own. With `-seed` there are eight unfiled saves to sort, two of them
    /// from creators the seed has filed before.
    static var openTriage: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-triage")
        #else
        return false
        #endif
    }

    static var triageDeck: String? { value(for: "-triage") }

    /// `-proSheet` opens the Pro sheet over the Library, as the 100-bork
    /// milestone would. Run it with `-seed`, which finishes the first-run
    /// tour and puts a library behind the sheet.
    ///
    /// The milestone fires once each at 100, 250 and 500 and never on a
    /// fresh install, so nothing else reaches it on demand.
    static var openProSheet: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-proSheet")
        #else
        return false
        #endif
    }

    /// `-picker "runn"` opens the topic picker over the Add sheet with that
    /// already typed, which is the only state where the picker's ordering —
    /// the thing being photographed — exists at all.
    static var pickerQuery: String? { value(for: "-picker") }

    /// `-myTopics "Running"` seeds those as custom topics (comma-separated).
    ///
    /// The seed makes one, "Trail running". The picker's ordering rule is
    /// about a topic whose *name* is what you typed beating a built-in that
    /// only holds a matching subtopic, so photographing it needs a topic named
    /// exactly that, and which one it is depends on the shot.
    static var seedCustomTopics: [String] {
        (value(for: "-myTopics") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `-quickFileChosen` starts the Add sheet's dial and the Quick File
    /// harness already chosen on the top candidate, as a tap would leave
    /// them, so the refine panel can be photographed; `simctl` can't tap.
    static var quickFileChosen: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-quickFileChosen")
        #else
        return false
        #endif
    }

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

    // MARK: - 1.4 design review ("Quiet clay")
    //
    // Screens that no launch argument reached in 1.3. The foundation declares
    // every accessor here; each screen's owner wires its own consumer (an
    // `.onAppear` in that screen). Where the two 1.4 plans named a flag
    // differently, both spellings work. All DEBUG-only, like everything above.

    /// `-detail 0` (an index into the Library's newest-first list) or
    /// `-detail <stableID>`; `-detail first` is index 0. Opens `DetailSheet`.
    /// Consumer: LibraryView.
    static var openDetail: String? {
        guard let raw = value(for: "-detail") else { return nil }
        return raw == "first" ? "0" : raw
    }

    /// `-auth signIn` / `-auth signUp` opens `AuthSheet` in that mode.
    /// Consumer: RootView (wired).
    static var openAuth: String? { value(for: "-auth") }

    /// `-importSheet` (or `-import`) opens `ImportSheet` from You.
    /// Consumer: YouView.
    static var openImport: Bool { contains("-importSheet") || contains("-import") }

    /// `-onboardingPage 2` starts the first-run tour on that page (1-based).
    /// Consumer: OnboardingView.
    static var onboardingPage: Int? { value(for: "-onboardingPage").flatMap(Int.init) }

    /// `-libraryAt rail|rest` (or `-libraryScroll rail|end`) scrolls the
    /// Library to the side-quest rail or the saves after it. Returns "rail" or
    /// "rest" ("end" is read as "rest"). Consumer: LibraryView (ScrollViewReader ids).
    static var libraryAnchor: String? {
        guard let raw = value(for: "-libraryAt") ?? value(for: "-libraryScroll") else { return nil }
        return raw == "end" ? "rest" : raw
    }

    /// `-insights` opens `InsightsSheet` ("What are you finding interesting?")
    /// over Revisit. Consumer: RevisitView.
    static var openInsights: Bool { contains("-insights") }

    /// `-revisitQueue` opens `RevisitQueueSheet`. Consumer: RevisitView.
    static var openRevisitQueue: Bool { contains("-revisitQueue") }

    /// `-source tiktok` (or `-sourcePage tiktok`) opens Browse on that
    /// platform's Source page (a `Platform` raw value). Consumer: BrowseView.
    static var openSource: String? { value(for: "-source") ?? value(for: "-sourcePage") }

    /// `-wall` raises the save-limit wall; `-wall waiting` / `-wall addSheet`
    /// pick its other two wordings. Consumer: RootView (wired).
    static var openWall: String? {
        guard contains("-wall") else { return nil }
        return value(for: "-wall") ?? "add"
    }

    /// `-shareGuide` opens `ShareSheetGuide` (how to share into bookmarker).
    /// Consumer: YouView or OnboardingView, whichever presents it.
    static var openShareGuide: Bool { contains("-shareGuide") }

    /// `-newQuest` opens `NewMissionSheet` on Browse's Side quests.
    /// Consumer: MissionsView.
    static var openNewQuest: Bool { contains("-newQuest") }

    /// `-neutralCovers` draws every save's cover as its topic's clay art, the
    /// cover a save with no picture of its own wears. Consumer: `CoverImage`.
    ///
    /// The website's screenshots show the Library both ways, the real
    /// creators' thumbnails cross-fading over the clay, and that needs the
    /// same screen photographed twice from the same store. Switching at render
    /// time rather than in the seed means no reseed between the two shots, so
    /// nothing but the covers can differ.
    static let neutralCovers: Bool = contains("-neutralCovers")

    /// `-toast "Filed to Fitness"` shows that toast a moment after launch,
    /// with an Undo action, so its placement above the tab bar can be
    /// photographed. Consumer: RootView (wired).
    static var toast: String? { value(for: "-toast") }

    private static func contains(_ flag: String) -> Bool {
        #if DEBUG
        return CommandLine.arguments.contains(flag)
        #else
        return false
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
