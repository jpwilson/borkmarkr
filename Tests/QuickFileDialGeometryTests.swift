import XCTest
@testable import borkmarkr

/// The wheel's hit regions follow the slabs it draws (direction B, referenced
/// to a 360 pt dial): a tap on any slab's label files that slab, the hub and
/// the gap around it confirm, and a tap well past the rim does nothing — at
/// every size the app draws it.
final class QuickFileDialGeometryTests: XCTestCase {

    /// The sizes in use: a short share sheet, triage, the Add and share sheets.
    private let diameters: [CGFloat] = [232, 280, 300, 340, 360]

    func testTheGeometryIsBsAt360() {
        let g = QuickFileDialGeometry(diameter: 360)
        XCTAssertEqual(g.scale, 1)
        XCTAssertEqual(g.outer, 168)
        XCTAssertEqual(g.inner, 76)
        XCTAssertEqual(g.hub, 66)
        XCTAssertEqual(g.hubArt, 84)
        XCTAssertEqual(g.slabArt, 36)
        XCTAssertEqual(g.labelRadius(seat: 0), 124.5, accuracy: 0.01)
        XCTAssertEqual(g.labelRadius(seat: 2), 117.5, accuracy: 0.01)
        XCTAssertEqual(g.labelRadius(seat: 1), 121, accuracy: 0.01)
    }

    func testEachSlabsLabelHitsThatSlab() {
        for d in diameters {
            let g = QuickFileDialGeometry(diameter: d)
            for seat in 0..<8 {
                XCTAssertEqual(g.region(at: g.labelPoint(seat: seat)), .seat(seat), "seat \(seat) at \(d) pt")
            }
        }
    }

    func testTheWholeDepthOfASlabHitsIt() {
        for d in diameters {
            let g = QuickFileDialGeometry(diameter: d)
            for seat in 0..<8 {
                let angle = Double(seat) * 45
                for r in [g.inner + 1, (g.inner + g.outer) / 2, g.outer - 1, g.outer + 10 * g.scale] {
                    XCTAssertEqual(g.region(at: g.point(degrees: angle, radius: r)), .seat(seat),
                                   "seat \(seat) at r \(r), \(d) pt")
                }
                // Either side of the slab's middle, inside its 45°.
                for offset in [-20.0, 20.0] {
                    XCTAssertEqual(g.region(at: g.point(degrees: angle + offset, radius: g.labelRadius(seat: seat))),
                                   .seat(seat))
                }
            }
        }
    }

    func testTheCentreAndTheRingAroundTheHubConfirm() {
        for d in diameters {
            let g = QuickFileDialGeometry(diameter: d)
            XCTAssertEqual(g.region(at: g.centre), .hub)
            for angle in stride(from: 0.0, to: 360, by: 30) {
                XCTAssertEqual(g.region(at: g.point(degrees: angle, radius: g.hub)), .hub)
                // The evidence ring sits in the gap and still belongs to the hub.
                XCTAssertEqual(g.region(at: g.point(degrees: angle, radius: g.ringRadius)), .hub)
                XCTAssertEqual(g.region(at: g.point(degrees: angle, radius: g.hubReach + 0.5)), .seat(Int((angle + 22.5) / 45) % 8))
            }
        }
    }

    func testWellPastTheRimIsOutside() {
        let g = QuickFileDialGeometry(diameter: 360)
        XCTAssertEqual(g.rimReach, 184)
        for angle in stride(from: 0.0, to: 360, by: 45) {
            XCTAssertEqual(g.region(at: g.point(degrees: angle, radius: 175)), .seat(Int(angle / 45)))
            XCTAssertEqual(g.region(at: g.point(degrees: angle, radius: 186)), .outside)
        }
    }

    /// The lit slab lifts straight out, 5 pt at 360, so it never rides into the hub.
    func testTheLiftIsOutward() {
        let g = QuickFileDialGeometry(diameter: 360)
        for seat in 0..<8 {
            let lift = g.liftOffset(seat: seat)
            XCTAssertEqual(hypot(lift.width, lift.height), 5, accuracy: 0.001)
            let lifted = CGPoint(x: g.labelPoint(seat: seat).x + lift.width, y: g.labelPoint(seat: seat).y + lift.height)
            XCTAssertGreaterThan(g.distance(lifted), g.distance(g.labelPoint(seat: seat)))
            XCTAssertEqual(g.region(at: lifted), .seat(seat))
        }
    }

    /// Small dials keep the labels readable: the caps never fall under 8.2 pt.
    func testLabelTextHasAFloor() {
        XCTAssertEqual(QuickFileDialGeometry(diameter: 360).textScale, 1)
        XCTAssertEqual(QuickFileDialGeometry(diameter: 232).textScale, 0.86)
        XCTAssertGreaterThanOrEqual(9.5 * QuickFileDialGeometry(diameter: 232).textScale, 8.17)
    }
}
