import Foundation
import Testing
@testable import VelouraLucent

struct RealAudioWorkflowTests {
    @Test
    func realAudioExcerptProducesCorrectedAndMasteredComparisonReport() async throws {
        let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = projectDirectory.appending(path: "violin #002 睡眠.wav")
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            Issue.record("Real audio fixture is missing: \(sourceURL.path(percentEncoded: false))")
            return
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let excerptURL = tempDirectory.appending(path: "real-audio-excerpt.wav")

        let inputSignal = try AudioFileService.loadAudio(from: sourceURL)
        let excerptSignal = excerpt(from: inputSignal, seconds: 8)
        try AudioFileService.saveAudio(excerptSignal, to: excerptURL)

        let correctedURL = try await AudioProcessingService().process(
            inputFile: excerptURL,
            denoiseStrength: .strong,
            analysisMode: .cpu
        ) { _ in }
        let masteredURL = try await MasteringService().process(
            inputFile: correctedURL,
            profile: .streaming
        ) { _ in }

        let correctedSignal = try AudioFileService.loadAudio(from: correctedURL)
        let masteredSignal = try AudioFileService.loadAudio(from: masteredURL)
        let inputNoise = NoiseMeasurementService.analyze(signal: excerptSignal)
        let correctedNoise = NoiseMeasurementService.analyze(signal: correctedSignal)
        let masteredNoise = NoiseMeasurementService.analyze(signal: masteredSignal)
        let report = report(
            input: excerptSignal,
            corrected: correctedSignal,
            mastered: masteredSignal,
            inputNoise: inputNoise,
            correctedNoise: correctedNoise,
            masteredNoise: masteredNoise
        )
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentRealAudioWorkflow.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: correctedURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: masteredURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
        #expect([inputNoise, correctedNoise, masteredNoise].flatMap(\.values).allSatisfy {
            $0.comparableLevelDB.isFinite && $0.measuredLevelDB.isFinite
        })
        #expect(MasteringAnalysisService.approximateTruePeak(masteredSignal.channels) <= powf(10, MasteringProfile.streaming.settings.peakCeilingDB / 20) + 0.02)
    }

    private func excerpt(from signal: AudioSignal, seconds: Double) -> AudioSignal {
        let frameCount = min(signal.frameCount, max(1, Int(signal.sampleRate * seconds)))
        return AudioSignal(
            channels: signal.channels.map { Array($0.prefix(frameCount)) },
            sampleRate: signal.sampleRate
        )
    }

    private func report(
        input: AudioSignal,
        corrected: AudioSignal,
        mastered: AudioSignal,
        inputNoise: NoiseMeasurementSnapshot,
        correctedNoise: NoiseMeasurementSnapshot,
        masteredNoise: NoiseMeasurementSnapshot
    ) -> String {
        var lines = [
            "# Real Audio Workflow",
            "",
            "- source: violin #002 睡眠.wav",
            "- excerpt: 8 seconds",
            "- correction: strong",
            "- mastering: streaming",
            "",
            "## Loudness",
            "",
            "| stage | integrated LUFS | true peak dBFS |",
            "| --- | ---: | ---: |",
            loudnessLine("input", input),
            loudnessLine("corrected", corrected),
            loudnessLine("mastered", mastered),
            "",
            "## Noise",
            "",
            "| metric | input | corrected | mastered | corrected-input | mastered-corrected |",
            "| --- | ---: | ---: | ---: | ---: | ---: |"
        ]

        for value in inputNoise.values {
            let correctedValue = correctedNoise.value(for: value.id)?.comparableLevelDB ?? -120
            let masteredValue = masteredNoise.value(for: value.id)?.comparableLevelDB ?? -120
            lines.append(
                "| \(value.label) | \(format(value.comparableLevelDB)) | \(format(correctedValue)) | \(format(masteredValue)) | \(format(correctedValue - value.comparableLevelDB, signed: true)) | \(format(masteredValue - correctedValue, signed: true)) |"
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func loudnessLine(_ label: String, _ signal: AudioSignal) -> String {
        let loudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        let peak = 20 * log10(Double(max(MasteringAnalysisService.approximateTruePeak(signal.channels), 1e-9)))
        return "| \(label) | \(format(Double(loudness))) | \(format(peak)) |"
    }

    private func format(_ value: Double, signed: Bool = false) -> String {
        String(format: signed ? "%+.1f dB" : "%.1f dB", value)
    }
}
