import XCTest
@testable import QoixDraw

final class SmokeTests: XCTestCase {
    func testTestBundleLoadsInsideTheApp() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
