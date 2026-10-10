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
