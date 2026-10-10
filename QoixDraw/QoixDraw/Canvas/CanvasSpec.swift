import CoreGraphics

/// The pixel size of a drawing.
///
/// A drawing is never larger than `maxDimension` (2000 px) on either side. That ceiling is enforced here,
/// in one place, so nothing else in the app can create or export an oversized image.
struct CanvasSpec: Equatable, Codable {
    /// The largest allowed width or height, in pixels.
    static let maxDimension = 2000

    let width: Int
    let height: Int

    /// Creates a canvas of the requested size. Anything larger than `maxDimension` on its longest side is
    /// scaled down to fit (keeping the proportions); anything smaller than 1 px is raised to 1 px.
    init(width: Int, height: Int) {
        let w = max(width, 1)
        let h = max(height, 1)
        let longest = max(w, h)
        if longest > Self.maxDimension {
            let scale = Double(Self.maxDimension) / Double(longest)
            self.width = max(Int((Double(w) * scale).rounded()), 1)
            self.height = max(Int((Double(h) * scale).rounded()), 1)
        } else {
            self.width = w
            self.height = h
        }
    }

    /// The largest canvas with the same proportions as `size` (for example, the screen).
    /// A 393 x 852 pt screen gives 923 x 2000 px.
    static func fitting(aspectOf size: CGSize) -> CanvasSpec {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CanvasSpec(width: maxDimension, height: maxDimension)
        }
        let scale = Double(maxDimension) / Double(max(size.width, size.height))
        return CanvasSpec(
            width: Int((Double(size.width) * scale).rounded()),
            height: Int((Double(size.height) * scale).rounded())
        )
    }

    var size: CGSize { CGSize(width: width, height: height) }

    // MARK: Codable (decoding goes through the clamping initializer above)

    private enum CodingKeys: String, CodingKey {
        case width, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int.self, forKey: .width)
        let height = try container.decode(Int.self, forKey: .height)
        self.init(width: width, height: height)
    }
}
