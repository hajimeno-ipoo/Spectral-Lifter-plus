import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioAnalysisModeTests {
    @Test
    func experimentalMetalAnalysisMatchesCPUOutput() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "analysis-mode-input.wav")
        let cpuOutputURL = tempDirectory.appending(path: "analysis-mode-cpu.wav")
        let metalOutputURL = tempDirectory.appending(path: "analysis-mode-metal.wav")

        try makeTestTone(at: inputURL, duration: 2)

        let processor = NativeAudioProcessor()
        try processor.process(
            inputFile: inputURL,
            outputFile: cpuOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        )
        try processor.process(
            inputFile: inputURL,
            outputFile: metalOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        )

        let cpuData = try Data(contentsOf: cpuOutputURL)
        let metalData = try Data(contentsOf: metalOutputURL)
        #expect(cpuData == metalData)
    }

    @Test
    func metalAnalysisProcessorProducesSeparatedSpectraWhenAvailable() {
        let processor = MetalAudioAnalysisProcessor()
        guard processor.isAvailable else { return }

        let sampleRate = 48_000.0
        let samples = (0..<16_384).map { index in
            let time = Double(index) / sampleRate
            return Float(sin(2 * Double.pi * 440 * time) * 0.1)
        }
        let spectrogram = SpectralDSP.stft(samples)

        let separated = processor.separatedMeanSpectra(spectrogram: spectrogram)

        #expect(separated != nil)
        #expect(separated?.harmonic.count == spectrogram.binCount)
        #expect(separated?.percussive.count == spectrogram.binCount)
    }

    @Test
    func experimentalMetalAnalysisValuesStayNearCPU() {
        let signal = makeTestSignal(duration: 2)

        let cpu = AudioAnalyzer(mode: .cpu).analyze(signal: signal)
        let metal = AudioAnalyzer(mode: .experimentalMetal).analyze(signal: signal)

        #expect(abs(cpu.cutoffFrequency - metal.cutoffFrequency) <= 1)
        #expect(abs(cpu.harmonicConfidence - metal.harmonicConfidence) <= 0.0001)
        #expect(cpu.hasShimmer == metal.hasShimmer)
        #expect(abs(cpu.shimmerRatio - metal.shimmerRatio) <= 0.0001)
        #expect(abs(cpu.brightnessRatio - metal.brightnessRatio) <= 0.0001)
        #expect(abs(cpu.transientAmount - metal.transientAmount) <= 0.000001)
        #expect(abs(cpu.noiseAmount - metal.noiseAmount) <= 0.0001)
    }

    @Test
    func recordsCPUAndExperimentalMetalAnalysisBenchmarks() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "analysis-benchmark-input.wav")
        let cpuOutputURL = tempDirectory.appending(path: "analysis-benchmark-cpu.wav")
        let metalOutputURL = tempDirectory.appending(path: "analysis-benchmark-metal.wav")

        try makeTestTone(at: inputURL, duration: 2)

        let processor = NativeAudioProcessor()
        let cpuBenchmark = try processor.benchmark(
            inputFile: inputURL,
            outputFile: cpuOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        )
        let metalBenchmark = try processor.benchmark(
            inputFile: inputURL,
            outputFile: metalOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        )

        #expect(cpuBenchmark.duration(for: "analyze") != nil)
        #expect(metalBenchmark.duration(for: "analyze") != nil)
        #expect(try Data(contentsOf: cpuOutputURL) == Data(contentsOf: metalOutputURL))

        let report = analysisBenchmarkReport(cpu: cpuBenchmark, metal: metalBenchmark)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentAnalysisModeBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private func analysisBenchmarkReport(
        cpu: NativeAudioProcessingBenchmark,
        metal: NativeAudioProcessingBenchmark
    ) -> String {
        let cpuAnalyze = cpu.duration(for: "analyze") ?? 0
        let metalAnalyze = metal.duration(for: "analyze") ?? 0
        return [
            "Audio analysis mode benchmark",
            "cpu.analyze: \(String(format: "%.6f", cpuAnalyze))s",
            "experimentalMetal.analyze: \(String(format: "%.6f", metalAnalyze))s",
            "cpu.total: \(String(format: "%.6f", cpu.totalDurationSeconds))s",
            "experimentalMetal.total: \(String(format: "%.6f", metal.totalDurationSeconds))s"
        ].joined(separator: "\n")
    }

    private func makeTestSignal(duration: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        var left = Array(repeating: Float.zero, count: frameCount)
        var right = Array(repeating: Float.zero, count: frameCount)

        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let base = Float(sin(2 * Double.pi * 330 * time) * 0.11)
            let high = Float(sin(2 * Double.pi * 7_200 * time) * 0.025)
            left[index] = base + high
            right[index] = base * 0.94 - high * 0.35
        }

        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
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
            let base = Float(sin(2 * Double.pi * 330 * time) * 0.11)
            let high = Float(sin(2 * Double.pi * 7_200 * time) * 0.025)
            left[index] = base + high
            right[index] = base * 0.94 - high * 0.35
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}
