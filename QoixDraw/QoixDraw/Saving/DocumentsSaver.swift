import Foundation

protocol FileSaving {
    /// Writes `data` into the app's folder and returns where it went.
    func save(_ data: Data, filename: String) throws -> URL
}

/// Keeps a copy in the app's Documents folder ("QOIX Draw" under On My iPhone in the Files app). Used as the
/// fallback when the photo library can't be written to, so a drawing is never lost.
struct DocumentsSaver: FileSaving {
    let directory: URL

    init(directory: URL = DocumentsSaver.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("QOIX Draw", isDirectory: true)
    }

    func save(_ data: Data, filename: String) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var url = directory.appendingPathComponent(filename)
        var attempt = 2
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(attempt).\(ext)")
            attempt += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
