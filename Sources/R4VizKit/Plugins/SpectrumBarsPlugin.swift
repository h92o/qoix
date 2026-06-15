import SwiftUI

/// Classic spectrum-analyzer bars rising from the bottom of the view, each bar
/// colored across the spectrum from low (red) to high (violet).
public final class SpectrumBarsPlugin: VisualizationPlugin {

    public let id = "spectrum-bars"
    public let displayName = "Spectrum Bars"

    public init() {}

    public func render(_ input: VisualizationInput, into context: inout GraphicsContext, size: CGSize) {
        let bins = input.spectrum
        guard !bins.isEmpty else { return }

        let gap = size.width / CGFloat(bins.count) * 0.2
        let barWidth = (size.width - gap * CGFloat(bins.count + 1)) / CGFloat(bins.count)
        guard barWidth > 0 else { return }

        for (i, magnitude) in bins.enumerated() {
            let height = max(2, CGFloat(magnitude) * size.height)
            let x = gap + CGFloat(i) * (barWidth + gap)
            let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)

            let hue = Double(i) / Double(bins.count) * 0.8 // red → violet
            let color = Color(hue: hue, saturation: 0.85, brightness: 0.95)

            let bar = Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 4))
            context.fill(bar, with: .linearGradient(
                Gradient(colors: [color, color.opacity(0.35)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))
        }
    }
}
