import ImageIO
import XCTest
@testable import QoixDraw

final class PNGEncoderTests: XCTestCase {
    private func image(width: Int, height: Int) throws -> CGImage {
        let canvas = try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: width, height: height)))
        return try XCTUnwrap(canvas.makeImage())
    }

    func testProducesAPNGWithTheSameDimensions() throws {
        let data = try XCTUnwrap(PNGEncoder.data(from: try image(width: 40, height: 25)))
        XCTAssertEqual(Array(data.prefix(8)), pngSignature)
        let size = try pixelSize(ofPNG: data)
        XCTAssertEqual(size.width, 40)
        XCTAssertEqual(size.height, 25)
    }

    func testTheLargestAllowedCanvasEncodesAt2000By2000() throws {
        let data = try XCTUnwrap(PNGEncoder.data(from: try image(width: 5000, height: 5000)))
        let size = try pixelSize(ofPNG: data)
        XCTAssertEqual(size.width, 2000)
        XCTAssertEqual(size.height, 2000)
    }
}

final class SaveNamingTests: XCTestCase {
    func testNameContainsTheDateAndTimeInTheGivenTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(SaveNaming.fileName(for: Date(timeIntervalSince1970: 0), timeZone: utc),
                       "QOIX Draw 1970-01-01 00.00.00.png")

        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(SaveNaming.fileName(for: Date(timeIntervalSince1970: 1_800_000_000), timeZone: newYork),
                       "QOIX Draw 2027-01-15 03.00.00.png")
    }
}

final class DocumentsSaverTests: XCTestCase {
    func testWritesTheFileAndCreatesTheFolder() throws {
        let folder = makeTemporaryFolder()
        let url = try DocumentsSaver(directory: folder).save(Data([1, 2, 3]), filename: "a.png")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, "a.png")
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }

    func testNeverOverwritesAnExistingFile() throws {
        let saver = DocumentsSaver(directory: makeTemporaryFolder())
        let first = try saver.save(Data([1]), filename: "a.png")
        let second = try saver.save(Data([2]), filename: "a.png")
        let third = try saver.save(Data([3]), filename: "a.png")
        XCTAssertEqual([first, second, third].map(\.lastPathComponent), ["a.png", "a 2.png", "a 3.png"])
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
        XCTAssertEqual(try Data(contentsOf: third), Data([3]))
    }
}

final class DrawingSaverTests: XCTestCase {
    private func run(_ saver: DrawingSaver) throws -> Result<SaveOutcome, SaveError> {
        let canvas = try XCTUnwrap(BitmapCanvas(spec: CanvasSpec(width: 16, height: 16)))
        let image = try XCTUnwrap(canvas.makeImage())
        let finished = expectation(description: "save finished")
        var outcome: Result<SaveOutcome, SaveError>?
        saver.save(image: image) { result in
            XCTAssertTrue(Thread.isMainThread, "completion must arrive on the main thread")
            outcome = result
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        return try XCTUnwrap(outcome)
    }

    func testSavesAPNGToPhotosWhenAvailable() throws {
        let photos = SpyPhotos()
        let folder = makeTemporaryFolder()
        let result = try run(DrawingSaver(photos: photos, files: DocumentsSaver(directory: folder)))

        XCTAssertEqual(result, .success(.savedToPhotos))
        XCTAssertEqual(photos.filenames.count, 1)
        XCTAssertTrue(photos.filenames[0].hasPrefix("QOIX Draw "))
        XCTAssertTrue(photos.filenames[0].hasSuffix(".png"))
        XCTAssertEqual(Array(photos.payloads[0].prefix(8)), pngSignature)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "nothing should be written to Files")
    }

    func testFallsBackToFilesWhenPhotosAccessIsDenied() throws {
        let photos = SpyPhotos()
        photos.result = .failure(.notAuthorized)
        let folder = makeTemporaryFolder()
        let result = try run(DrawingSaver(photos: photos, files: DocumentsSaver(directory: folder)))

        guard case .success(.savedToFiles(let url, let denied)) = result else {
            return XCTFail("expected a Files fallback, got \(result)")
        }
        XCTAssertTrue(denied)
        XCTAssertEqual(Array(try Data(contentsOf: url).prefix(8)), pngSignature)
    }

    func testFallsBackToFilesWhenPhotosFailsForAnotherReason() throws {
        let photos = SpyPhotos()
        photos.result = .failure(.failed("disk full"))
        let result = try run(DrawingSaver(photos: photos, files: DocumentsSaver(directory: makeTemporaryFolder())))

        guard case .success(.savedToFiles(_, let denied)) = result else {
            return XCTFail("expected a Files fallback, got \(result)")
        }
        XCTAssertFalse(denied)
    }

    func testReportsFailureWhenNeitherPlaceWorks() throws {
        let photos = SpyPhotos()
        photos.result = .failure(.notAuthorized)
        let unwritable = DocumentsSaver(directory: URL(fileURLWithPath: "/dev/null/qoixdraw"))
        let result = try run(DrawingSaver(photos: photos, files: unwritable))

        guard case .failure(.writeFailed) = result else {
            return XCTFail("expected a write failure, got \(result)")
        }
    }

    func testReportsEncodingFailureWithoutTouchingPhotos() throws {
        let photos = SpyPhotos()
        let result = try run(DrawingSaver(photos: photos, files: DocumentsSaver(directory: makeTemporaryFolder()), encode: { _ in nil }))

        XCTAssertEqual(result, .failure(.encodingFailed))
        XCTAssertTrue(photos.filenames.isEmpty)
    }
}
