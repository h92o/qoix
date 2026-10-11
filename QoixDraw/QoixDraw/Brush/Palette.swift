import Foundation

struct PaletteColor: Equatable {
    let name: String
    let color: RGBAColor
}

/// The inks that Volume Up steps through, in order, wrapping around.
enum Palette {
    static let colors: [PaletteColor] = [
        PaletteColor(name: "Ink", color: RGBAColor(red: 0.08, green: 0.07, blue: 0.06)),
        PaletteColor(name: "Vermilion", color: RGBAColor(red: 0.85, green: 0.22, blue: 0.16)),
        PaletteColor(name: "Indigo", color: RGBAColor(red: 0.12, green: 0.18, blue: 0.48)),
        PaletteColor(name: "Sepia", color: RGBAColor(red: 0.44, green: 0.26, blue: 0.08)),
        PaletteColor(name: "Forest", color: RGBAColor(red: 0.10, green: 0.36, blue: 0.22)),
        PaletteColor(name: "Gold", color: RGBAColor(red: 0.79, green: 0.64, blue: 0.15)),
        PaletteColor(name: "White", color: .white),
    ]

    /// Maps any integer onto a valid index, so stepping forward past the end (or back past the start) wraps around.
    static func wrap(_ index: Int) -> Int {
        let count = colors.count
        return ((index % count) + count) % count
    }
}
