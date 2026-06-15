import SwiftUI

/// Oscilloscope-style waveform that traces the time-domain samples across the
/// view with a soft glow.
public final class WaveformPlugin: VisualizationPlugin {

    public let id = "waveform"
    public let displayName = "Waveform"

    public init() {}

    public func render(_ input: VisualizationInput, into context: inout GraphicsContext, size: CGSize) {
        guard input.samples.count > 1 else { return }

        let midY = size.height / 2
        let stepX = size.width / CGFloat(input.samples.count - 1)
        let amplitude = midY * 0.85

        var path = Path()
        for (i, sample) in input.samples.enumerated() {
            let x = CGFloat(i) * stepX
            let y = midY - CGFloat(sample) * amplitude
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Hue drifts slowly with time; brightness tracks the signal level.
        let hue = (input.time * 0.05).truncatingRemainder(dividingBy: 1)
        let color = Color(hue: hue, saturation: 0.8, brightness: 0.6 + 0.4 * Double(input.level))

        var glow = context
        glow.addFilter(.blur(radius: 8))
        glow.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 6)

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }
}
