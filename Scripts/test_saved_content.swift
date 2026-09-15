import Foundation
@main enum SavedContentTests {
    struct Fixture: Decodable { let raw: String; let body: String?; let platform: String; let want: String }
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Scripts/fixtures/saved_content.json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
        for f in fixtures {
            precondition(SavedContent.title(f.raw, body: f.body, platform: f.platform) == f.want, f.raw)
        }
        precondition(SavedContent.breadcrumb(topic: "Health", subtopic: "Green light") == "Health › Green light")
        precondition(SavedContent.breadcrumb(topic: nil, subtopic: nil).isEmpty)
        precondition(SavedContent.excerpt("  a useful\ncaption  ") == "a useful caption")
        precondition(SavedContent.excerpt("Sign in to continue") == nil)
        print("Saved content: shared fixtures and breadcrumbs passed.")
    }
}
