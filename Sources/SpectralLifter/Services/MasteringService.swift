import Foundation

struct MasteringService {
    func process(inputFile: URL, profile: MasteringProfile, logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        try await process(inputFile: inputFile, settings: profile.settings, logHandler: logHandler)
    }

    func process(inputFile: URL, settings: MasteringSettings, logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        let outputURL = Self.temporaryOutputURL(for: inputFile)
        let outputPath = outputURL.path(percentEncoded: false)
        let logger = MasteringClosureLogger(logHandler: logHandler)

        try await Task.detached(priority: .userInitiated) {
            logger.log(MasteringStep.analyze.rawValue)
            let signal = try AudioFileService.loadAudio(from: inputFile)
            let analysis = MasteringAnalysisService.analyze(signal: signal)
            let mastered = MasteringProcessor().process(
                signal: signal,
                analysis: analysis,
                settings: settings,
                logger: logger
            )
            logger.log(MasteringStep.save.rawValue)
            try AudioFileService.saveAudio(mastered, to: outputURL)
        }.value

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw AppError.outputNotFound(outputPath)
        }

        return outputURL
    }

    static func defaultOutputURL(for inputFile: URL) -> URL {
        let directory = inputFile.deletingLastPathComponent()
        let fileName = inputFile.deletingPathExtension().lastPathComponent
        let baseName = fileName.hasSuffix("_mastered") ? fileName : "\(fileName)_mastered"
        let ext = inputFile.pathExtension
        return directory.appendingPathComponent(baseName).appendingPathExtension(ext)
    }

    static func temporaryOutputURL(for inputFile: URL) -> URL {
        let fileName = inputFile.deletingPathExtension().lastPathComponent
        let baseName = fileName.hasSuffix("_mastered") ? fileName : "\(fileName)_mastered"
        let ext = inputFile.pathExtension
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpectralLifterPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory
            .appendingPathComponent("\(baseName)_\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }
}

private struct MasteringClosureLogger: AudioProcessingLogger, Sendable {
    let logHandler: @Sendable (String) -> Void

    func log(_ message: String) {
        logHandler(message)
    }
}
