import Foundation

/// The document: a canvas size, a background color, and the strokes drawn so far.
///
/// The strokes are the source of truth. The pixels on screen are only a cache of them, which is what makes
/// undo/redo, re-rendering at another size, and saving a drawing for later editing possible.
struct Drawing: Equatable, Codable {
    let canvas: CanvasSpec
    var background: RGBAColor
    private(set) var strokes: [Stroke] = []

    init(canvas: CanvasSpec, background: RGBAColor = .white) {
        self.canvas = canvas
        self.background = background
    }

    var isEmpty: Bool { strokes.isEmpty }

    mutating func append(_ stroke: Stroke) {
        strokes.append(stroke)
    }

    @discardableResult
    mutating func removeLastStroke() -> Stroke? {
        strokes.popLast()
    }

    @discardableResult
    mutating func removeAllStrokes() -> [Stroke] {
        let removed = strokes
        strokes.removeAll()
        return removed
    }

    mutating func replaceStrokes(with newStrokes: [Stroke]) {
        strokes = newStrokes
    }
}
