import AppKit
import SwiftUI

struct ContentView: View {
    @State private var job = ProcessingJob()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            inputSection
            outputSection
            actionSection
            logSection
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 500)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spectral Lifter")
                .font(.largeTitle.bold())
            Text("AI音源の高域補完とシマーノイズ低減を、Macアプリから直接実行します。")
                .foregroundStyle(.secondary)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入力ファイル")
                .font(.headline)

            HStack {
                Text(job.inputFile?.path(percentEncoded: false) ?? "まだ選択されていません")
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("音声を選ぶ") {
                    if let url = FilePanelService.chooseAudioFile() {
                        job.prepareForSelection(url)
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("出力ファイル")
                .font(.headline)

            Text(job.outputFile?.path(percentEncoded: false) ?? "入力ファイルを選ぶと自動で決まります")
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button(job.isProcessing ? "処理中..." : "処理を開始") {
                startProcessing()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(job.inputFile == nil || job.isProcessing)

            Button("結果を開く") {
                guard let outputFile = job.outputFile else { return }
                NSWorkspace.shared.open(outputFile)
            }
            .disabled(!job.hasExistingOutput || job.isProcessing)

            Button("Finderで表示") {
                guard let outputFile = job.outputFile else { return }
                NSWorkspace.shared.activateFileViewerSelecting([outputFile])
            }
            .disabled(!job.hasExistingOutput || job.isProcessing)

            Spacer()

            Text(job.statusMessage)
                .foregroundStyle(job.statusColor)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("処理ログ")
                .font(.headline)

            ScrollView {
                Text(job.logText.isEmpty ? "ここに処理ログが表示されます。" : job.logText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func startProcessing() {
        guard let inputFile = job.inputFile else { return }

        Task {
            job.beginProcessing()

            do {
                let outputFile = try await AudioProcessingService().process(inputFile: inputFile) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }
                await MainActor.run {
                    job.finishSuccess(outputFile)
                }
            } catch {
                await MainActor.run {
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
