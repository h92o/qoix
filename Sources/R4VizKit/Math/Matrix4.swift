import CoreGraphics
import simd

/// A 4×4 transform matrix using column-major storage, matching the OpenGL
/// convention that R4's scene scripts were written against.
///
/// R4 scenes drive an immediate-mode pipeline (`gl.gltranslate`, `gl.glrotate`,
/// `gl.glscale`, perspective projection). We reproduce just enough of that math
/// to project the ported scenes identically on macOS and iOS without a GPU
/// dependency.
public struct Matrix4 {
    public var m: simd_float4x4

    public init(_ m: simd_float4x4) { self.m = m }

    public static let identity = Matrix4(matrix_identity_float4x4)

    public static func translation(_ x: Float, _ y: Float, _ z: Float) -> Matrix4 {
        var r = matrix_identity_float4x4
        r.columns.3 = SIMD4<Float>(x, y, z, 1)
        return Matrix4(r)
    }

    public static func scale(_ x: Float, _ y: Float, _ z: Float) -> Matrix4 {
        var r = matrix_identity_float4x4
        r.columns.0.x = x; r.columns.1.y = y; r.columns.2.z = z
        return Matrix4(r)
    }

    /// Rotation by `degrees` about the (x, y, z) axis — matches `gl.glrotate`.
    public static func rotation(degrees: Float, _ x: Float, _ y: Float, _ z: Float) -> Matrix4 {
        let len = (x * x + y * y + z * z).squareRoot()
        guard len > 0 else { return .identity }
        let a = degrees * .pi / 180
        let (ax, ay, az) = (x / len, y / len, z / len)
        let c = cosf(a), s = sinf(a), t = 1 - c
        let col0 = SIMD4<Float>(t * ax * ax + c,      t * ax * ay + s * az, t * ax * az - s * ay, 0)
        let col1 = SIMD4<Float>(t * ax * ay - s * az, t * ay * ay + c,      t * ay * az + s * ax, 0)
        let col2 = SIMD4<Float>(t * ax * az + s * ay, t * ay * az - s * ax, t * az * az + c,      0)
        let col3 = SIMD4<Float>(0, 0, 0, 1)
        return Matrix4(simd_float4x4(col0, col1, col2, col3))
    }

    /// A symmetric perspective projection (like `gluPerspective`).
    public static func perspective(fovYDegrees: Float, aspect: Float, near: Float, far: Float) -> Matrix4 {
        let f = 1 / tanf(fovYDegrees * .pi / 360)
        let col0 = SIMD4<Float>(f / aspect, 0, 0, 0)
        let col1 = SIMD4<Float>(0, f, 0, 0)
        let col2 = SIMD4<Float>(0, 0, (far + near) / (near - far), -1)
        let col3 = SIMD4<Float>(0, 0, (2 * far * near) / (near - far), 0)
        return Matrix4(simd_float4x4(col0, col1, col2, col3))
    }

    public static func * (lhs: Matrix4, rhs: Matrix4) -> Matrix4 {
        Matrix4(lhs.m * rhs.m)
    }

    /// Transform a point, returning the clip-space vector (before perspective divide).
    public func transform(_ p: SIMD3<Float>) -> SIMD4<Float> {
        m * SIMD4<Float>(p.x, p.y, p.z, 1)
    }
}
