import SwiftUI

/// The brush sheet (shake the phone, then Brush & Color): pick a pen, tweak its shape and feel, choose an ink.
/// Everything is previewed live with the real drawing engine, and remembered.
struct BrushSettingsView: View {
    @ObservedObject var settings: PenSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrushPreviewView(preset: settings.preset, color: settings.paletteColor.color)
                        .frame(height: 130)
                        .listRowInsets(EdgeInsets())
                }

                Section("Pen") {
                    Picker("Style", selection: styleSelection) {
                        ForEach(BrushPreset.all) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    Picker("Tip", selection: $settings.preset.shape) {
                        Text("Flat").tag(Nib.Shape.rectangle)
                        Text("Oval").tag(Nib.Shape.ellipse)
                    }
                    .pickerStyle(.segmented)
                    Button("Reset this pen") {
                        resetToBuiltIn()
                    }
                }

                Section("Shape") {
                    SliderRow(title: "Size", value: $settings.preset.lengthPoints, range: 2...40) {
                        String(format: "%.0f pt", $0)
                    }
                    SliderRow(title: "Edge thickness", value: $settings.preset.thicknessPoints, range: 0.5...20) {
                        String(format: "%.1f pt", $0)
                    }
                    SliderRow(title: "Angle", value: $settings.preset.angleDegrees, range: 0...180) {
                        String(format: "%.0f°", $0)
                    }
                }

                Section("Feel") {
                    SliderRow(title: "Smoothing", value: $settings.preset.smoothing, range: 0...1) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                    SliderRow(title: "Speed sensitivity", value: $settings.preset.speedResponse, range: 0...1) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                    SliderRow(title: "Finger pressure", value: $settings.preset.contactResponse, range: 0...1) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                }

                Section("Ink (Volume Up changes it too)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(Array(Palette.colors.enumerated()), id: \.offset) { index, ink in
                            Button {
                                settings.colorIndex = index
                            } label: {
                                Circle()
                                    .fill(Color(uiColor: UIColor(cgColor: ink.color.cgColor)))
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.accentColor, lineWidth: 3)
                                            .padding(-4)
                                            .opacity(index == settings.colorIndex ? 1 : 0)
                                    )
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(ink.name)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Brush & Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// The Style picker shows the built-in pen the current brush started from, and choosing one loads it.
    private var styleSelection: Binding<String> {
        Binding(
            get: { settings.preset.name },
            set: { name in
                if let builtIn = BrushPreset.all.first(where: { $0.name == name }) {
                    settings.preset = builtIn
                }
            }
        )
    }

    private func resetToBuiltIn() {
        if let builtIn = BrushPreset.all.first(where: { $0.name == settings.preset.name }) {
            settings.preset = builtIn
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(label(value))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
