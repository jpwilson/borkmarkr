import UIKit
import UniformTypeIdentifiers
import SwiftData

/// The whole point of the app: you're in Instagram, you tap Share, you pick
/// borkmarkr, it's saved. No app switch, no paste, no friction.
///
/// Deliberately writes straight into the shared App Group store and dismisses.
/// Categorising happens later in the app — the brief was explicit that saving
/// must never be blocked by organising.
final class ShareViewController: UIViewController {

    private let container = Store.make()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleInput()
    }

    private func handleInput() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments, !providers.isEmpty
        else {
            return finish(message: nil)
        }

        // A shared post usually arrives as a URL, but some apps hand over plain
        // text with the link embedded, so we try both.
        Task { @MainActor in
            let contextTitle = (item.attributedContentText?.string).flatMap {
                $0.isEmpty ? nil : $0
            }

            for provider in providers {
                if let url = await Self.loadURL(from: provider) {
                    save(url: url, sharedText: contextTitle)
                    return
                }
            }

            for provider in providers {
                if let text = await Self.loadText(from: provider),
                   let url = Self.firstURL(in: text) {
                    save(url: url, sharedText: text)
                    return
                }
            }

            finish(message: "No link found")
        }
    }

    @MainActor
    private func save(url: URL, sharedText: String?) {
        let title = Self.title(from: sharedText, url: url)
        let suggestion = Categorizer.suggest(url: url, title: title)

        do {
            try Store.save(
                url: url,
                title: title,
                categoryID: suggestion.categoryID,
                subcategory: suggestion.subcategory,
                tags: suggestion.tags,
                isUnread: true,
                in: container.mainContext
            )
            finish(message: "Saved to borkmarkr")
        } catch {
            finish(message: "Couldn't save")
        }
    }

    /// Prefer the text the source app handed us (usually the caption), falling
    /// back to a title derived from the URL slug.
    private static func title(from sharedText: String?, url: URL) -> String {
        if let sharedText {
            // Strip any URL out of the caption so the title isn't just the link.
            let withoutURLs = sharedText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.lowercased().hasPrefix("http") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if withoutURLs.count > 3 {
                return String(withoutURLs.prefix(140))
            }
        }

        let slug = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .last { $0.count > 3 && !$0.allSatisfy(\.isNumber) }

        guard let slug else { return Platform.detect(from: url).label + " link" }
        return slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
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

    /// Brief confirmation then dismiss — a share extension that lingers is a
    /// share extension people stop using.
    @MainActor
    private func finish(message: String?) {
        guard let message else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let toast = ToastView(text: message)
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task {
            try? await Task.sleep(for: .milliseconds(650))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

private final class ToastView: UIView {
    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 0.92)
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
