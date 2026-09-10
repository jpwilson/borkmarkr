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
///
/// **It always finishes.** The extension that shipped in 1.0.1 drew nothing
/// until the host had handed over the link, and waited for that forever. A
/// host that was slow to answer — Instagram has been — looked like a blank
/// sheet that had hung, with no way out but the home button. Now a card is on
/// screen from the first frame with a Cancel on it, each request to the host
/// gets 2.5 seconds, and a five-second watchdog completes the request
/// whatever state the rest is in. Exactly one of those paths finishes it; the
/// rest become no-ops. Whatever happened is left in the App Group as a
/// breadcrumb (`ShareOutcome`) so the app's share guide can say so.
///
/// **`@objc(ShareViewController)` is the fix for the blank sheet.** Info.plist
/// names the principal class `ShareViewController`, but a Swift class is
/// registered with the Objective-C runtime as `ShareExtension.ShareViewController`,
/// so iOS could not find it — the simulator log says exactly that — and
/// presented an empty sheet with nobody in it to complete the request. That
/// is the sheet Seb photographed. Giving the class its bare Objective-C name
/// makes the plist true; it is done here rather than by prefixing the plist
/// value because the plist is regenerated from project.yml on every
/// `xcodegen generate`, and a fix that lives in a generated file is not one.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private let card = StatusCard()
    private var done = false

    private enum Timing {
        /// A host that never calls back costs this much, not the whole share.
        static let perProvider: Duration = .milliseconds(2500)
        /// The request is completed by this point, no matter what.
        static let watchdog: Duration = .seconds(5)
        static let savedToast: Duration = .milliseconds(600)
        static let failedToast: Duration = .milliseconds(1800)
    }

    /// Everything the host gave us. 1.0.1 looked only at the first item; a
    /// host that put an empty first item ahead of the real one got nothing.
    private var items: [NSExtensionItem] {
        extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // iOS presents the extension as a sheet with its own opaque surface,
        // so `.clear` never showed the host through — it showed system grey.
        view.backgroundColor = StatusCard.Palette.paper
        showCard()

        Task { @MainActor in
            try? await Task.sleep(for: Timing.watchdog)
            finish(.timeout)
        }
        Task { @MainActor in await handleInput() }
    }

    private func showCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.onCancel = { [weak self] in self?.finish(.cancelled) }
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        card.showBusy("Saving to bookmarker…")
    }

    // MARK: - Reading the share

    @MainActor
    private func handleInput() async {
        let items = self.items
        guard !items.isEmpty else { return finish(.noLink) }

        // The post text, when the host gives it. X and Threads always do, and
        // the link is right there in it — no round trip to the host needed,
        // so a host that is slow to answer can't slow this down.
        for item in items {
            let caption = item.attributedContentText?.string
            if let url = ShareInput.firstURL(in: caption) {
                return save(url: url, caption: caption)
            }
        }

        for item in items {
            let caption = item.attributedContentText?.string
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                guard !done else { return }
                if let url = await Self.load(.url, from: provider, as: ShareInput.url(from:)) {
                    return save(url: url, caption: caption)
                }
            }
        }

        // Some apps hand over plain text with the link embedded.
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                guard !done else { return }
                if let text = await Self.load(.plainText, from: provider, as: ShareInput.text(from:)),
                   let url = ShareInput.firstURL(in: text) {
                    return save(url: url, caption: text)
                }
            }
        }

        finish(.noLink)
    }

    /// One request to the host, with a deadline. The host's reply and the
    /// deadline race; whichever comes first resumes the continuation and the
    /// other finds it already resumed and does nothing. The payload is
    /// converted inside the host's callback so only a value crosses back.
    private static func load<T: Sendable>(
        _ type: UTType,
        from provider: NSItemProvider,
        as convert: @escaping @Sendable (Any?) -> T?
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            provider.loadItem(forTypeIdentifier: type.identifier) { payload, _ in
                once.resume(convert(payload))
            }
            Task {
                try? await Task.sleep(for: Timing.perProvider)
                once.resume(nil)
            }
        }
    }

    // MARK: - Saving

    @MainActor
    private func save(url: URL, caption: String?) {
        guard !done else { return }
        let platform = Platform.detect(from: url)
        let title = ShareInput.title(from: caption, url: url)

        // X and Threads carry real post bodies; elsewhere the caption is just a
        // caption and shouldn't turn the card into a text post.
        let body: String? = platform.carriesTextPosts ? ShareInput.cleanBody(caption) : nil
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
            finish(.saved)
        } catch {
            finish(.couldntSave)
        }
    }

    /// The one exit. Whichever of the save, the Cancel, the watchdog or a
    /// "nothing here" gets here first wins; the rest are no-ops. A brief
    /// confirmation, then out of the way — a share extension that lingers is
    /// one people stop using — but a failure stays up long enough to read,
    /// because it tells them what to do instead.
    @MainActor
    private func finish(_ outcome: ShareOutcome) {
        guard !done else { return }
        done = true
        ShareOutcome.record(outcome, in: UserDefaults(suiteName: Store.appGroupID))

        if outcome == .cancelled {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            return
        }

        card.showResult(outcome.toast, succeeded: outcome == .saved)
        Task {
            try? await Task.sleep(for: outcome == .saved ? Timing.savedToast : Timing.failedToast)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

private extension ShareOutcome {
    var toast: String {
        switch self {
        case .saved: "Saved to bookmarker"
        case .noLink: "No link in that share — copy the link and paste it in bookmarker"
        case .timeout: "Couldn't read that link — copy it and paste it in bookmarker"
        case .couldntSave: "Couldn't save — copy the link and paste it in bookmarker"
        case .cancelled: ""
        }
    }
}

/// A continuation that can be told to resume from two places and only does
/// so once.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// The one piece of UI the extension has, over the host app's screen.
///
/// Busy: the app's card surface — white on paper, 20pt corners, a hairline —
/// with a spinner, what it's doing, and a Cancel. Done: the app's toast
/// (`ToastView` in RootView.swift): ink, white text, the tick in the same
/// green, so the two halves of a share look like one product. The palette is
/// `App/DesignSystem/Tokens.swift` by value, because the extension target
/// does not compile `App/`, and the type is the system font because the
/// app's fonts are bundled with the app, not with this.
private final class StatusCard: UIView {
    var onCancel: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let icon = UIImageView()
    private let label = UILabel()
    private let hairline = UIView()
    private let cancel = UIButton(type: .system)

    enum Palette {
        static let paper = UIColor(red: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEE / 255, alpha: 1)
        static let ink = UIColor(red: 0x19 / 255, green: 0x15 / 255, blue: 0x10 / 255, alpha: 1)
        static let inkSecondary = UIColor(red: 0x6E / 255, green: 0x65 / 255, blue: 0x5A / 255, alpha: 1)
        static let surface = UIColor.white
        static let hairline = UIColor(red: 0xEA / 255, green: 0xE4 / 255, blue: 0xDA / 255, alpha: 1)
        static let toastCheck = UIColor(red: 0x7B / 255, green: 0xE3 / 255, blue: 0xA4 / 255, alpha: 1)
        static let coral = UIColor(red: 0xFF / 255, green: 0x5A / 255, blue: 0x2D / 255, alpha: 1)
    }

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.borderWidth = 1

        spinner.hidesWhenStopped = true
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isHidden = true

        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let line = UIStackView(arrangedSubviews: [spinner, icon, label])
        line.axis = .horizontal
        line.alignment = .center
        line.spacing = 10
        line.isLayoutMarginsRelativeArrangement = true
        line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)

        var config = UIButton.Configuration.plain()
        config.title = "Cancel"
        config.baseForegroundColor = Palette.inkSecondary
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return attributes
        }
        cancel.configuration = config
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [line, hairline, cancel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            widthAnchor.constraint(lessThanOrEqualToConstant: 340),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showBusy(_ text: String) {
        backgroundColor = Palette.surface
        layer.borderColor = Palette.hairline.cgColor
        hairline.backgroundColor = Palette.hairline
        label.text = text
        label.textColor = Palette.ink
        spinner.color = Palette.ink
        spinner.startAnimating()
        icon.isHidden = true
        hairline.isHidden = false
        cancel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func showResult(_ text: String, succeeded: Bool) {
        spinner.stopAnimating()
        hairline.isHidden = true
        cancel.isHidden = true
        let symbol = succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        icon.tintColor = succeeded ? Palette.toastCheck : Palette.coral
        icon.isHidden = false
        label.text = text
        label.textColor = .white
        UIView.animate(withDuration: 0.18) {
            self.backgroundColor = Palette.ink
            self.layer.borderColor = Palette.ink.cgColor
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
