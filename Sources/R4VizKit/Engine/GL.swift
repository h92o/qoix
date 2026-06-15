import SwiftUI
import simd

/// A tiny immediate-mode drawing helper that mirrors the subset of R4's `gl`
/// module the ported scenes use: a model-view matrix stack, perspective
/// projection, color state, and primitive draws (quad / cube / line).
///
/// Scenes call into this much like the original scripts called `gl.gltranslate`,
/// `gl.glrotate`, `gl.glscale`, `gl.glcolor`, etc., so the ported render code
/// reads close to the originals. Everything projects on the CPU and draws into a
/// SwiftUI `GraphicsContext`, so it is identical on macOS and iOS.
public final class GL {
    private var context: GraphicsContext
    public let size: CGSize

    private let projection: Matrix4
    private var stack: [Matrix4]
    private var rgba: (r: Double, g: Double, b: Double, a: Double) = (1, 1, 1, 1)

    public init(context: GraphicsContext, size: CGSize) {
        self.context = context
        self.size = size
        let aspect = Float(size.width / max(size.height, 1))
        self.projection = .perspective(fovYDegrees: 60, aspect: aspect, near: 0.1, far: 100)
        self.stack = [.identity]
    }

    private var current: Matrix4 {
        get { stack[stack.count - 1] }
        set { stack[stack.count - 1] = newValue }
    }

    private func color(_ shade: Double = 1) -> Color {
        Color(.sRGB, red: rgba.r * shade, green: rgba.g * shade, blue: rgba.b * shade, opacity: rgba.a)
    }

    // MARK: Matrix stack (mirrors gl push/pop, translate/rotate/scale)

    public func pushMatrix() { stack.append(current) }
    public func popMatrix() { if stack.count > 1 { stack.removeLast() } }

    public func translate(_ x: Float, _ y: Float, _ z: Float) {
        current = current * .translation(x, y, z)
    }
    public func rotate(_ degrees: Float, _ x: Float, _ y: Float, _ z: Float) {
        current = current * .rotation(degrees: degrees, x, y, z)
    }
    public func scale(_ x: Float, _ y: Float, _ z: Float) {
        current = current * .scale(x, y, z)
    }

    public func glColor(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        rgba = (r, g, b, a)
    }

    /// Use additive blending for the following draws (R4 shader `B11` / `BA1`).
    public func additiveBlend() { context.blendMode = .plusLighter }
    public func normalBlend() { context.blendMode = .normal }

    // MARK: Projection

    /// Project an object-space point to screen space, or `nil` if behind the eye.
    private func project(_ p: SIMD3<Float>) -> CGPoint? {
        let eye = current.m * SIMD4<Float>(p.x, p.y, p.z, 1)
        let clip = projection.m * eye
        guard clip.w > 0.0001 else { return nil }
        let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
        return CGPoint(
            x: CGFloat(ndc.x * 0.5 + 0.5) * size.width,
            y: CGFloat(1 - (ndc.y * 0.5 + 0.5)) * size.height
        )
    }

    /// Eye-space depth of an object-space point (for painter's-order sorting).
    private func eyeDepth(_ p: SIMD3<Float>) -> Float {
        (current.m * SIMD4<Float>(p.x, p.y, p.z, 1)).z
    }

    // MARK: Primitives

    /// Draw a unit quad in the XY plane (corners ±1), filled with the current color.
    public func quad() {
        fillPolygon([SIMD3(-1, -1, 0), SIMD3(1, -1, 0), SIMD3(1, 1, 0), SIMD3(-1, 1, 0)],
                    with: color())
    }

    /// Draw a unit cube centered at the origin (corners ±1) with painter's-order
    /// face sorting and a little per-face shading for solidity.
    public func cube() {
        let v: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ]
        let faces: [(idx: [Int], shade: Double)] = [
            ([0, 1, 2, 3], 0.55), ([5, 4, 7, 6], 1.0),
            ([4, 0, 3, 7], 0.70), ([1, 5, 6, 2], 0.85),
            ([3, 2, 6, 7], 0.95), ([4, 5, 1, 0], 0.65)
        ]
        let sorted = faces.map { face -> (face: (idx: [Int], shade: Double), depth: Float) in
            let avg = face.idx.reduce(SIMD3<Float>(repeating: 0)) { $0 + v[$1] } / Float(face.idx.count)
            return (face, eyeDepth(avg))
        }.sorted { $0.depth < $1.depth }

        for item in sorted {
            fillPolygon(item.face.idx.map { v[$0] }, with: color(item.face.shade))
        }
    }

    /// Draw a soft round point at an object-space position, sized in world units
    /// and scaled by perspective (nearer points are larger). Used by particle /
    /// point-cloud scenes like Medusa.
    public func point(_ p: SIMD3<Float>, size: Float) {
        let eye = current.m * SIMD4<Float>(p.x, p.y, p.z, 1)
        let clip = projection.m * eye
        guard clip.w > 0.0001 else { return }
        let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
        let center = CGPoint(
            x: CGFloat(ndc.x * 0.5 + 0.5) * self.size.width,
            y: CGFloat(1 - (ndc.y * 0.5 + 0.5)) * self.size.height
        )
        // Project the world size to screen pixels via the perspective w (≈ depth).
        let radius = CGFloat(size) / CGFloat(clip.w) * self.size.height * 0.5
        guard radius > 0.2 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color()))
    }

    /// Draw a line between two object-space points using the current color.
    public func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width: CGFloat = 1) {
        guard let pa = project(a), let pb = project(b) else { return }
        var path = Path()
        path.move(to: pa); path.addLine(to: pb)
        context.stroke(path, with: .color(color()), lineWidth: width)
    }

    private func fillPolygon(_ pts: [SIMD3<Float>], with fill: Color) {
        var screen: [CGPoint] = []
        screen.reserveCapacity(pts.count)
        for p in pts {
            guard let s = project(p) else { return } // cull if any vertex is behind the eye
            screen.append(s)
        }
        var path = Path()
        path.move(to: screen[0])
        for s in screen.dropFirst() { path.addLine(to: s) }
        path.closeSubpath()
        context.fill(path, with: .color(fill))
    }
}
