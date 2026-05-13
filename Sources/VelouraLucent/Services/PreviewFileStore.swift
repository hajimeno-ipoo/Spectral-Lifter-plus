import Foundation

enum PreviewFileStore {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VelouraLucentPreview", isDirectory: true)

    static func temporaryOutputURL(baseName: String, suffix: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitizedName = shortPreviewBaseName(from: baseName)
        let shortID = String(UUID().uuidString.prefix(6)).lowercased()
        return directory
            .appendingPathComponent("\(sanitizedName)_\(suffix)_\(shortID)")
            .appendingPathExtension(AudioFileService.outputFileExtension)
    }

    static func removeAllPreviewFiles() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == AudioFileService.outputFileExtension {
            try? fileManager.removeItem(at: file)
        }
    }

    private static func shortPreviewBaseName(from fileName: String) -> String {
        let trimmed = fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return String(trimmed.prefix(24))
    }
}
