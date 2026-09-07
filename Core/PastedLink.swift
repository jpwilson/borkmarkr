import Foundation
import CoreTransferable

/// What the Add sheet's paste control hands back, and how a link is dug out of it.
///
/// **Why this type exists at all.** The paste card used to be
/// `PasteButton(payloadType: String.self)`, and the founder saw three different
/// things after copying a link out of Instagram or X: a working green button, a
/// card with no button in it, and a greyed-out button. All three are the same
/// bug. `PasteButton` decides for itself whether it can be tapped, by matching
/// the *content types* sitting on the pasteboard against the declared payload's
/// `Transferable` representations. "Copy link" in a fair number of apps writes
/// only a `public.url` item — no `public.utf8-plain-text` alongside it — and a
/// `String` payload does not match that, so the control renders disabled. It
/// also re-evaluates asynchronously, which is the third state: enabled a beat
/// after the sheet is already on screen.
///
/// So the payload accepts **both**: a `URL` item and a text item. Import only —
/// nothing in the app ever puts a `PastedLink` back on the pasteboard, and an
/// export representation would only add content types the button then advertises
/// it can write.
///
/// The button stays a *system* paste control for the reason recorded in
/// `AddSheet`: iOS grants it the paste without the "would like to paste from…"
/// dialog. A custom button that reads `UIPasteboard.general.string` itself is
/// what produced that dialog on every single tap.
struct PastedLink: Transferable {
    /// Exactly what was on the pasteboard — a URL's `absoluteString`, or the
    /// raw text. Turning it into a link is `url`'s job, not the importer's, so
    /// the parsing rules live in one place and are testable without a clipboard.
    let raw: String

    var url: URL? { PastedLink.firstURL(in: raw) }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in PastedLink(raw: url.absoluteString) })
        ProxyRepresentation(importing: { (text: String) in PastedLink(raw: text) })
    }
}

extension PastedLink {

    /// The first http(s) URL in whatever was copied. Pure — no pasteboard, no
    /// network — so `Scripts/test_pasted_link.swift` can exercise every shape.
    ///
    /// Shapes that actually turn up on the clipboard, in order of how often:
    /// a bare link; a link with a caption wrapped around it ("Check this out:
    /// …", or X's "… https://x.com/i/status/1 via @someone"); a link with no
    /// scheme; and text with no link in it at all.
    ///
    /// **First http(s) match wins.** Not the longest, not the last: the link
    /// someone means is the one at the front of what they copied. Non-web
    /// schemes are skipped rather than returned — `NSDataDetector` happily
    /// matches `mailto:` and phone numbers, and neither is a bork.
    static func firstURL(in raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // The overwhelmingly common case — the clipboard is just the link — is
        // answered without running the detector over it. Whitespace is the
        // cheap tell that there is prose around it.
        if !trimmed.contains(where: \.isWhitespace), let whole = webURL(from: trimmed) {
            return whole
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        for match in detector.matches(in: trimmed, range: range) {
            if let url = match.url, isWeb(url) { return url }
        }
        return nil
    }

    /// A single token to a URL, supplying `https://` when it was left off.
    private static func webURL(from token: String) -> URL? {
        if let scheme = declaredScheme(token) {
            guard scheme == "http" || scheme == "https",
                  let url = URL(string: token), url.host?.isEmpty == false else { return nil }
            return url
        }
        // No scheme, so this has to look like a host before we invent one.
        // Without the check "1.5" and "v2.0" become links.
        guard let url = URL(string: "https://\(token)"), let host = url.host, looksLikeHost(host) else { return nil }
        return url
    }

    /// The scheme the token declares, if it declares one.
    ///
    /// `URL(string:)` is no help here: it reads "example.com:8080/a" as the
    /// scheme "example.com", and prefixing `https://` onto "mailto:someone@x"
    /// yields a URL whose host is x — an email address turned into a bork. A
    /// scheme's body never starts with a digit; a port always does, which is
    /// the whole difference between the two.
    private static func declaredScheme(_ token: String) -> String? {
        guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else { return nil }
        let head = token[token.startIndex..<colon]
        guard head.first?.isLetter == true,
              head.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") })
        else { return nil }
        let after = token.index(after: colon)
        if after < token.endIndex, token[after].isNumber { return nil }
        return head.lowercased()
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Dotted, and ending in something that could be a TLD.
    private static func looksLikeHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2 else { return false }
        return tld.allSatisfy(\.isLetter)
    }
}
