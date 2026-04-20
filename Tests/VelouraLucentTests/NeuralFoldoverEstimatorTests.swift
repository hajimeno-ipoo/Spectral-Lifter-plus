import Foundation
import Testing
@testable import VelouraLucent

struct NeuralFoldoverEstimatorTests {
    @Test
    func estimatorRaisesFoldoverForHarmonicDeficit() {
        let estimator = NeuralFoldoverEstimator()
        let richPrediction = estimator.predict(
            features: NeuralFoldoverFeatures(
                harmonicConfidence: 1.0,
                shimmerRatio: 0.10,
                brightnessRatio: 0.34,
                transientAmount: 0.55,
                cutoffFrequency: 12_200,
                noiseAmount: 0.08
            )
        )
        let weakPrediction = estimator.predict(
            features: NeuralFoldoverFeatures(
                harmonicConfidence: 0.18,
                shimmerRatio: 0.34,
                brightnessRatio: 0.58,
                transientAmount: 0.18,
                cutoffFrequency: 15_800,
                noiseAmount: 0.35
            )
        )

        #expect(richPrediction.foldoverMix > weakPrediction.foldoverMix)
        #expect(richPrediction.harshnessGuard < weakPrediction.harshnessGuard)
    }

    @Test
    func estimatorClampsOutputsToSafeRange() {
        let estimator = NeuralFoldoverEstimator()
        let prediction = estimator.predict(
            features: NeuralFoldoverFeatures(
                harmonicConfidence: 3.0,
                shimmerRatio: 1.0,
                brightnessRatio: 1.0,
                transientAmount: 3.0,
                cutoffFrequency: 8_000,
                noiseAmount: 1.0
            )
        )

        #expect((0.04...0.32).contains(prediction.foldoverMix))
        #expect((-0.06...0.16).contains(prediction.airGainBias))
        #expect((-0.04...0.12).contains(prediction.transientBoostBias))
        #expect((0.0...0.72).contains(prediction.harshnessGuard))
    }
}
