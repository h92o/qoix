import Combine
import Foundation

/// The pen currently in use: which brush (with any tweaks made in the brush sheet) and which ink.
/// Remembered between launches.
final class PenSettings: ObservableObject {
    private static let presetKey = "penSettings.preset"
    private static let colorKey = "penSettings.colorIndex"

    private let defaults: UserDefaults?

    /// The brush being used. The brush sheet edits it freely, so it can differ from every built-in preset.
    @Published var preset: BrushPreset {
        didSet { save() }
    }

    /// Index into `Palette.colors`.
    @Published var colorIndex: Int {
        didSet { save() }
    }

    /// `defaults` is where the choice is remembered; pass nil to keep it in memory only (as the tests do).
    init(defaults: UserDefaults? = UserDefaults.standard, preset fallback: BrushPreset = AppConfig.defaultPreset) {
        self.defaults = defaults
        var loadedPreset = fallback
        var loadedColor = 0
        if let defaults {
            if let data = defaults.data(forKey: PenSettings.presetKey),
               let saved = try? JSONDecoder().decode(BrushPreset.self, from: data) {
                loadedPreset = saved
            }
            loadedColor = defaults.integer(forKey: PenSettings.colorKey)
        }
        self.preset = loadedPreset
        self.colorIndex = Palette.wrap(loadedColor)
    }

    var paletteColor: PaletteColor {
        Palette.colors[Palette.wrap(colorIndex)]
    }

    /// Moves to the next ink (wrapping around) and returns it.
    @discardableResult
    func cycleColor() -> PaletteColor {
        colorIndex = Palette.wrap(colorIndex + 1)
        return paletteColor
    }

    /// The brush to paint the next stroke with, for a canvas with `pixelsPerPoint` canvas pixels per screen point.
    func brush(pixelsPerPoint: Double) -> Brush {
        preset.brush(color: paletteColor.color, pixelsPerPoint: pixelsPerPoint)
    }

    private func save() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(preset) {
            defaults.set(data, forKey: PenSettings.presetKey)
        }
        defaults.set(colorIndex, forKey: PenSettings.colorKey)
    }
}
