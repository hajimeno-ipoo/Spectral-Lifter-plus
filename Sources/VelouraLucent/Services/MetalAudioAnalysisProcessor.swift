import Foundation

#if canImport(Metal)
import Metal
#endif

struct MetalAudioAnalysisProcessor: Sendable {
    var isAvailable: Bool {
        #if canImport(Metal)
        Self.cache.context() != nil
        #else
        false
        #endif
    }

    func separatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra? {
        guard let magnitudes = makeMagnitudes(spectrogram: spectrogram),
              let separatedSpectrum = separatedMeanSpectra(
                magnitudes: magnitudes,
                frameCount: spectrogram.frameCount,
                binCount: spectrogram.binCount
              ) else {
            return nil
        }
        return separatedSpectrum
    }
}

extension MetalAudioAnalysisProcessor {
    private func separatedMeanSpectra(magnitudes: [Float], frameCount: Int, binCount: Int) -> AudioSeparatedMeanSpectra? {
        guard frameCount > 0, binCount > 0 else {
            return AudioSeparatedMeanSpectra(harmonic: [], percussive: [])
        }

        guard let temporalMedian = makeTemporalMedian17(magnitudes: magnitudes, frameCount: frameCount, binCount: binCount) else {
            return nil
        }

        var harmonicSpectrum = Array(repeating: Float.zero, count: binCount)
        var percussiveSpectrum = Array(repeating: Float.zero, count: binCount)
        var frameMagnitudes = Array(repeating: Float.zero, count: binCount)

        for frameIndex in 0..<frameCount {
            let frameStart = frameIndex * binCount
            frameMagnitudes[0..<binCount] = magnitudes[frameStart..<(frameStart + binCount)]
            let spectralMedian = SpectralDSP.medianFilter(frameMagnitudes, windowSize: 9)
            for binIndex in 0..<binCount {
                let harmonicWeight = temporalMedian[frameStart + binIndex]
                let percussiveWeight = spectralMedian[binIndex]
                let total = max(harmonicWeight + percussiveWeight, 1e-6)
                let magnitude = frameMagnitudes[binIndex]
                harmonicSpectrum[binIndex] += magnitude * harmonicWeight / total
                percussiveSpectrum[binIndex] += magnitude * percussiveWeight / total
            }
        }

        let scale = 1 / Float(max(frameCount, 1))
        for binIndex in 0..<binCount {
            harmonicSpectrum[binIndex] *= scale
            percussiveSpectrum[binIndex] *= scale
        }
        return AudioSeparatedMeanSpectra(harmonic: harmonicSpectrum, percussive: percussiveSpectrum)
    }

