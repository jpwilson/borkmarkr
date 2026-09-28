import XCTest
@testable import borkmarkr

/// A newer app on a server not yet migrated for it keeps backing up borks.
final class SyncFallbackTests: XCTestCase {
    func testRecognisesAServerBehindTheApp() {
        // PostgREST and Postgres messages, as `Supabase.send` surfaces them.
        let behind = [
            "Could not find the table 'public.custom_topics' in the schema cache",
            "Could not find the 'enrichment_version' column of 'bookmarks' in the schema cache",
            "relation \"public.bookmark_opens\" does not exist",
            "column bookmarks.filing_source does not exist",
        ]
        for message in behind {
            XCTAssertTrue(Supabase.isSchemaBehind(Supabase.Failure.http(400, message)), message)
        }

        // Everything else still fails the sync.
        let real = [
            "JWT expired",
            "new row violates row-level security policy for table \"bookmarks\"",
            "duplicate key value violates unique constraint",
            "",
        ]
        for message in real {
            XCTAssertFalse(Supabase.isSchemaBehind(Supabase.Failure.http(401, message)), message)
        }
        XCTAssertFalse(Supabase.isSchemaBehind(URLError(.notConnectedToInternet)))
    }
}
