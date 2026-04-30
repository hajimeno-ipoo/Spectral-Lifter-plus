import Testing
@testable import VelouraLucent

struct AudioQualityReportServiceTests {
    @Test
    func normalMetricsReturnNoItems() {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.0,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -18.3,
            truePeakDBFS: -0.8,
            stereoWidth: 0.86,
            crestFactorDB: 9.2,
            hf12Ratio: 0.13,
            hf16Ratio: 0.06,
            hf18Ratio: 0.03
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -16.5,
            truePeakDBFS: -0.5,
            stereoWidth: 0.92,
            crestFactorDB: 8.5,
            hf12Ratio: 0.16,
            hf16Ratio: 0.08,
            hf18Ratio: 0.04
        )

        let report = AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        )

        #expect(report.items.isEmpty)
        #expect(report.severity == .info)
    }

    @Test
    func riskyChangesReturnJapaneseWarnings() {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.0,
            stereoWidth: 0.80,
            crestFactorDB: 12.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.01
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -19.4,
            truePeakDBFS: -0.8,
            stereoWidth: 1.05,
            crestFactorDB: 8.5,
            hf12Ratio: 0.13,
            hf16Ratio: 0.05,
            hf18Ratio: 0.02
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -13.8,
            truePeakDBFS: -0.1,
            stereoWidth: 1.35,
            crestFactorDB: 5.0,
            hf12Ratio: 0.30,
            hf16Ratio: 0.16,
            hf18Ratio: 0.09
        )

        let report = AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        )

        #expect(report.severity == .warning)
        #expect(report.items.contains { $0.title == "補正後の音量感が下がっています" })
        #expect(report.items.contains { $0.title == "マスタリング後のピークが高すぎます" })
        #expect(report.items.contains { $0.title == "マスタリング後の18kHz以上が増えています" })
        #expect(report.items.contains { $0.title == "補正後のステレオ幅が大きく変わっています" })
        #expect(report.items.contains { $0.title == "マスタリング後の音の起伏が小さくなっています" })
        #expect(report.items.contains { $0.title == "最終版の音量感が大きく上がっています" })
    }

    private func makeSnapshot(
        integratedLoudnessLUFS: Double,
        truePeakDBFS: Double,
        stereoWidth: Double,
        crestFactorDB: Double,
        hf12Ratio: Double,
        hf16Ratio: Double,
        hf18Ratio: Double
    ) -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            peakDBFS: truePeakDBFS - 0.2,
            rmsDBFS: truePeakDBFS - crestFactorDB,
            crestFactorDB: crestFactorDB,
            loudnessRangeLU: 3.0,
            integratedLoudnessLUFS: integratedLoudnessLUFS,
            truePeakDBFS: truePeakDBFS,
            stereoWidth: stereoWidth,
            stereoCorrelation: 0.8,
            harshnessScore: 0.2,
            centroidHz: 2_500,
            hf12Ratio: hf12Ratio,
            hf16Ratio: hf16Ratio,
            hf18Ratio: hf18Ratio,
            bandEnergies: [],
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        )
    }
}
