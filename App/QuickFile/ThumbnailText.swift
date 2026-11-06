import Foundation
import UIKit
import Vision

/// The words printed on a save's thumbnail, read for filing.
///
/// A reel shared from Instagram often arrives with nothing to read: no
/// caption, and a title made from its URL. Its cover usually says what it is
/// anyway, in big burned-in letters ("3 MOVES FOR KNEE PAIN"). Vision reads
/// them here, on the device, and `FilingSuggest.cleanOCR` throws away the app
/// furniture (handles, view counts, "Follow", "Original audio"). What is left
/// is one more, deliberately weak, signal for the dial: on-screen text counts
/// half and is capped below "Sorted for you", so it can lift a topic up the
/// ring but never decide one alone.
///
/// - Never in the Share Extension: no Vision and no full-size decode there.
/// - Never synced, and no schema change: cached on this device only, by
///   `stableID`, in Application Support.
/// - `.fast` in the Library's background pass (`PreviewFetcher`, at most four
///   a pass) and in the Add sheet; `.accurate` for the next cards in triage.
/// - The bitmap comes through `ImagePipeline`, so a cover the Library already
///   downloaded is read from its disk cache, decoded by ImageIO at no more
///   than 1024 px on the long side.
enum ThumbnailText {

    /// What one read found. `text` nil means it was read and said nothing
    /// worth keeping, which is remembered so it isn't read again.
    struct Entry: Codable, Sendable {
        var text: String?
        var accurate: Bool
        var at: Date
    }

    private static let maxPixels: CGFloat = 1024
    /// Enough for a heavy library's unsorted saves; the oldest go first.
    private static let limit = 3000

    // MARK: Cache

    @MainActor private static var entries: [String: Entry]?
    @MainActor private static var reading: Set<String> = []
    @MainActor private static var pendingWrite: Task<Void, Never>?

    /// The cleaned text for a save, if its thumbnail said anything.
    @MainActor static func cached(_ stableID: String) -> String? {
        table[stableID]?.text
    }

    /// Whether the thumbnail has been read at least as carefully as asked.
    @MainActor static func hasRead(_ stableID: String, accurate: Bool) -> Bool {
        guard let entry = table[stableID] else { return false }
        return entry.accurate || !accurate
    }

    @MainActor static func store(_ text: String?, for stableID: String, accurate: Bool) {
        var all = table
        all[stableID] = Entry(text: text, accurate: accurate, at: .now)
        if all.count > limit {
            let oldest = all.sorted { $0.value.at < $1.value.at }.prefix(all.count - limit).map(\.key)
            for key in oldest { all.removeValue(forKey: key) }
        }
        entries = all
        scheduleWrite()
    }

    /// Reads the thumbnail unless it has been read carefully enough already,
    /// and remembers what it said. A careful read that finds nothing never
    /// erases what a quick one found.
    @MainActor static func read(_ stableID: String, imageURL: URL, accurate: Bool) async -> String? {
        if hasRead(stableID, accurate: accurate) { return cached(stableID) }
        guard !reading.contains(stableID) else { return nil }
        reading.insert(stableID)
        defer { reading.remove(stableID) }
        let found = await recognize(imageURL, accurate: accurate) ?? cached(stableID)
        store(found, for: stableID, accurate: accurate)
        return found
    }

    @MainActor private static var table: [String: Entry] {
        if let entries { return entries }
        let loaded = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = loaded
        return loaded
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("quickfile", isDirectory: true)
            .appendingPathComponent("thumbnail-text.json")
    }

    /// One write a second at most, off the main actor.
    @MainActor private static func scheduleWrite() {
        pendingWrite?.cancel()
        pendingWrite = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let snapshot = entries, let url = fileURL else { return }
            Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: Reading

    /// The thumbnail's text, cleaned, or nil when it says nothing useful (or
    /// can't be fetched). Never cached here; `read` does that.
    static func recognize(_ imageURL: URL, accurate: Bool) async -> String? {
        let box = CGSize(width: maxPixels, height: maxPixels)
        guard let bitmap = await ImagePipeline.shared.image(for: imageURL, box: box, fill: false) else { return nil }
        let lines = await Task.detached(priority: .utility) {
            Self.lines(in: bitmap, accurate: accurate)
        }.value
        return FilingSuggest.cleanOCR(lines)
    }

    /// Recognised lines, top of the picture first, keeping only what Vision
    /// is reasonably sure of.
    private static func lines(in bitmap: ImagePipeline.Entry, accurate: Bool) -> [String] {
        guard let image = bitmap.image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = accurate
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { observation in
                guard let best = observation.topCandidates(1).first, best.confidence >= 0.5 else { return nil }
                return best.string
            }
    }
}
