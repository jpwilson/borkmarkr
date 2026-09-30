import AppIntents
import Foundation

/// "Save a link" — bookmarker in Shortcuts, Siri, the Action button and
/// Back Tap.
///
/// Copy a reel's link, press the Action button, done. Set up once in the
/// Shortcuts app as **Get Clipboard → Save a link**. It writes to the same
/// inbox the Share Extension does, so the link is saved instantly, filed the
/// same way a share is, and in the Library the next time the app is open —
/// the app never has to come to the front.
struct SaveLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Save a link"
    static let description = IntentDescription(
        "Saves a link to bookmarker — or the post's link out of copied text, like a caption."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Link or text",
               description: "A link, or text with a link in it.",
               inputOptions: String.IntentInputOptions(keyboardType: .URL, capitalizationType: .none, autocorrect: false))
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$input) to bookmarker")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = Self.link(in: input) else {
            throw $input.needsValueError("There's no link in that. Copy the post's link and try again.")
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = trimmed == url.absoluteString ? nil : trimmed
        try Store.enqueue(BookmarkDraft.handedOver(url: url, caption: caption))
        return .result(dialog: "Borked. It's in your library.")
    }

    /// The post's own link out of whatever was handed over: a bare link, or
    /// a copied caption with one in it. Same rules as the share sheet.
    static func link(in input: String) -> URL? {
        ShareInput.postURL(in: input) ?? ShareInput.url(from: input)
    }
}

/// Shows "Save a link" in Shortcuts and Spotlight without any setup.
struct BookmarkerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveLinkIntent(),
            phrases: [
                "Save a link to \(.applicationName)",
                "Bork a link with \(.applicationName)",
            ],
            shortTitle: "Save a link",
            systemImageName: "bookmark.fill"
        )
    }
}
