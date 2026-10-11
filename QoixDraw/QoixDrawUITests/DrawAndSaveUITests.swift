import XCTest

/// Drives the real app in the Simulator: draws a little picture with touches, saves it with ⌘S (the Simulator
/// has no volume buttons) and checks the app answers. Screenshots are attached to the test results and copied to
/// /tmp/qoixdraw-shots so CI can publish them.
final class DrawAndSaveUITests: XCTestCase {
    private let shotsFolder = "/tmp/qoixdraw-shots"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: shotsFolder, withIntermediateDirectories: true)
    }

    private func launchApp() -> (app: XCUIApplication, canvas: XCUIElement) {
        let app = XCUIApplication()
        app.launchEnvironment["QOIX_UI_TESTING"] = "1"
        app.launch()
        return (app, app.descendants(matching: .any)["canvas"])
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "\(shotsFolder)/\(name).png"))
    }

    private func line(on canvas: XCUIElement, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: a.0, dy: a.1))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: b.0, dy: b.1))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// Waits for the "Saved ..." message. If iOS asks for permission to add to Photos (the pre-approval in CI
    /// didn't take on this simulator), it answers Allow, so the test measures the app and not the setup.
    ///
    /// The toast only stays up for a couple of seconds and a slow simulator can miss it, so the canvas's
    /// accessibility value (which stays until you draw again) is checked too.
    private func waitForSaveConfirmation(in app: XCUIApplication, canvas: XCUIElement, timeout: TimeInterval = 90) -> String? {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved'")).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = canvas.value as? String, status.hasPrefix("Saved") {
                return status
            }
            if saved.exists {
                return saved.label
            }
            let alert = springboard.alerts.firstMatch
            if alert.exists {
                let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow' AND NOT label CONTAINS[c] \"Don\"")).firstMatch
                if allow.exists {
                    allow.tap()
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// One line describing what is on screen, for failure messages.
    private func describeScreen(of app: XCUIApplication) -> String {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label)
        let alerts = springboard.alerts.allElementsBoundByIndex.map { alert in
            "\(alert.label) \(alert.buttons.allElementsBoundByIndex.map(\.label))"
        }
        return "app state \(app.state.rawValue); texts \(texts); system alerts \(alerts)"
    }

    func testTheCanvasFillsTheWholeScreen() throws {
        let (app, canvas) = launchApp()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "the drawing canvas should be on screen")
        let window = app.windows.firstMatch
        XCTAssertEqual(canvas.frame.width, window.frame.width, accuracy: 1)
        XCTAssertEqual(canvas.frame.height, window.frame.height, accuracy: 1)
        snap("0-blank-canvas")
    }

    /// Lines radiating from one point in twelve directions. With the default flat pen the thickness changes with
    /// the direction (hairline along the pen's edge, broad across it), which the screenshot makes easy to see.
    func testANibRoseShowsThickAndThinByDirection() throws {
        let (_, canvas) = launchApp()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "the drawing canvas should be on screen")

        let size = canvas.frame.size
        let radius: CGFloat = 150 // points
        let center = CGVector(dx: 0.5, dy: 0.45)
        for index in 0..<12 {
            let angle = CGFloat(index) / 12 * 2 * .pi
            let end = (0.5 + radius * cos(angle) / size.width, 0.45 + radius * sin(angle) / size.height)
            line(on: canvas, (center.dx, center.dy), end)
        }
        snap("5-nib-rose")
    }

    func testTheBrushSheetOpensAndCloses() throws {
        let (app, canvas) = launchApp()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "the drawing canvas should be on screen")

        // The screen only starts answering key commands once it is on screen and has become first responder,
        // which can lag behind the canvas appearing, so a key press that comes too early is simply lost. Press
        // again until the sheet shows (pressing it again once it is open does nothing).
        let title = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Brush & Color'")).firstMatch
        var opened = false
        for _ in 0..<5 where !opened {
            app.typeKey("b", modifierFlags: .command)
            opened = title.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(opened, "⌘B should open the Brush & Color sheet; \(describeScreen(of: app)); \(app.debugDescription.prefix(3000))")
        snap("4-brush-sheet")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the sheet has a Done button; \(describeScreen(of: app))")
        done.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: done)
        wait(for: [gone], timeout: 20)
    }

    func testDrawAPictureThenSaveIt() throws {
        let (app, canvas) = launchApp()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "the drawing canvas should be on screen")

        // A house: walls, roof, door.
        line(on: canvas, (0.30, 0.50), (0.70, 0.50))
        line(on: canvas, (0.70, 0.50), (0.70, 0.74))
        line(on: canvas, (0.70, 0.74), (0.30, 0.74))
        line(on: canvas, (0.30, 0.74), (0.30, 0.50))
        line(on: canvas, (0.24, 0.50), (0.50, 0.36))
        line(on: canvas, (0.50, 0.36), (0.76, 0.50))
        line(on: canvas, (0.44, 0.74), (0.44, 0.63))
        line(on: canvas, (0.44, 0.63), (0.56, 0.63))
        line(on: canvas, (0.56, 0.63), (0.56, 0.74))
        // A sun, as a polygon, and a doorknob dot.
        let center = (x: CGFloat(0.80), y: CGFloat(0.20))
        let points: [(CGFloat, CGFloat)] = (0...10).map { i in
            let angle = CGFloat(i) / 10 * 2 * .pi
            return (center.x + 0.08 * cos(angle), center.y + 0.04 * sin(angle))
        }
        for pair in zip(points, points.dropFirst()) {
            line(on: canvas, pair.0, pair.1)
        }
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.69)).tap()
        snap("1-drawn")

        app.typeKey("s", modifierFlags: .command)
        let confirmation = waitForSaveConfirmation(in: app, canvas: canvas)
        XCTAssertNotNil(confirmation, "saving should confirm with a message; canvas value \(String(describing: canvas.value)); \(describeScreen(of: app))")
        snap("2-saved")

        app.typeKey("z", modifierFlags: .command)
        snap("3-after-undo")
    }
}
