import ImageIO
import XCTest
@testable import QoixDraw

let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

/// Reads the pixel dimensions out of PNG data.
func pixelSize(ofPNG data: Data) throws -> (width: Int, height: Int) {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
    return (width, height)
}

/// A stand-in for the photo library that records what it was asked to save.
final class SpyPhotos: PhotoSaving {
    private let lock = NSLock()
    private var storedFilenames: [String] = []
    private var storedPayloads: [Data] = []

    /// What the next save should report.
    var result: Result<Void, PhotoSaveError> = .success(())

    var filenames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedFilenames
    }

    var payloads: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedPayloads
    }

    func savePNG(_ data: Data, filename: String, completion: @escaping (Result<Void, PhotoSaveError>) -> Void) {
        lock.lock()
        storedFilenames.append(filename)
        storedPayloads.append(data)
        lock.unlock()
        completion(result)
    }
}

extension XCTestCase {
    /// A fresh, not-yet-created folder path that is deleted when the test ends.
    func makeTemporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qoixdraw-tests-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    /// Lets the main run loop (and so anything dispatched to the main queue) run for a moment.
    func letMainQueueRun(for seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

/// The raw bytes of an image's pixels, row by row, for comparing two pictures exactly.
func pixelBytes(of image: CGImage) -> Data? {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
    return Data(bytes: bytes, count: CFDataGetLength(data))
}

/// Evenly spaced finger samples along a straight line, as if drawn at a steady `speed` (canvas pixels per second).
func linePoints(from start: CGPoint, to end: CGPoint, spacing: Double = 4, speed: Double = 600) -> [StrokePoint] {
    let dx = Double(end.x - start.x)
    let dy = Double(end.y - start.y)
    let length = (dx * dx + dy * dy).squareRoot()
    let count = max(1, Int((length / spacing).rounded(.up)))
    return (0...count).map { index in
        let t = Double(index) / Double(count)
        return StrokePoint(x: Double(start.x) + dx * t, y: Double(start.y) + dy * t, time: length * t / speed)
    }
}

/// How much ink (in canvas pixels) lies along a straight probe through `center`, found by sampling the committed
/// pixels at quarter-pixel steps. `direction` doesn't need to be a unit vector.
func inkWidth(in canvas: BitmapCanvas, through center: CGPoint, direction: CGVector, reach: Double = 45) -> Double {
    let length = Double(hypot(direction.dx, direction.dy))
    let ux = Double(direction.dx) / length
    let uy = Double(direction.dy) / length
    let step = 0.25
    var covered = 0.0
    var t = -reach
    while t <= reach {
        let x = Int((Double(center.x) + ux * t).rounded(.down))
        let y = Int((Double(center.y) + uy * t).rounded(.down))
        if let pixel = canvas.pixel(x: x, y: y), pixel.r < 128 {
            covered += step
        }
        t += step
    }
    return covered
}
