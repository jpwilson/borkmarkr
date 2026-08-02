import Foundation

/// Where a saved link came from. Detected from the URL host so the user never
/// has to tell us — the brief's "that is information that's kept".
enum Platform: String, Codable, CaseIterable, Sendable {
    case instagram, x, threads, youtube, youtubeShorts, tiktok, pinterest, reddit, web

    var label: String {
        switch self {
        case .instagram: "Instagram"
        case .x: "X"
        case .threads: "Threads"
        case .youtube: "YouTube"
        case .youtubeShorts: "Shorts"
        case .tiktok: "TikTok"
        case .pinterest: "Pinterest"
        case .reddit: "Reddit"
        case .web: "Web"
        }
    }

    /// SF Symbol standing in for each platform's mark — Apple forbids shipping
    /// third-party logos without licence, and these read clearly enough.
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .x: "bird"
        case .threads: "at"
        case .youtube, .youtubeShorts: "play.rectangle"
        case .tiktok: "music.note"
        case .pinterest: "pin"
        case .reddit: "bubble.left.and.bubble.right"
        case .web: "globe"
        }
    }

    /// Hex tint used for the source chip.
    var tintHex: String {
        switch self {
        case .instagram: "E1306C"
        case .x: "111111"
        case .threads: "444444"
        case .youtube, .youtubeShorts: "FF0033"
        case .tiktok: "00C2CB"
        case .pinterest: "E60023"
        case .reddit: "FF4500"
        case .web: "7A7A7A"
        }
    }

    /// Best-effort detection from a URL. Unknown hosts fall back to `.web`,
    /// which is a legitimate outcome, not a failure.
    static func detect(from url: URL) -> Platform {
        guard var host = url.host?.lowercased() else { return .web }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }

        let path = url.path.lowercased()

        switch host {
        case "instagram.com", "instagr.am", "ig.me":
            return .instagram
        case "x.com", "twitter.com", "t.co":
            return .x
        case "threads.net", "threads.com":
            return .threads
        case "youtube.com", "youtu.be", "music.youtube.com":
            return path.contains("/shorts/") ? .youtubeShorts : .youtube
        case "tiktok.com", "vm.tiktok.com", "vt.tiktok.com":
            return .tiktok
        case "pinterest.com", "pin.it":
            return .pinterest
        case "reddit.com", "redd.it":
            return .reddit
        default:
            return .web
        }
    }
}
