import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioProcessingPipelineTests {
    @Test
    func pipelineProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "input.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(output.lastPathComponent.contains("input_lifter"))
        let written = try AVAudioFile(forReading: output)
        #expect(written.length > 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(written.length))!
        try written.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        #expect(samples.contains { $0.isFinite })
        #expect(samples.map { abs($0) }.max() ?? 0 <= 1.01)
    }

    @Test
    func pipelineHandlesLocalizedFilename() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "violin #002 睡眠.wav")

        try makeTestTone(at: inputURL, duration: 6)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .gentle
        ) { _ in }

        #expect(output.lastPathComponent.contains("_lifter_"))
        #expect(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test
    func pipelineAcceptsExperimentalMetalAnalysisMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "metal-analysis.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func pipelineAcceptsAutoAnalysisMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "auto-analysis.wav")

        try makeTestTone(at: inputURL)
        let logs = LogCollector()

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .auto
        ) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(logs.values.contains("解析モード: 自動 -> \(AudioAnalysisMode.auto.resolvedMode.title)"))
        #expect(logs.values.contains { $0.hasPrefix("合計: ") && $0.hasSuffix("秒") })
    }

    @Test
    func pipelineAcceptsCustomCorrectionSettings() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "custom-correction.wav")

        try makeTestTone(at: inputURL)
        var settings = DenoiseStrength.balanced.settings
        settings.highNaturalness = 0.74
        settings.airRepair = 0.42

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func strongerCorrectionSettingsReduceMeasuredHighNoise() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "hissy-input.wav")

        try makeNoisyTone(at: inputURL)

        var strongerSettings = DenoiseStrength.balanced.settings
        strongerSettings.correctionIntensity = 0.78
        strongerSettings.highNaturalness = 0.88
        strongerSettings.noiseDetectionSensitivity = 0.78
        strongerSettings.airRepair = 0.32

        let defaultOutput = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: DenoiseStrength.balanced.settings,
            analysisMode: .cpu
        ) { _ in }
        let strongerOutput = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: strongerSettings,
            analysisMode: .cpu
        ) { _ in }

        let defaultHighNoise = try bandRMS(from: defaultOutput, lower: 10_000, upper: 16_000)
        let strongerHighNoise = try bandRMS(from: strongerOutput, lower: 10_000, upper: 16_000)

        #expect(strongerHighNoise < defaultHighNoise * 0.82)
    }

    @Test
    func maximumLowCleanupKeepsRumbleBandPolarity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "rumbly-input.wav")

        try makeRumblyTone(at: inputURL)
        var settings = DenoiseStrength.strong.settings
        settings.lowCleanup = 1
        settings.noiseDetectionSensitivity = 1
        settings.correctionIntensity = 1

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { _ in }

        let inputBand = try bandSamples(from: inputURL, lower: 35, upper: 80)
        let outputBand = try bandSamples(from: output, lower: 35, upper: 80)
        let dotProduct = zip(inputBand, outputBand).reduce(Float.zero) { partial, pair in
            partial + pair.0 * pair.1
        }

        #expect(dotProduct > 0)
        #expect(outputBand.allSatisfy { $0.isFinite })
    }

    @Test
    func correctionLeavesFinalLoudnessToMastering() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "loudness-reference.wav")

        try makeTestTone(at: inputURL, duration: 3)

        let correctedOutput = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        ) { _ in }
        let masteredOutput = try await MasteringService().process(
            inputFile: correctedOutput,
            profile: .streaming
        ) { _ in }

        let inputSignal = try AudioFileService.loadAudio(from: inputURL)
        let correctedSignal = try AudioFileService.loadAudio(from: correctedOutput)
        let masteredSignal = try AudioFileService.loadAudio(from: masteredOutput)
        let inputLoudness = MasteringAnalysisService.integratedLoudness(signal: inputSignal)
        let correctedLoudness = MasteringAnalysisService.integratedLoudness(signal: correctedSignal)
        let masteredLoudness = MasteringAnalysisService.integratedLoudness(signal: masteredSignal)
        let masteredPeak = MasteringAnalysisService.approximateTruePeak(masteredSignal.channels)

        #expect(correctedLoudness < inputLoudness - 3)
        #expect(masteredLoudness > correctedLoudness + 10)
        #expect(masteredPeak <= powf(10, MasteringProfile.streaming.settings.peakCeilingDB / 20) + 0.02)
    }

    @Test
    func outputURLsUseWavEvenWhenInputExtensionIsCompressed() {
        let inputURL = URL(fileURLWithPath: "/tmp/demo-track.mp3")

        let defaultOutput = AudioProcessingService.defaultOutputURL(for: inputURL)
        let temporaryOutput = AudioProcessingService.temporaryOutputURL(for: inputURL)

        #expect(defaultOutput.pathExtension == AudioFileService.outputFileExtension)
        #expect(temporaryOutput.pathExtension == AudioFileService.outputFileExtension)
    }

    private func makeTestTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            channel[index] = Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.1)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeNoisyTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.09
            let hiss = sin(2 * Double.pi * 11_700 * time) * 0.026
                + sin(2 * Double.pi * 13_900 * time) * 0.022
            let flicker = (index / 240) % 2 == 0 ? 1.0 : 0.55
            channel[index] = Float(body + hiss * flicker)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeRumblyTone(at url: URL, duration: Double = 1) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.04
            let rumble = sin(2 * Double.pi * 50 * time) * 0.08
            channel[index] = Float(body + rumble)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func bandRMS(from url: URL, lower: Double, upper: Double) throws -> Float {
        let band = try bandSamples(from: url, lower: lower, upper: upper)
        let meanSquare = band.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(band.count, 1))
        return sqrtf(meanSquare)
    }

    private func bandSamples(from url: URL, lower: Double, upper: Double) throws -> [Float] {
        let signal = try AudioFileService.loadAudio(from: url)
        guard let channel = signal.channels.first else { return [] }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upper,
            sampleRate: signal.sampleRate
        )
    }

}

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
