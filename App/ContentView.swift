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
        HStack(spacing: 14) {
            labeledPicker("Scene", selection: $engine.selectedSceneID,
                          items: engine.registry.scenes.map { Choice($0.id, $0.name) })

            labeledPicker("Overlay", selection: $engine.selectedOverlayID,
                          items: engine.overlays.overlays.map { Choice($0.id, $0.name) })

            labeledPicker("Fade", selection: $engine.selectedFadeID,
                          items: engine.fades.fades.map { Choice($0.id, $0.name) })

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

    private struct Choice: Identifiable {
        let id: String
        let name: String
        init(_ id: String, _ name: String) { self.id = id; self.name = name }
    }

    private func labeledPicker(_ title: String, selection: Binding<String>,
                               items: [Choice]) -> some View {
        Picker(title, selection: selection) {
            ForEach(items) { item in
                Text(item.name).tag(item.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}
