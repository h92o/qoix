import SwiftUI

/// Hosts the UIKit canvas screen inside the SwiftUI app.
struct CanvasScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CanvasViewController {
        CanvasViewController()
    }

    func updateUIViewController(_ uiViewController: CanvasViewController, context: Context) {}
}
