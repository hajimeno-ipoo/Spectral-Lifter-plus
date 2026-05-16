import Foundation

enum NoiseMeasurementService {
    static func analyze(signal: AudioSignal) -> NoiseMeasurementSnapshot {
        analyze(signal: signal, definitions: definitions)
    }

    static func analyze(signal: AudioSignal, ids requestedIDs: [String]) -> NoiseMeasurementSnapshot {
        let requestedIDSet = Set(requestedIDs)
        let selectedDefinitions = definitions.filter { requestedIDSet.contains($0.id) }
        return analyze(signal: signal, definitions: selectedDefinitions)
    }

    private static func analyze(signal: AudioSignal, definitions selectedDefinitions: [NoiseMeasurementDefinition]) -> NoiseMeasurementSnapshot {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return NoiseMeasurementSnapshot(values: selectedDefinitions.map {
                NoiseMeasurementValue(
                    id: $0.id,
                    label: $0.label,
                    comparableLevelDB: -120,
                    measuredLevelDB: -120,
                    unitLabel: $0.unitLabel,
                    measurementDescription: $0.measurementDescription,
                    lowerIsBetter: $0.lowerIsBetter
                )
            })
        }

        let requestedIDs = Set(selectedDefinitions.map(\.id))
        let measuredLevels = measure(mono: mono, sampleRate: signal.sampleRate, ids: requestedIDs)

