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

    func testTheCanvasFillsTheWholeScreen() throws {
        let (app, canvas) = launchApp()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "the drawing canvas should be on screen")
        let window = app.windows.firstMatch
        XCTAssertEqual(canvas.frame.width, window.frame.width, accuracy: 1)
        XCTAssertEqual(canvas.frame.height, window.frame.height, accuracy: 1)
        snap("0-blank-canvas")
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
        let saved = app.staticTexts["Saved to Photos"]
        XCTAssertTrue(saved.waitForExistence(timeout: 30), "saving should confirm with a message")
        snap("2-saved")

        app.typeKey("z", modifierFlags: .command)
        snap("3-after-undo")
    }
}
