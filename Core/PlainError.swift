import Foundation

/// Errors as a person would say them.
///
/// A raw `error.localizedDescription` ("Expected 3 parts in JWT; got 1", "The
/// network connection was lost.", "Couldn't reach the summary service") is for
/// the log, not the screen. Every place that used to show one shows
/// `PlainError.message(error, doing:)` instead, and logs the raw text in DEBUG.
/// Mirrors docs/index.html's "Errors as a person would say them".
///
/// Foundation only, so it compiles into both targets and under `swiftc`.
enum PlainError {

    /// One short sentence: what didn't happen, and what to do about it.
    ///
    /// `doing` is the thing that failed, as a verb phrase that fits
    /// "Couldn't …": "back up", "load your links", "sign you in". Pass nil for
    /// a generic line.
    static func message(_ error: Error?, doing: String? = nil) -> String {
        let what = doing.map { "Couldn't \($0)" } ?? "That didn't work"
        switch kind(of: error) {
        case .offline:
            return "\(what) — you're offline. We'll try again when you're back."
        case .timeout:
            return "\(what) — the connection is slow. Try again in a moment."
        case .signedOut:
            return "\(what) — please sign in again."
        case .server:
            return "\(what) right now. We'll try again soon."
        case .cancelled:
            return ""
        case .other:
            return "\(what). Try again in a moment."
        }
    }

    /// The broad reason, for callers that want to choose their own words.
    enum Kind: Equatable { case offline, timeout, signedOut, server, cancelled, other }

    static func kind(of error: Error?) -> Kind {
        guard let error else { return .other }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled: return .cancelled
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
                 NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return .offline
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorCannotConnectToHost, NSURLErrorBadServerResponse,
                 NSURLErrorSecureConnectionFailed:
                return .server
            case NSURLErrorUserAuthenticationRequired: return .signedOut
            default: return .other
            }
        }
        let text = String(describing: error).lowercased() + " " + ns.localizedDescription.lowercased()
        if text.contains("jwt") || text.contains("401") || text.contains("unauthor")
            || text.contains("expired") || text.contains("not signed in") || text.contains("refresh token") {
            return .signedOut
        }
        if text.contains("offline") || text.contains("internet") { return .offline }
        if text.contains("timed out") || text.contains("timeout") { return .timeout }
        if text.contains("500") || text.contains("502") || text.contains("503") || text.contains("server")
            || text.contains("service") || text.contains("unavailable") {
            return .server
        }
        return .other
    }
}
