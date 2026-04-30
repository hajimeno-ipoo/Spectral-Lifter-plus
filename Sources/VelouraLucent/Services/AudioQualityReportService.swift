import Foundation

enum AudioQualityReportSeverity: Int, Sendable, Comparable {
    case info
    case caution
    case warning

    static func < (lhs: AudioQualityReportSeverity, rhs: AudioQualityReportSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AudioQualityReportItem: Sendable, Equatable {
    let severity: AudioQualityReportSeverity
    let title: String
    let detail: String
}

struct AudioQualityReport: Sendable, Equatable {
    let items: [AudioQualityReportItem]

    var severity: AudioQualityReportSeverity {
        items.map(\.severity).max() ?? .info
    }
}

enum AudioQualityReportService {
    static func makeReport(
        input: AudioMetricSnapshot?,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> AudioQualityReport {
        var items: [AudioQualityReportItem] = []

        if let input, let corrected {
            items.append(contentsOf: compare(reference: input, target: corrected, stageName: "補正後"))
        }

        if let corrected, let mastered {
            items.append(contentsOf: compare(reference: corrected, target: mastered, stageName: "マスタリング後"))
        }

        if let input, let mastered {
            items.append(contentsOf: compareFinal(input: input, mastered: mastered))
        }

        return AudioQualityReport(items: items)
    }

    private static func compare(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        stageName: String
    ) -> [AudioQualityReportItem] {
        var items: [AudioQualityReportItem] = []

        let loudnessDrop = reference.integratedLoudnessLUFS - target.integratedLoudnessLUFS
        if loudnessDrop >= 1.0 {
            items.append(.warning(
                "\(stageName)の音量感が下がっています",
                "Integrated Loudness が \(format(loudnessDrop)) LU 下がっています。"
            ))
        }

        if target.truePeakDBFS > -0.3 {
            items.append(.warning(
                "\(stageName)のピークが高すぎます",
                "True Peak が \(format(target.truePeakDBFS)) dBFS です。"
            ))
        }

        items.append(contentsOf: highFrequencyItems(reference: reference, target: target, stageName: stageName))

        let widthChange = target.stereoWidth - reference.stereoWidth
        if abs(widthChange) >= 0.20 {
            items.append(.caution(
                "\(stageName)のステレオ幅が大きく変わっています",
                "Stereo Width が \(formatSigned(widthChange)) 変化しています。"
            ))
        }

        let crestChange = target.crestFactorDB - reference.crestFactorDB
        if crestChange <= -3.0 {
            items.append(.caution(
                "\(stageName)の音の起伏が小さくなっています",
                "Crest Factor が \(format(abs(crestChange))) dB 下がっています。"
            ))
        } else if crestChange >= 4.0 {
            items.append(.caution(
                "\(stageName)の音の起伏が大きく変わっています",
                "Crest Factor が \(format(crestChange)) dB 上がっています。"
            ))
        }

        return items
    }

    private static func compareFinal(input: AudioMetricSnapshot, mastered: AudioMetricSnapshot) -> [AudioQualityReportItem] {
        var items: [AudioQualityReportItem] = []
        let loudnessIncrease = mastered.integratedLoudnessLUFS - input.integratedLoudnessLUFS

        if loudnessIncrease >= 4.0 {
            items.append(.caution(
                "最終版の音量感が大きく上がっています",
                "入力より Integrated Loudness が \(format(loudnessIncrease)) LU 上がっています。"
            ))
        }

        return items
    }

    private static func highFrequencyItems(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        stageName: String
    ) -> [AudioQualityReportItem] {
        [
            highFrequencyItem(
                label: "12kHz以上",
                reference: reference.hf12Ratio,
                target: target.hf12Ratio,
                stageName: stageName,
                cautionIncrease: 0.08,
                warningIncrease: 0.14
            ),
            highFrequencyItem(
                label: "16kHz以上",
                reference: reference.hf16Ratio,
                target: target.hf16Ratio,
                stageName: stageName,
                cautionIncrease: 0.05,
                warningIncrease: 0.10
            ),
            highFrequencyItem(
                label: "18kHz以上",
                reference: reference.hf18Ratio,
                target: target.hf18Ratio,
                stageName: stageName,
                cautionIncrease: 0.03,
                warningIncrease: 0.06
            )
        ].compactMap { $0 }
    }

    private static func highFrequencyItem(
        label: String,
        reference: Double,
        target: Double,
        stageName: String,
        cautionIncrease: Double,
        warningIncrease: Double
    ) -> AudioQualityReportItem? {
        let increase = target - reference
        guard increase >= cautionIncrease else {
            return nil
        }

        let severity: AudioQualityReportSeverity = increase >= warningIncrease ? .warning : .caution
        return AudioQualityReportItem(
            severity: severity,
            title: "\(stageName)の\(label)が増えています",
            detail: "\(label) が \(formatPercent(increase)) 増えています。"
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func formatSigned(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

private extension AudioQualityReportItem {
    static func warning(_ title: String, _ detail: String) -> AudioQualityReportItem {
        AudioQualityReportItem(severity: .warning, title: title, detail: detail)
    }

    static func caution(_ title: String, _ detail: String) -> AudioQualityReportItem {
        AudioQualityReportItem(severity: .caution, title: title, detail: detail)
    }
}
