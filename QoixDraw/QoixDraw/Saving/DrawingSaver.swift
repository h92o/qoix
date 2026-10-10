import CoreGraphics
import Foundation

enum SaveOutcome: Equatable {
    case savedToPhotos
    /// The photo library couldn't be used, so the picture was kept in the app's Files folder instead.
    /// `photosAccessDenied` is true when the cause was missing permission (worth telling the user).
    case savedToFiles(URL, photosAccessDenied: Bool)
}

enum SaveError: Error, Equatable {
    case encodingFailed
    case writeFailed(String)
}

/// Encodes a drawing as PNG and stores it: Photos first, the app's Files folder if that fails.
struct DrawingSaver {
    private let photos: PhotoSaving
    private let files: FileSaving
    private let encode: (CGImage) -> Data?

    init(
        photos: PhotoSaving = PhotoLibrarySaver(),
        files: FileSaving = DocumentsSaver(),
        encode: @escaping (CGImage) -> Data? = { PNGEncoder.data(from: $0) }
    ) {
        self.photos = photos
        self.files = files
        self.encode = encode
    }

    /// Saves `image`. Encoding and writing happen off the main thread; `completion` is always called on it.
    func save(image: CGImage, date: Date = Date(), completion: @escaping (Result<SaveOutcome, SaveError>) -> Void) {
        let photos = self.photos
        let files = self.files
        let encode = self.encode
        let filename = SaveNaming.fileName(for: date)

        func finish(_ result: Result<SaveOutcome, SaveError>) {
            DispatchQueue.main.async {
                completion(result)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = encode(image) else {
                finish(.failure(.encodingFailed))
                return
            }
            photos.savePNG(data, filename: filename) { photoResult in
                switch photoResult {
                case .success:
                    finish(.success(.savedToPhotos))
                case .failure(let photoError):
                    do {
                        let url = try files.save(data, filename: filename)
                        finish(.success(.savedToFiles(url, photosAccessDenied: photoError == .notAuthorized)))
                    } catch {
                        finish(.failure(.writeFailed(error.localizedDescription)))
                    }
                }
            }
        }
    }
}
