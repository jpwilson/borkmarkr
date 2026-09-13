import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Per-device cumulative counters merge by max; totals sum across devices.
/// Retrying an upload cannot double-count an open or overwrite bookmark edits.
@Model final class OpenSignal {
    @Attribute(.unique) var id: String
    var bookmarkID: String
    var deviceID: String
    var count: Int
    var lastOpenedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(bookmarkID: String, deviceID: String, count: Int = 0, lastOpenedAt: Date? = nil) {
        self.id = deviceID + ":" + bookmarkID
        self.bookmarkID = bookmarkID; self.deviceID = deviceID
        self.count = count; self.lastOpenedAt = lastOpenedAt
        self.createdAt = .now; self.updatedAt = .now
    }
    @MainActor static var localDevice: String {
        #if canImport(UIKit)
        if let id = UIDevice.current.identifierForVendor?.uuidString { return id }
        #endif
        if let id = UserDefaults.standard.string(forKey: "openSignalDevice") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "openSignalDevice")
        return id
    }
    @MainActor static func seedLegacy(_ bookmark: Bookmark, context: ModelContext) throws {
        guard !bookmark.openSignalsMigrated else { return }
        if bookmark.openCount > 0 {
            let id = localDevice + ":" + bookmark.id
            let existing = try context.fetch(FetchDescriptor<OpenSignal>(predicate: #Predicate { $0.id == id })).first
            if let existing {
                existing.count = max(existing.count, bookmark.openCount)
            } else {
                context.insert(OpenSignal(bookmarkID: bookmark.id, deviceID: localDevice,
                    count: bookmark.openCount, lastOpenedAt: bookmark.lastOpenedAt))
            }
        }
        bookmark.openSignalsMigrated = true
    }
    @MainActor static func record(_ bookmark: Bookmark) throws {
        guard let context = bookmark.modelContext else { return }
        try seedLegacy(bookmark, context: context)
        let id = localDevice + ":" + bookmark.id
        let signal = try context.fetch(FetchDescriptor<OpenSignal>(predicate: #Predicate { $0.id == id })).first
            ?? OpenSignal(bookmarkID: bookmark.id, deviceID: localDevice)
        if signal.modelContext == nil { context.insert(signal) }
        signal.count += 1; signal.lastOpenedAt = .now; signal.updatedAt = .now
    }
}
