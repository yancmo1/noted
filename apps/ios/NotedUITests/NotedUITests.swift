import XCTest

@MainActor
final class NotedUITests: XCTestCase {
    func testLaunchShowsNotedEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Meetings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Record"].exists)
    }
}
