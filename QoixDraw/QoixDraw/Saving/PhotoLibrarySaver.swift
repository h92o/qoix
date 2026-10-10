import Foundation
import Photos
import UniformTypeIdentifiers

enum PhotoSaveError: Error, Equatable {
    /// The user has not allowed (or iOS restricts) adding to the photo library.
    case notAuthorized
    case failed(String)
}

protocol PhotoSaving {
    /// Adds a PNG to the photo library. May call `completion` on any queue.
    func savePNG(_ data: Data, filename: String, completion: @escaping (Result<Void, PhotoSaveError>) -> Void)
}

/// Saves to the Photos library using add-only access, so the app never needs to read your photos.
/// The first save shows the system permission prompt.
struct PhotoLibrarySaver: PhotoSaving {
    func savePNG(_ data: Data, filename: String, completion: @escaping (Result<Void, PhotoSaveError>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(.notAuthorized))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = filename
                options.uniformTypeIdentifier = UTType.png.identifier
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }, completionHandler: { success, error in
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(.failed(error?.localizedDescription ?? "Unknown error")))
                }
            })
        }
    }
}
