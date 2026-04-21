import Foundation
import Testing
@testable import VelouraLucent

struct DenoiseMaskCoefficientTests {
    @Test
    func precomputedCoefficientsMatchInlineFormula() {
        let binCount = 1_025
        let lowBandFloor: Float = 0.16
        let highBandFloor: Float = 0.28
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: lowBandFloor,
            highBandFloor: highBandFloor
        )

        for binIndex in stride(from: 0, to: binCount, by: 17) {
            let normalizedBand = Float(binIndex) / Float(max(binCount - 1, 1))
            expectClose(coefficients.highBandBias[binIndex], 0.94 + powf(normalizedBand, 1.25) * 0.18)
            expectClose(coefficients.granularProfileScale[binIndex], max(0, (normalizedBand - 0.42) / 0.58))
            expectClose(coefficients.thresholdScale[binIndex], 0.92 + powf(normalizedBand, 1.1) * 0.24)
            expectClose(
                coefficients.floor[binIndex],
                lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25)
            )
            expectClose(coefficients.granularThresholdScale[binIndex], 1.1 + normalizedBand * 0.6)
        }
    }

    @Test
    func precomputedMaskMatchesInlineMaskFormula() {
        let binCount = 1_025
        let lowBandFloor: Float = 0.16
        let highBandFloor: Float = 0.28
        let thresholdMultiplier: Float = 1.46
        let granularReduction: Float = 0.26
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: lowBandFloor,
            highBandFloor: highBandFloor
        )

        for binIndex in stride(from: 0, to: binCount, by: 31) {
            let normalizedBand = Float(binIndex) / Float(max(binCount - 1, 1))
            let magnitude: Float = 0.08 + Float(binIndex % 13) * 0.004
            let noiseProfile: Float = 0.02 + Float(binIndex % 7) * 0.002
            let granularProfile: Float = 0.01 + Float(binIndex % 5) * 0.001
            let granularActivity: Float = 0.015 + Float(binIndex % 11) * 0.001
            let transientLift: Float = 0.03

            let inlineThreshold = noiseProfile * thresholdMultiplier * (0.92 + powf(normalizedBand, 1.1) * 0.24)
            let inlineFloor = lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25)
            let inlineRawMask = max(inlineFloor, min(1.0, (magnitude - inlineThreshold) / max(magnitude, 1e-6)))
            let inlineGranularThreshold = granularProfile * (1.1 + normalizedBand * 0.6)
            let inlineGranularExcess = max(0, granularActivity - inlineGranularThreshold)
            let inlineGranularMask = max(
                inlineFloor,
                1 - min(0.72, inlineGranularExcess / max(magnitude + inlineGranularThreshold, 1e-6)) * granularReduction
            )
            let inlineMask = min(1.0, max(inlineRawMask, inlineGranularMask) + transientLift)

            let precomputedThreshold = noiseProfile * thresholdMultiplier * coefficients.thresholdScale[binIndex]
            let precomputedFloor = coefficients.floor[binIndex]
            let precomputedRawMask = max(precomputedFloor, min(1.0, (magnitude - precomputedThreshold) / max(magnitude, 1e-6)))
            let precomputedGranularThreshold = granularProfile * coefficients.granularThresholdScale[binIndex]
            let precomputedGranularExcess = max(0, granularActivity - precomputedGranularThreshold)
            let precomputedGranularMask = max(
                precomputedFloor,
                1 - min(0.72, precomputedGranularExcess / max(magnitude + precomputedGranularThreshold, 1e-6)) * granularReduction
            )
            let precomputedMask = min(1.0, max(precomputedRawMask, precomputedGranularMask) + transientLift)

            expectClose(precomputedMask, inlineMask)
        }
    }

    private func expectClose(_ actual: Float, _ expected: Float, tolerance: Float = 0.000_001) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
