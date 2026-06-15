import SwiftUI

/// A radial burst of particles orbiting the center, their radius pulsing with the
/// signal level. Demonstrates a fully procedural visualizer that ignores the raw
/// waveform and reacts only to ``VisualizationInput/level``.
public final class ParticleFieldPlugin: VisualizationPlugin {

    public let id = "particle-field"
    public let displayName = "Particle Field"

    private let particleCount = 140

    public init() {}

    public func render(_ input: VisualizationInput, into context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) / 2
        let pulse = 0.35 + 0.65 * CGFloat(input.level)
        let t = input.time

        for i in 0..<particleCount {
            let fraction = Double(i) / Double(particleCount)

            // Each particle rides a different ring and angular speed.
            let ringSpeed = 0.4 + fraction * 1.6
            let angle = fraction * .pi * 2 * 6 + t * ringSpeed
            let radius = maxRadius * pulse * (0.2 + 0.8 * fraction)

            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            let dotSize = 2 + 4 * CGFloat(input.level) * CGFloat(1 - fraction)

            let hue = (fraction + t * 0.03).truncatingRemainder(dividingBy: 1)
            let color = Color(hue: hue, saturation: 0.7, brightness: 1)

            let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85)))
        }
    }
}
