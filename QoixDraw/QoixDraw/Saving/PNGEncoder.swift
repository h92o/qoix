import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGEncoder {
    /// Encodes `image` as a PNG file. Returns nil if encoding fails.
    static func data(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
