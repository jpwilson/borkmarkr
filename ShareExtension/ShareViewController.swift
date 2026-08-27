import UIKit
import UniformTypeIdentifiers

/// The primary way things get into bookmarker: you're in Instagram, you tap
/// Share, you pick bookmarker, it's saved.
///
/// **Engineering deviation.** v1 opened the SwiftData container here and wrote
/// directly. This queues a JSON draft into the App Group inbox instead and
/// exits — see `Store` for why. Practically it also matters because share
/// extensions run under a hard memory cap (~120MB) and are killed without
/// warning: booting a full persistent store to save one URL is both risky and
/// slow, and the user is staring at a spinner over someone else's app while it
/// happens.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleInput()
    }

    private func handleInput() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments, !providers.isEmpty
        else { return finish(message: nil) }

        Task { @MainActor in
            // Caption text, when the source app supplies it.
            let caption = item.attributedContentText?.string

            for provider in providers {
                if let url = await Self.loadURL(from: provider) {
                    return save(url: url, caption: caption)
                }
            }

            // Some apps hand over plain text with the link embedded.
            for provider in providers {
                if let text = await Self.loadText(from: provider),
                   let url = Self.firstURL(in: text) {
                    return save(url: url, caption: text)
                }
            }

            finish(message: "No link found")
        }
    }

    @MainActor
    private func save(url: URL, caption: String?) {
        let platform = Platform.detect(from: url)
        let title = Self.title(from: caption, url: url)

        // X and Threads carry real post bodies; elsewhere the caption is just a
        // caption and shouldn't turn the card into a text post.
        let body: String? = platform.carriesTextPosts ? Self.cleanBody(caption) : nil
        let suggestion = Categorizer.suggest(url: url, title: title, text: body)

        let draft = BookmarkDraft(
            url: url,
            title: title,
            author: Categorizer.fallbackAuthor(for: url),
            platform: platform,
            kind: platform.defaultKind,
            categoryID: suggestion.categoryID,
            subcategory: suggestion.subcategory,
            tags: suggestion.tags,
            text: body,
            isUnread: true
        )

        do {
            try Store.enqueue(draft)
            finish(message: "Saved to bookmarker")
        } catch {
            finish(message: "Couldn't save")
        }
    }

    private static func title(from caption: String?, url: URL) -> String {
        if let caption {
            let withoutURLs = caption
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.lowercased().hasPrefix("http") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if withoutURLs.count > 3 { return String(withoutURLs.prefix(140)) }
        }
        return Categorizer.fallbackTitle(for: url)
    }

    private static func cleanBody(_ caption: String?) -> String? {
        guard let caption else { return nil }
        let cleaned = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 3 ? cleaned : nil
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    /// Brief confirmation, then out of the way. A share extension that lingers
    /// is one people stop using.
    @MainActor
    private func finish(message: String?) {
        guard let message else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let toast = ToastLabel(text: message)
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task {
            try? await Task.sleep(for: .milliseconds(600))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

private final class ToastLabel: UIView {
    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
