import Foundation

enum NoiseMeasurementService {
    private static let targetComparableLoudness: Float = -23

    static func analyze(signal: AudioSignal) -> NoiseMeasurementSnapshot {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return NoiseMeasurementSnapshot(values: definitions.map {
                NoiseMeasurementValue(id: $0.id, label: $0.label, comparableLevelDB: -120, measuredLevelDB: -120)
            })
        }

        let comparable = loudnessNormalized(mono: mono, sampleRate: signal.sampleRate)
        let comparableLevels = measure(mono: comparable, sampleRate: signal.sampleRate)
        let measuredLevels = measure(mono: mono, sampleRate: signal.sampleRate)

        let values = definitions.map { definition in
            NoiseMeasurementValue(
                id: definition.id,
                label: definition.label,
                comparableLevelDB: comparableLevels[definition.id] ?? -120,
                measuredLevelDB: measuredLevels[definition.id] ?? -120
            )
        }
        return NoiseMeasurementSnapshot(values: values)
    }

    private static var definitions: [(id: String, label: String)] {
        [
            (NoiseMeasurementID.hiss, "ヒス・シュワシュワ"),
            (NoiseMeasurementID.sibilance, "サ行・歯擦音"),
            (NoiseMeasurementID.shimmer, "高域のチラつき"),
            (NoiseMeasurementID.mud, "こもり・低いザラつき"),
            (NoiseMeasurementID.hum, "ハム・電源ノイズ"),
            (NoiseMeasurementID.rumble, "低域ゴロゴロ"),
            (NoiseMeasurementID.room, "環境音・部屋鳴り")
        ]
    }

    private static func loudnessNormalized(mono: [Float], sampleRate: Double) -> [Float] {
        let signal = AudioSignal(channels: [mono], sampleRate: sampleRate)
        let loudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard loudness.isFinite, loudness > -69 else { return mono }
        let gain = powf(10, (targetComparableLoudness - loudness) / 20)
        return mono.map { $0 * gain }
    }

    private static func measure(mono: [Float], sampleRate: Double) -> [String: Double] {
        let fullRMS = rmsDB(mono)
        let high = bandPass(mono, lower: 8_000, upper: min(20_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
        let sibilance = bandPass(mono, lower: 5_000, upper: min(14_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
        let shimmer = bandPass(mono, lower: 8_000, upper: min(14_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
        let lowMid = bandPass(mono, lower: 200, upper: 1_000, sampleRate: sampleRate)
        let low = bandPass(mono, lower: 20, upper: 150, sampleRate: sampleRate)

        return [
            NoiseMeasurementID.hiss: rmsDB(high),
            NoiseMeasurementID.sibilance: transientExcessDB(band: sibilance, sampleRate: sampleRate),
            NoiseMeasurementID.shimmer: transientPeakDB(band: shimmer, sampleRate: sampleRate),
            NoiseMeasurementID.mud: sustainedBandRatioDB(band: lowMid, fullRMSDB: fullRMS),
            NoiseMeasurementID.hum: humProminenceDB(mono: mono, sampleRate: sampleRate),
            NoiseMeasurementID.rumble: rmsDB(low),
            NoiseMeasurementID.room: quietBandNoiseFloorDB(band: mono, reference: mono, sampleRate: sampleRate)
        ]
    }

    private static func bandPass(_ samples: [Float], lower: Double, upper: Double, sampleRate: Double) -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else { return Array(repeating: 0, count: samples.count) }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: lower, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        )
    }

    private static func quietBandNoiseFloorDB(band: [Float], reference: [Float], sampleRate: Double) -> Double {
        let frameSize = max(256, Int(sampleRate * 0.050))
        let hopSize = max(128, Int(sampleRate * 0.025))
        let referenceFrames = frameRMS(reference, frameSize: frameSize, hopSize: hopSize)
        let bandFrames = frameRMS(band, frameSize: frameSize, hopSize: hopSize)
        guard !referenceFrames.isEmpty, referenceFrames.count == bandFrames.count else {
            return rmsDB(band)
        }

        let threshold = percentile(referenceFrames, 0.25)
        let quietValues = zip(referenceFrames, bandFrames).compactMap { reference, band -> Double? in
            reference <= threshold ? band : nil
        }
        return energyAverageDB(quietValues.isEmpty ? bandFrames : quietValues)
    }

    private static func transientExcessDB(band: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = frameRMS(band, frameSize: frameSize, hopSize: hopSize).sorted()
        guard frames.count >= 4 else { return 0 }
        return percentile(frames, 0.95) - percentile(frames, 0.50)
    }

    private static func transientPeakDB(band: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = frameRMS(band, frameSize: frameSize, hopSize: hopSize)
        guard frames.count >= 4 else { return rmsDB(band) }
        return percentile(frames, 0.95)
    }

    private static func sustainedBandRatioDB(band: [Float], fullRMSDB: Double) -> Double {
        rmsDB(band) - fullRMSDB
    }

    private static func humProminenceDB(mono: [Float], sampleRate: Double) -> Double {
        let baseFrequencies = [50.0, 60.0]
        var strongest = 0.0

        for base in baseFrequencies {
            var harmonic = base
            while harmonic <= min(360, sampleRate * 0.5 - 30) {
                let center = sineMagnitudeDB(mono, frequency: harmonic, sampleRate: sampleRate)
                let lower = sineMagnitudeDB(mono, frequency: max(20, harmonic - 17), sampleRate: sampleRate)
                let upper = sineMagnitudeDB(mono, frequency: min(sampleRate * 0.5 - 20, harmonic + 17), sampleRate: sampleRate)
                strongest = max(strongest, center - ((lower + upper) * 0.5))
                harmonic += base
            }
        }

        return strongest
    }

    private static func sineMagnitudeDB(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return -120 }
        var real = 0.0
        var imag = 0.0
        let angular = 2 * Double.pi * frequency / sampleRate
        for index in samples.indices {
            let phase = angular * Double(index)
            let sample = Double(samples[index])
            real += sample * cos(phase)
            imag -= sample * sin(phase)
        }
        let magnitude = sqrt(real * real + imag * imag) * 2 / Double(samples.count)
        return 20 * log10(max(magnitude, 1e-12))
    }

    private static func frameRMS(_ samples: [Float], frameSize: Int, hopSize: Int) -> [Double] {
        guard !samples.isEmpty else { return [] }
        if samples.count <= frameSize {
            return [rmsDB(samples)]
        }

        var values: [Double] = []
        var start = 0
        while start + frameSize <= samples.count {
            let frame = samples[start..<(start + frameSize)]
            let energy = frame.reduce(0.0) { partial, sample in
                partial + Double(sample * sample)
            } / Double(frameSize)
            values.append(10 * log10(max(energy, 1e-12)))
            start += hopSize
        }
        return values
    }

    private static func rmsDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        let energy = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return 10 * log10(max(energy, 1e-12))
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(round(Double(sorted.count - 1) * percentile))))
        return sorted[index]
    }

    private static func energyAverageDB(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return -120 }
        let energy = values.reduce(0.0) { partial, value in
            partial + pow(10, value / 10)
        } / Double(values.count)
        return 10 * log10(max(energy, 1e-12))
    }
}
