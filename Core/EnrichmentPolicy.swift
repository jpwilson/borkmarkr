import Foundation

enum EnrichmentPolicy {
    static let version = 2
    static func due(version: Int?, attempts: Int?, lastAttempt: Date?, now: Date = .now) -> Bool {
        guard (version ?? 0) < Self.version, (attempts ?? 0) < 3 else { return false }
        return lastAttempt.map { now.timeIntervalSince($0) >= 3600 } ?? true
    }
    /// Nil is a legacy record: we cannot prove who chose its filing.
    static func mayFile(source: String?) -> Bool { source == "automatic" }
}