    func makeTemporalMedian17(magnitudes: [Float], frameCount: Int, binCount: Int) -> [Float]? {
        #if canImport(Metal)
        guard frameCount > 0, binCount > 0 else { return [] }
        let valueCount = frameCount * binCount
        guard magnitudes.count == valueCount,
              let context = Self.cache.context(),
              let magnitudeBuffer = context.device.makeBuffer(bytes: magnitudes, length: valueCount * MemoryLayout<Float>.stride),
              let outputBuffer = context.device.makeBuffer(length: valueCount * MemoryLayout<Float>.stride),
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        var frameCountValue = UInt32(frameCount)
        var binCountValue = UInt32(binCount)
        encoder.setComputePipelineState(context.temporalMedianPipeline)
        encoder.setBuffer(magnitudeBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBytes(&frameCountValue, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.setBytes(&binCountValue, length: MemoryLayout<UInt32>.stride, index: 3)

        let threadCount = min(context.temporalMedianPipeline.maxTotalThreadsPerThreadgroup, max(context.temporalMedianPipeline.threadExecutionWidth, 1))
        let threadsPerGroup = MTLSize(width: threadCount, height: 1, depth: 1)
        let grid = MTLSize(width: valueCount, height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            return nil
        }

        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: valueCount)
        return Array(UnsafeBufferPointer(start: outputPointer, count: valueCount))
        #else
        return nil
        #endif
    }

    private func makeMagnitudes(spectrogram: Spectrogram) -> [Float]? {
        #if canImport(Metal)
        let valueCount = spectrogram.frameCount * spectrogram.binCount
        guard valueCount > 0,
              let context = Self.cache.context(),
              let realBuffer = context.device.makeBuffer(bytes: spectrogram.real, length: valueCount * MemoryLayout<Float>.stride),
              let imagBuffer = context.device.makeBuffer(bytes: spectrogram.imag, length: valueCount * MemoryLayout<Float>.stride),
              let outputBuffer = context.device.makeBuffer(length: valueCount * MemoryLayout<Float>.stride),
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(context.magnitudePipeline)
        encoder.setBuffer(realBuffer, offset: 0, index: 0)
        encoder.setBuffer(imagBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes([UInt32(valueCount)], length: MemoryLayout<UInt32>.stride, index: 3)

        let threadCount = min(context.magnitudePipeline.maxTotalThreadsPerThreadgroup, max(context.magnitudePipeline.threadExecutionWidth, 1))
        let threadsPerGroup = MTLSize(width: threadCount, height: 1, depth: 1)
        let grid = MTLSize(width: valueCount, height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            return nil
        }

        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: valueCount)
        return Array(UnsafeBufferPointer(start: outputPointer, count: valueCount))
        #else
        return nil
        #endif
    }

    static var metalSource: String {
        """
        #include <metal_stdlib>
        using namespace metal;

        kernel void computeMagnitudes(
            device const float *realValues [[buffer(0)]],
            device const float *imagValues [[buffer(1)]],
            device float *magnitudes [[buffer(2)]],
            constant uint &valueCount [[buffer(3)]],
            uint index [[thread_position_in_grid]]
        ) {
            if (index >= valueCount) {
                return;
            }
            float realValue = realValues[index];
            float imagValue = imagValues[index];
            magnitudes[index] = sqrt(realValue * realValue + imagValue * imagValue);
        }

        kernel void computeTemporalMedian17(
            device const float *magnitudes [[buffer(0)]],
            device float *temporalMedian [[buffer(1)]],
            constant uint &frameCount [[buffer(2)]],
            constant uint &binCount [[buffer(3)]],
            uint index [[thread_position_in_grid]]
        ) {
            uint valueCount = frameCount * binCount;
            if (index >= valueCount) {
                return;
            }

            uint frameIndex = index / binCount;
            uint binIndex = index - frameIndex * binCount;
            uint lower = frameIndex > 8 ? frameIndex - 8 : 0;
            uint upper = min(frameCount - 1, frameIndex + 8);
            uint count = upper - lower + 1;

            float window[17];
            for (uint offset = 0; offset < count; offset++) {
                uint sourceFrame = lower + offset;
                window[offset] = magnitudes[sourceFrame * binCount + binIndex];
            }

            for (uint outer = 1; outer < count; outer++) {
                float value = window[outer];
                int inner = int(outer) - 1;
                while (inner >= 0 && window[inner] > value) {
                    window[inner + 1] = window[inner];
                    inner -= 1;
                }
                window[inner + 1] = value;
            }

            temporalMedian[index] = window[(count - 1) / 2];
        }
        """
    }
}

#if canImport(Metal)
private extension MetalAudioAnalysisProcessor {
    static let cache = MetalAudioAnalysisCache()
}

private final class MetalAudioAnalysisCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedContext: MetalAudioAnalysisContext?

    func context() -> MetalAudioAnalysisContext? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedContext {
            return cachedContext
        }

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: MetalAudioAnalysisProcessor.metalSource, options: nil),
              let magnitudeFunction = library.makeFunction(name: "computeMagnitudes"),
              let temporalMedianFunction = library.makeFunction(name: "computeTemporalMedian17"),
              let magnitudePipeline = try? device.makeComputePipelineState(function: magnitudeFunction),
              let temporalMedianPipeline = try? device.makeComputePipelineState(function: temporalMedianFunction) else {
            return nil
        }

        let context = MetalAudioAnalysisContext(
            device: device,
            commandQueue: commandQueue,
            magnitudePipeline: magnitudePipeline,
            temporalMedianPipeline: temporalMedianPipeline
        )
        cachedContext = context
        return context
    }
}

private final class MetalAudioAnalysisContext {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let magnitudePipeline: any MTLComputePipelineState
    let temporalMedianPipeline: any MTLComputePipelineState

    init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue,
        magnitudePipeline: any MTLComputePipelineState,
        temporalMedianPipeline: any MTLComputePipelineState
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.magnitudePipeline = magnitudePipeline
        self.temporalMedianPipeline = temporalMedianPipeline
    }
}
#endif
