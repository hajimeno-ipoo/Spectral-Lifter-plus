import SwiftUI

@MainActor
@Observable
final class ProcessingJob {
    var inputFile: URL?
    var outputFile: URL?
    var logText = ""
    var statusMessage = "待機中"
    var isProcessing = false
    var lastError: String?
    var hasExistingOutput = false

    var statusColor: Color {
        if isProcessing {
            return .orange
        }
        if lastError != nil {
            return .red
        }
        return .secondary
    }

    func prepareForSelection(_ inputURL: URL) {
        inputFile = inputURL
        outputFile = AudioProcessingService.defaultOutputURL(for: inputURL)
        logText = ""
        statusMessage = "処理待ち"
        lastError = nil
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
    }

    func beginProcessing() {
        isProcessing = true
        lastError = nil
        logText = ""
        statusMessage = "処理中"
    }

    func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if logText.isEmpty {
            logText = trimmed
        } else {
            logText += "\n\(trimmed)"
        }
    }

    func finishSuccess(_ outputURL: URL) {
        isProcessing = false
        outputFile = outputURL
        statusMessage = "完了"
        hasExistingOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
    }

    func finishFailure(_ message: String) {
        isProcessing = false
        lastError = message
        statusMessage = "失敗"
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        appendLog(message)
    }
}
