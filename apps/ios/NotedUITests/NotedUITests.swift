import XCTest

@MainActor
final class NotedUITests: XCTestCase {
    func testLaunchShowsNotedEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Meetings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Record"].exists)
    }

    func testRealRecordingUploadsToLocalMacServer() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            if alert.buttons["OK"].exists {
                alert.buttons["OK"].tap()
                return true
            }
            return false
        }

        app.launch()

        let recordTab = app.tabBars.buttons["Record"]
        XCTAssertTrue(recordTab.waitForExistence(timeout: 10))
        recordTab.tap()

        let uniqueTitle = "iPhone local tracer " + String(UUID().uuidString.prefix(8))
        let titleField = app.textFields["recording-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(uniqueTitle)

        let startButton = app.buttons["record-toggle"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()
        app.tap()

        let stopButton = app.buttons["record-stop-save"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4)
        stopButton.tap()
        XCTAssertTrue(app.staticTexts["Recording saved on this iPhone"].waitForExistence(timeout: 15))

        let meetingsTab = app.tabBars.buttons["Meetings"]
        XCTAssertTrue(meetingsTab.waitForExistence(timeout: 10))
        meetingsTab.tap()

        let recordedTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", uniqueTitle)
        ).firstMatch
        XCTAssertTrue(recordedTitle.waitForExistence(timeout: 15))
        recordedTitle.tap()

        let sendButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'send-recording-'")
        ).firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 15))
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        // The upload response updates the local record before the longer
        // Whisper/Qwen processing poll finishes.
        XCTAssertTrue(app.staticTexts["Saved on the server"].waitForExistence(timeout: 45))
    }

    func testDoctorRecordingShowsLocalDiagnosticsAndCalendarCandidate() {
        let app = XCUIApplication()
        app.launch()

        let meetingsTab = app.tabBars.buttons["Meetings"]
        XCTAssertTrue(meetingsTab.waitForExistence(timeout: 10))
        meetingsTab.tap()
        let refreshButton = app.buttons["Refresh meetings"]
        if refreshButton.waitForExistence(timeout: 10) {
            refreshButton.tap()
        }

        let doctorRecording = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Doctor visit local tracer")
        ).firstMatch
        var foundDoctorRecording = false
        for _ in 0..<6 {
            if doctorRecording.exists {
                foundDoctorRecording = true
                break
            }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(foundDoctorRecording)
        doctorRecording.tap()

        XCTAssertTrue(app.staticTexts["Processing details"].waitForExistence(timeout: 20))
        let candidate = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Doctor follow-up")
        ).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "November 10")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Needs confirmation"].exists)

        let reviewButton = app.buttons["Review and add to Calendar"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 10))
        reviewButton.tap()
        XCTAssertTrue(app.navigationBars["Add to Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["calendar-event-title"].exists)
        let calendarPicker = app.descendants(matching: .any)["calendar-picker"]
        let noWritableCalendars = app.staticTexts["No writable calendars are available on this iPhone."]
        XCTAssertTrue(
            calendarPicker.waitForExistence(timeout: 10) ||
            noWritableCalendars.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["add-calendar-event"].exists)
        app.buttons["Cancel"].tap()
    }
}
