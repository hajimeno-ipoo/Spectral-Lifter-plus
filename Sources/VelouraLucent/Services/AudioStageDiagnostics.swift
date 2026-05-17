import Foundation

enum AudioStageDiagnostics {
    static func save(
        _ signal: AudioSignal,
        to directory: URL?,
        domain: String,
        order: Int,
        id: String,
        label: String,
        logger: AudioProcessingLogger?
    ) {
        guard let directory else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeLabel = sanitize(label)
            let fileName = String(format: "%02d_%@_%@_%@.wav", order, domain, id, safeLabel)
            let url = directory.appending(path: fileName)
            try AudioFileService.saveAudio(signal, to: url)
            logger?.log("診断書き出し: \(url.path(percentEncoded: false))")
        } catch {
            logger?.log("診断書き出し失敗: \(domain)/\(id) - \(error.localizedDescription)")
        }
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }
}
