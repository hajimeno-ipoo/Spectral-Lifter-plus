import AVFoundation
import Foundation
import Testing
@testable import SpectralLifter

struct AudioProcessingPipelineTests {
    @Test
    func pipelineProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "input.wav")
        let outputURL = tempDirectory.appending(path: "input_lifter.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(inputFile: inputURL) { _ in }

        #expect(output == outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path()))
        let written = try AVAudioFile(forReading: outputURL)
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
        let outputURL = tempDirectory.appending(path: "violin #002 睡眠_lifter.wav")

        try makeTestTone(at: inputURL, duration: 6)

        let output = try await AudioProcessingService().process(inputFile: inputURL) { _ in }

        #expect(output.path(percentEncoded: false) == outputURL.path(percentEncoded: false))
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
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
}
