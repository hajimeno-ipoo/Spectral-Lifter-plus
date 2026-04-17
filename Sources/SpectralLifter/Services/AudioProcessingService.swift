import Foundation

struct AudioProcessingService {
    func process(inputFile: URL, logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        let outputURL = Self.defaultOutputURL(for: inputFile)
        let outputPath = outputURL.path(percentEncoded: false)

        let logger = ClosureLogger(logHandler: logHandler)
        try await Task.detached(priority: .userInitiated) {
            try NativeAudioProcessor().process(inputFile: inputFile, outputFile: outputURL, logger: logger)
        }.value

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw AppError.outputNotFound(outputPath)
        }

        return outputURL
    }

    static func defaultOutputURL(for inputFile: URL) -> URL {
        let directory = inputFile.deletingLastPathComponent()
        let fileName = inputFile.deletingPathExtension().lastPathComponent
        let ext = inputFile.pathExtension
        return directory.appendingPathComponent("\(fileName)_lifter").appendingPathExtension(ext)
    }
}

private struct ClosureLogger: AudioProcessingLogger, Sendable {
    let logHandler: @Sendable (String) -> Void

    func log(_ message: String) {
        logHandler(message)
    }
}
