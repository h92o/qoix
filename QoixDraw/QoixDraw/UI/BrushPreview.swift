import SwiftUI
import UIKit

/// Draws a small specimen of a brush with the real engine: a zigzag, which shows thick and thin strokes as the
/// direction changes, and a wave.
enum BrushPreviewRenderer {
    static let canvas = CanvasSpec(width: 800, height: 280)
    /// Canvas pixels per screen point the preview pretends to have (about an iPhone's), so sizes look right.
    static let pixelsPerPoint = 2.35

    static func image(for preset: BrushPreset, color: RGBAColor) -> UIImage? {
        guard let bitmap = BitmapCanvas(spec: canvas, background: .white) else { return nil }
        let brush = preset.brush(color: color, pixelsPerPoint: pixelsPerPoint)
        bitmap.paint(Stroke(brush: brush, points: samples(along: zigzag, speed: 700)))
        bitmap.paint(Stroke(brush: brush, points: samples(along: wave, speed: 900)))
        return bitmap.makeImage().map { UIImage(cgImage: $0) }
    }

    private static let zigzag: [CGPoint] = [
        CGPoint(x: 40, y: 235), CGPoint(x: 105, y: 45), CGPoint(x: 170, y: 235),
        CGPoint(x: 235, y: 45), CGPoint(x: 300, y: 235),
    ]

    private static var wave: [CGPoint] {
        stride(from: 380.0, through: 760.0, by: 10.0).map { x in
            CGPoint(x: x, y: 140 + 75 * sin((x - 380) / 380 * 2 * Double.pi * 1.75))
        }
    }

    /// Evenly spaced finger samples along a polyline, as if drawn at a steady `speed` (canvas pixels per second).
    private static func samples(along points: [CGPoint], speed: Double, spacing: Double = 4) -> [StrokePoint] {
        guard var previous = points.first else { return [] }
        var result = [StrokePoint(previous, time: 0)]
        var time = 0.0
        for next in points.dropFirst() {
            let dx = Double(next.x - previous.x)
            let dy = Double(next.y - previous.y)
            let length = (dx * dx + dy * dy).squareRoot()
            let count = max(1, Int((length / spacing).rounded(.up)))
            for step in 1...count {
                let t = Double(step) / Double(count)
                time += length / Double(count) / speed
                result.append(StrokePoint(x: Double(previous.x) + dx * t, y: Double(previous.y) + dy * t, time: time))
            }
            previous = next
        }
        return result
    }
}

struct BrushPreviewView: UIViewRepresentable {
    let preset: BrushPreset
    let color: RGBAColor

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .white
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = BrushPreviewRenderer.image(for: preset, color: color)
    }
}
