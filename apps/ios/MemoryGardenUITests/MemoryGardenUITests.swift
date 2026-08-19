import XCTest

@MainActor
final class MemoryGardenUITests: XCTestCase {
    func testLaunchShowsMemoryGardenEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Memory Garden"].waitForExistence(timeout: 5))
    }
}
