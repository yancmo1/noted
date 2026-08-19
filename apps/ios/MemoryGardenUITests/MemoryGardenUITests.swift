import XCTest

@MainActor
final class MemoryGardenUITests: XCTestCase {
    func testLaunchShowsMemoryGardenEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Meetings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Record"].exists)
    }
}
