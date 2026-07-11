import XCTest
@testable import OpenClinic

final class AnatomicalRegionTests: XCTestCase {
    func testKnownRegions() {
        XCTAssertEqual(AnatomicalRegion.displayName(for: "scalp"), "Scalp")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "facial_mesh_nose"), "Nose")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "left_cheek"), "Left Cheek")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "right_cheek"), "Right Cheek")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "forehead"), "Forehead")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "left_shoulder"), "Left Shoulder")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "skull"), "Skull")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "neck_muscles"), "Neck Muscles")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "chest_muscles"), "Pectoral Muscles")
    }

    func testUnknownFallback() {
        XCTAssertEqual(AnatomicalRegion.displayName(for: "unknown_random_region"), "unknown_random_region")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "LIVER"), "LIVER")
    }

    func testEmptyAndWhitespace() {
        XCTAssertEqual(AnatomicalRegion.displayName(for: ""), "")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "   "), "   ")
    }

    func testCaseSensitivity() {
        XCTAssertEqual(AnatomicalRegion.displayName(for: "Scalp"), "Scalp")
        XCTAssertEqual(AnatomicalRegion.displayName(for: "SCALP"), "SCALP")
    }
}
