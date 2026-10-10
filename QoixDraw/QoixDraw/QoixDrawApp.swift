import SwiftUI

@main
struct QoixDrawApp: App {
    /// The unit tests run inside the app process; keep the app itself inert while they do. (UI tests launch the
    /// app as a separate process and set QOIX_UI_TESTING, so they get the real thing.)
    private static let isRunningUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil && environment["QOIX_UI_TESTING"] == nil
    }()

    var body: some Scene {
        WindowGroup {
            if Self.isRunningUnitTests {
                Color.black.ignoresSafeArea()
            } else {
                CanvasScreen()
                    .ignoresSafeArea()
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
                    .defersSystemGestures(on: .all)
            }
        }
    }
}
