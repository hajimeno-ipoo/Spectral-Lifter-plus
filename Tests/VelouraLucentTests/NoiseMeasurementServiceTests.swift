import Foundation
import Testing
@testable import VelouraLucent

struct NoiseMeasurementServiceTests {
    @Test
    func detectsHumProminenceWithoutTreatingAllLowEnergyAsHum() {
        let clean = testSignal { time in
            Float(sin(2 * Double.pi * 440 * time) * 0.08)
        }
        let hum = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let noise = sin(2 * Double.pi * 60 * time) * 0.025
            return Float(tone + noise)
        }

        let cleanValue = value("hum", in: NoiseMeasurementService.analyze(signal: clean))
        let humValue = value("hum", in: NoiseMeasurementService.analyze(signal: hum))

        #expect(humValue > cleanValue + 4)
    }

    @Test
    func detectsSibilanceAsShortPeakExcess() {
        let smooth = testSignal { time in
            Float(sin(2 * Double.pi * 440 * time) * 0.08)
        }
        let spiky = testSignal { time in
            let base = sin(2 * Double.pi * 440 * time) * 0.08
            let gate = Int(time * 12) % 6 == 0 ? 1.0 : 0.0
            let spike = sin(2 * Double.pi * 7_000 * time) * 0.05 * gate
            return Float(base + spike)
        }

        let smoothValue = value("sibilance", in: NoiseMeasurementService.analyze(signal: smooth))
        let spikyValue = value("sibilance", in: NoiseMeasurementService.analyze(signal: spiky))

        #expect(spikyValue > smoothValue + 4)
    }

    @Test
    func detectsShimmerAsUpperHighShortPeakExcess() {
        let smooth = testSignal { time in
            Float(sin(2 * Double.pi * 440 * time) * 0.08)
        }
        let shimmering = testSignal { time in
            let base = sin(2 * Double.pi * 440 * time) * 0.08
            let gate = Int(time * 16) % 5 == 0 ? 1.0 : 0.0
            let shimmer = sin(2 * Double.pi * 11_500 * time) * 0.04 * gate
            return Float(base + shimmer)
        }

        let smoothValue = value("shimmer", in: NoiseMeasurementService.analyze(signal: smooth))
        let shimmerValue = value("shimmer", in: NoiseMeasurementService.analyze(signal: shimmering))

        #expect(shimmerValue > smoothValue + 4)
    }

    @Test
    func comparableLevelsIgnoreSimpleLoudnessGain() {
        let base = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let hiss = sin(2 * Double.pi * 12_000 * time) * 0.006
            return Float(tone + hiss)
        }
        let louder = AudioSignal(
            channels: [base.channels[0].map { $0 * 2 }],
            sampleRate: base.sampleRate
        )

        let baseHiss = value("hiss", in: NoiseMeasurementService.analyze(signal: base))
        let louderHiss = value("hiss", in: NoiseMeasurementService.analyze(signal: louder))

        #expect(Swift.abs(baseHiss - louderHiss) < 0.7)
    }

    private func value(_ id: String, in snapshot: NoiseMeasurementSnapshot) -> Double {
        snapshot.value(for: id)?.comparableLevelDB ?? -120
    }

    private func testSignal(_ sample: (Double) -> Float) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let channel = (0..<frameCount).map { index in
            sample(Double(index) / sampleRate)
        }
        return AudioSignal(channels: [channel], sampleRate: sampleRate)
    }
}