        let values = selectedDefinitions.map { definition in
            let measured = measuredLevels[definition.id] ?? -120
            return NoiseMeasurementValue(
                id: definition.id,
                label: definition.label,
                comparableLevelDB: measured,
                measuredLevelDB: measured,
                unitLabel: definition.unitLabel,
                measurementDescription: definition.measurementDescription,
                lowerIsBetter: definition.lowerIsBetter
            )
        }
        return NoiseMeasurementSnapshot(values: values)
    }

    private static var definitions: [NoiseMeasurementDefinition] {
        [
            NoiseMeasurementDefinition(id: NoiseMeasurementID.hiss, label: "ヒス・シュワシュワ", unitLabel: "dBFS", measurementDescription: "静かな区間の8kHz以上の床"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.sibilance, label: "サ行・歯擦音", unitLabel: "dB", measurementDescription: "5〜9kHzの短時間突出"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.shimmer, label: "高域のチラつき", unitLabel: "dBFS", measurementDescription: "静かな区間の10〜16kHz床"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.mud, label: "こもり・低いザラつき", unitLabel: "dB", measurementDescription: "300Hz〜1kHzの全体比"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.hum, label: "ハム・電源ノイズ", unitLabel: "dB", measurementDescription: "50/60Hzと倍音の周辺比"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.rumble, label: "低域ゴロゴロ", unitLabel: "dBFS", measurementDescription: "静かな区間の20〜150Hz床"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.room, label: "環境音・部屋鳴り", unitLabel: "dBFS", measurementDescription: "静かな区間の100Hz〜8kHz床")
        ]
    }

    private static func measure(mono: [Float], sampleRate: Double, ids requestedIDs: Set<String>) -> [String: Double] {
        var measured: [String: Double] = [:]

        if requestedIDs.contains(NoiseMeasurementID.hiss) {
            let high = bandPass(mono, lower: 8_000, upper: min(20_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
            measured[NoiseMeasurementID.hiss] = quietBandNoiseFloorDB(band: high, reference: mono, sampleRate: sampleRate)
        }

        if requestedIDs.contains(NoiseMeasurementID.sibilance) {
            let sibilance = bandPass(mono, lower: 5_000, upper: min(9_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
            measured[NoiseMeasurementID.sibilance] = transientExcessDB(band: sibilance, sampleRate: sampleRate)
        }

        if requestedIDs.contains(NoiseMeasurementID.shimmer) {
            let shimmer = bandPass(mono, lower: 10_000, upper: min(16_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
            measured[NoiseMeasurementID.shimmer] = quietBandNoiseFloorDB(band: shimmer, reference: mono, sampleRate: sampleRate)
        }

        if requestedIDs.contains(NoiseMeasurementID.mud) {
            let fullRMS = rmsDB(mono)
            let lowMid = bandPass(mono, lower: 300, upper: 1_000, sampleRate: sampleRate)
            measured[NoiseMeasurementID.mud] = sustainedBandRatioDB(band: lowMid, fullRMSDB: fullRMS)
        }

        if requestedIDs.contains(NoiseMeasurementID.hum) {
            measured[NoiseMeasurementID.hum] = humProminenceDB(mono: mono, sampleRate: sampleRate)
        }

        if requestedIDs.contains(NoiseMeasurementID.rumble) {
            let low = bandPass(mono, lower: 20, upper: 150, sampleRate: sampleRate)
            measured[NoiseMeasurementID.rumble] = quietBandNoiseFloorDB(band: low, reference: mono, sampleRate: sampleRate)
        }

        if requestedIDs.contains(NoiseMeasurementID.room) {
            let room = bandPass(mono, lower: 100, upper: min(8_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
            measured[NoiseMeasurementID.room] = quietBandNoiseFloorDB(band: room, reference: mono, sampleRate: sampleRate)
        }

        return measured
    }

    private static func bandPass(_ samples: [Float], lower: Double, upper: Double, sampleRate: Double) -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else { return Array(repeating: 0, count: samples.count) }
        var filtered = samples
        for _ in 0..<4 {
            filtered = SpectralDSP.highPass(filtered, cutoff: lower, sampleRate: sampleRate)
            filtered = SpectralDSP.lowPass(filtered, cutoff: upper, sampleRate: sampleRate)
        }
        return filtered
    }

    private static func quietBandNoiseFloorDB(band: [Float], reference: [Float], sampleRate: Double) -> Double {
        let frameSize = max(512, Int(sampleRate * 0.100))
        let hopSize = max(256, Int(sampleRate * 0.050))
        let referenceFrames = frameRMS(reference, frameSize: frameSize, hopSize: hopSize)
        let bandFrames = frameRMS(band, frameSize: frameSize, hopSize: hopSize)
        guard !referenceFrames.isEmpty, referenceFrames.count == bandFrames.count else {
            return rmsDB(band)
        }

        let threshold = percentile(referenceFrames, 0.20)
        let quietValues = zip(referenceFrames, bandFrames).compactMap { reference, band -> Double? in
            reference <= threshold ? band : nil
        }
        return percentile(quietValues.isEmpty ? bandFrames : quietValues, 0.20)
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
        let spectrogram = SpectralDSP.stft(mono, fftSize: 8192, hopSize: 4096)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)

        for base in baseFrequencies {
            var harmonic = base
            while harmonic <= min(360, sampleRate * 0.5 - 30) {
                let spectral = harmonicProminenceDB(
                    spectrogram: spectrogram,
                    frequency: harmonic,
                    frequencyStep: frequencyStep
                )
                let sine = windowedSineProminenceDB(mono: mono, frequency: harmonic, sampleRate: sampleRate)
                strongest = max(strongest, spectral, sine)
                harmonic += base
            }
        }

        return strongest
    }

    private static func windowedSineProminenceDB(mono: [Float], frequency: Double, sampleRate: Double) -> Double {
        let frameSize = max(2048, Int(sampleRate * 0.50))
        let hopSize = max(1024, frameSize / 2)
        guard mono.count >= frameSize else { return 0 }

        var values: [Double] = []
        var start = 0
        while start + frameSize <= mono.count {
            let frame = Array(mono[start..<(start + frameSize)])
            let center = sineMagnitudeDB(frame, frequency: frequency, sampleRate: sampleRate)
            let surrounding = [
                sineMagnitudeDB(frame, frequency: max(20, frequency - 23), sampleRate: sampleRate),
                sineMagnitudeDB(frame, frequency: max(20, frequency - 17), sampleRate: sampleRate),
                sineMagnitudeDB(frame, frequency: min(sampleRate * 0.5 - 20, frequency + 17), sampleRate: sampleRate),
                sineMagnitudeDB(frame, frequency: min(sampleRate * 0.5 - 20, frequency + 23), sampleRate: sampleRate)
            ]
            values.append(center - median(surrounding))
            start += hopSize
        }

        return max(0, percentile(values, 0.50))
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

    private static func harmonicProminenceDB(spectrogram: Spectrogram, frequency: Double, frequencyStep: Double) -> Double {
        let centerBin = max(1, min(spectrogram.binCount - 2, Int(round(frequency / frequencyStep))))
        let centerRadius = max(1, Int(round(1.5 / frequencyStep)))
        let excludeRadius = max(centerRadius + 1, Int(round(3.0 / frequencyStep)))
        let searchRadius = max(excludeRadius + 1, Int(round(18.0 / frequencyStep)))
        var frameProminences: [Double] = []

        for frameIndex in 0..<spectrogram.frameCount {
            let frameOffset = frameIndex * spectrogram.binCount
            var centerMagnitudes: [Double] = []
            var surroundingMagnitudes: [Double] = []
            let lower = max(1, centerBin - searchRadius)
            let upper = min(spectrogram.binCount - 1, centerBin + searchRadius)

            for bin in lower...upper {
                let index = frameOffset + bin
                let real = Double(spectrogram.real[index])
                let imag = Double(spectrogram.imag[index])
                let magnitude = sqrt(real * real + imag * imag)
                let distance = abs(bin - centerBin)
                if distance <= centerRadius {
                    centerMagnitudes.append(magnitude)
                } else if distance > excludeRadius {
                    surroundingMagnitudes.append(magnitude)
                }
            }

            guard !centerMagnitudes.isEmpty, surroundingMagnitudes.count >= 3 else { continue }
            let center = centerMagnitudes.reduce(0, +) / Double(centerMagnitudes.count)
            let surrounding = median(surroundingMagnitudes)
            frameProminences.append(20 * log10(max(center, 1e-12) / max(surrounding, 1e-12)))
        }

        guard !frameProminences.isEmpty else { return 0 }
        return max(0, percentile(frameProminences, 0.75))
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

    private static func median(_ values: [Double]) -> Double {
        percentile(values, 0.50)
    }
}

private struct NoiseMeasurementDefinition {
    let id: String
    let label: String
    let unitLabel: String
    let measurementDescription: String
    let lowerIsBetter: Bool

    init(
        id: String,
        label: String,
        unitLabel: String,
        measurementDescription: String,
        lowerIsBetter: Bool = true
    ) {
        self.id = id
        self.label = label
        self.unitLabel = unitLabel
        self.measurementDescription = measurementDescription
        self.lowerIsBetter = lowerIsBetter
    }
}
