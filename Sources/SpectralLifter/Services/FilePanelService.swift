import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanelService {
    static func chooseAudioFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .audio,
            UTType(filenameExtension: "wav"),
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "m4a"),
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "aiff")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "開く"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
