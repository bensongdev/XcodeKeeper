import XCTest
@testable import XcodeKeeper

final class ByteFormatTests: XCTestCase {
    func testMenuBarLabelRoundsDownToWholeGB() {
        XCTAssertEqual(ByteFormat.menuBarLabel(16_200_000_000), "16G")
        XCTAssertEqual(ByteFormat.menuBarLabel(16_999_999_999), "16G")
        XCTAssertEqual(ByteFormat.menuBarLabel(0), "0G")
    }

    func testMenuBarLabelWithoutValue() {
        XCTAssertEqual(ByteFormat.menuBarLabel(nil), "—")
        XCTAssertEqual(ByteFormat.menuBarLabel(-1), "—")
    }

    func testGigabytesShowsOneDecimalRoundedDown() {
        XCTAssertEqual(ByteFormat.gigabytes(16_200_000_000), "16.2GB")
        XCTAssertEqual(ByteFormat.gigabytes(16_290_000_000), "16.2GB")
        XCTAssertEqual(ByteFormat.gigabytes(950_000_000), "0.9GB")
        XCTAssertEqual(ByteFormat.gigabytes(nil), "—")
    }
}
