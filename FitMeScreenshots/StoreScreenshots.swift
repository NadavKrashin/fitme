import XCTest

/// Captures the App Store screenshots: launches the app in screenshot mode (demo closet, a packed Lisbon trip, steady
/// weather) and saves each screen as a PNG in `SCREENSHOT_DIR` (set by `make screenshots`).
final class StoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-FitMeScreenshots"]
        app.launch()
    }

    @MainActor
    func testStoreScreenshots() {
        // 1. Today: an outfit for the weather.
        XCTAssert(app.staticTexts["Suggestions"].waitForExistence(timeout: 30))
        app.swipeUp(velocity: .slow)
        save("1-today")

        // 2. The outfit's pieces, with swaps.
        app.buttons["See pieces or swap one"].firstMatch.tap()
        XCTAssert(app.staticTexts["The outfit"].waitForExistence(timeout: 10))
        save("2-outfit")
        app.buttons["Done"].tap()

        // 3. The packed bag for a trip.
        app.tabBars.buttons["Trips"].tap()
        let trip = app.staticTexts["Lisbon"].firstMatch
        XCTAssert(trip.waitForExistence(timeout: 30))
        trip.tap()
        sleep(2)
        save("3-trip")

        // 4. The closet.
        app.tabBars.buttons["Closet"].tap()
        sleep(2)
        save("4-closet")

        // 5. Insights, once every piece has been tried with everything else.
        app.staticTexts["Insights"].firstMatch.tap()
        XCTAssert(app.staticTexts["Best next buy"].waitForExistence(timeout: 90))
        sleep(1)
        save("5-insights")
    }

    private func save(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        XCTAssertNoThrow(try png.write(to: url))
    }
}
