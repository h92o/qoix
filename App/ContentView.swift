import SwiftUI
import R4VizKit

/// The app's main screen: a full-bleed visualization with an overlaid control
/// bar to switch scenes and pause/resume. Identical on macOS and iOS.
struct ContentView: View {

    @ObservedObject var engine: VisualizationEngine

    var body: some View {
        ZStack(alignment: .bottom) {
            VisualizationView(engine: engine)
                .ignoresSafeArea()

            controlBar
                .padding()
        }
        #if os(macOS)
        .background(Color.black)
        #endif
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Picker("Scene", selection: $engine.selectedSceneID) {
                ForEach(engine.registry.scenes, id: \.id) { scene in
                    Text(scene.name).tag(scene.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Button {
                engine.isRunning.toggle()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.primary)
    }
}
