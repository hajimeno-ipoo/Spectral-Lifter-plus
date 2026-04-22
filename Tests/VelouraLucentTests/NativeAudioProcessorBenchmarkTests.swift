import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct NativeAudioProcessorBenchmarkTests {
    @Test
    func recordsStageTimings() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "benchmark-input.wav")
        let outputURL = tempDirectory.appending(path: "benchmark-output.wav")

        try makeTestTone(at: inputURL, duration: 2)

        let benchmark = try NativeAudioProcessor().benchmark(
            inputFile: inputURL,
            outputFile: outputURL,
            denoiseStrength: .balanced
        )

        let expectedStages = [
            "loadAudio",
            "analyze",
            "neuralPrediction",
            "denoise",
            "harmonicUpscale",
            "multibandDynamics",
            "loudnessFinalize",
            "saveAudio"
        ]

        #expect(benchmark.stages.map(\.name) == expectedStages)
        #expect(benchmark.stages.allSatisfy { $0.durationSeconds >= 0 })
        #expect(benchmark.totalDurationSeconds >= 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path()))

        let report = benchmarkReport(for: benchmark)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentNativeAudioBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private func benchmarkReport(for benchmark: NativeAudioProcessingBenchmark) -> String {
        var lines = ["NativeAudioProcessor benchmark"]
        for stage in benchmark.stages {
            lines.append("\(stage.name): \(String(format: "%.6f", stage.durationSeconds))s")
        }
        lines.append("total: \(String(format: "%.6f", benchmark.totalDurationSeconds))s")
        return lines.joined(separator: "\n")
    }

    private func makeTestTone(at url: URL, duration: Double) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let base = Float(sin(2 * Double.pi * 440 * time) * 0.12)
            let upper = Float(sin(2 * Double.pi * 6_000 * time) * 0.03)
            left[index] = base + upper
            right[index] = base * 0.96 - upper * 0.4
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}
