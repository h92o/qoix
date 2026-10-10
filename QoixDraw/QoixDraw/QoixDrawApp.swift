import SwiftUI

@main
struct QoixDrawApp: App {
    /// The unit tests run inside the app process; keep the app itself inert while they do.
    private static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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
