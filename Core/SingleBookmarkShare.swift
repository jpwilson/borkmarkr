import Foundation

enum SingleBookmarkShare {
    static func text(title: String, url: String, topic: String?, subtopic: String?, tags: [String], note: String?, includeNote: Bool) -> String {
        var lines = ["Check out this link:", title, url]
        let path = SavedContent.breadcrumb(topic: topic, subtopic: subtopic)
        if !path.isEmpty { lines.append("Topic: " + path) }
        if !tags.isEmpty { lines.append("Tags: " + tags.map { "#" + $0 }.joined(separator: " · ")) }
        if includeNote, let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("\nMy note:\n" + note)
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
