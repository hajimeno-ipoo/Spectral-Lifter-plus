import Foundation

enum NoiseCheckReportService {
    static func makeReport(
        input: NoiseMeasurementSnapshot?,
        corrected: NoiseMeasurementSnapshot?,
        mastered: NoiseMeasurementSnapshot?,
        correctionSettings: CorrectionSettings,
        settings: MasteringSettings
    ) -> NoiseCheckReport? {
        guard input != nil || corrected != nil || mastered != nil else { return nil }

        let definitions = noiseDefinitions(correctionSettings: correctionSettings, masteringSettings: settings)
        let rows = definitions.map { definition in
            let inputValue = input.flatMap { value(for: definition, snapshot: $0) }
            let correctedValue = corrected.flatMap { value(for: definition, snapshot: $0) }
            let masteredValue = mastered.flatMap { value(for: definition, snapshot: $0) }
            let correctionDelta = delta(from: inputValue, to: correctedValue)
            let masteringDelta = delta(from: correctedValue, to: masteredValue)
            let masteringWorsened = (masteringDelta ?? 0) >= definition.masteringWorseningCautionDB
            let severity = maxSeverity([
                currentSeverity(input: inputValue, corrected: correctedValue, mastered: masteredValue),
                masteringWorsened ? .caution : nil
            ])

            return NoiseCheckRow(
                id: definition.id,
                label: definition.label,
                input: inputValue,
                corrected: correctedValue,
                mastered: masteredValue,
                correctionDeltaDB: correctionDelta,
                masteringDeltaDB: masteringDelta,
                severity: severity,
                correctionEffectText: correctionEffectText(correctionDelta),
                masteringEffectText: masteringEffectText(masteringDelta, warningDelta: definition.masteringWorseningCautionDB),
                recommendedActions: recommendedActions(
                    for: definition,
                    input: inputValue,
                    corrected: correctedValue,
                    mastered: masteredValue,
                    correctionDelta: correctionDelta,
                    masteringDelta: masteringDelta
                )
            )
        }

        return NoiseCheckReport(rows: rows)
    }

    private static func value(for definition: NoiseDefinition, snapshot: NoiseMeasurementSnapshot) -> NoiseCheckValue? {
        guard let measurement = snapshot.value(for: definition.id) else { return nil }
        return NoiseCheckValue(
            levelDB: measurement.comparableLevelDB,
            measuredLevelDB: measurement.measuredLevelDB,
            severity: severity(levelDB: measurement.comparableLevelDB, caution: definition.cautionDB, warning: definition.warningDB)
        )
    }

    private static func delta(from reference: NoiseCheckValue?, to target: NoiseCheckValue?) -> Double? {
        guard let reference, let target else { return nil }
        return target.levelDB - reference.levelDB
    }

    private static func severity(levelDB: Double, caution: Double, warning: Double) -> NoiseCheckSeverity {
        if levelDB >= warning {
            return .warning
        }
        if levelDB >= caution {
            return .caution
        }
        return .low
    }

    private static func maxSeverity(_ values: [NoiseCheckSeverity?]) -> NoiseCheckSeverity {
        let compact = values.compactMap { $0 }
        if compact.contains(.warning) {
            return .warning
        }
        if compact.contains(.caution) {
            return .caution
        }
        return .low
    }

    private static func currentSeverity(
        input: NoiseCheckValue?,
        corrected: NoiseCheckValue?,
        mastered: NoiseCheckValue?
    ) -> NoiseCheckSeverity {
        mastered?.severity ?? corrected?.severity ?? input?.severity ?? .low
    }

    private static func correctionEffectText(_ delta: Double?) -> String {
        guard let delta else { return "補正: 未実行" }
        if delta <= -3.0 {
            return "補正: 大きく改善 \(formatDelta(delta))"
        }
        if delta <= -1.0 {
            return "補正: 改善 \(formatDelta(delta))"
        }
        if delta < 1.0 {
            return "補正: ほぼ維持 \(formatDelta(delta))"
        }
        return "補正: 増加 \(formatDelta(delta))"
    }

    private static func masteringEffectText(_ delta: Double?, warningDelta: Double) -> String {
        guard let delta else { return "仕上げ: 未実行" }
        if delta <= -1.0 {
            return "仕上げ: さらに改善 \(formatDelta(delta))"
        }
        if delta < 0.5 {
            return "仕上げ: 維持 \(formatDelta(delta))"
        }
        if delta < warningDelta {
            return "仕上げ: 少し戻り \(formatDelta(delta))"
        }
        return "仕上げ: 戻りあり \(formatDelta(delta))"
    }

    private static func recommendedActions(
        for definition: NoiseDefinition,
        input: NoiseCheckValue?,
        corrected: NoiseCheckValue?,
        mastered: NoiseCheckValue?,
        correctionDelta: Double?,
        masteringDelta: Double?
    ) -> [NoiseCheckAction] {
        let correctionWeak = corrected.map { $0.severity != .low } == true && (correctionDelta ?? 0) > -1.0
        let correctionWorse = (correctionDelta ?? 0) >= 1.0
        let masteringReturned = (masteringDelta ?? 0) >= definition.masteringWorseningCautionDB
        let masteringStillHigh = mastered.map { $0.severity != .low } == true && (masteringDelta ?? 0) >= 0.5
        let inputWasHigh = input.map { $0.severity != .low } == true

        var actions: [NoiseCheckAction] = []
        if masteringReturned || masteringStillHigh {
            actions.append(definition.masteringAction)
        }
        if actions.count < 2 && (correctionWorse || correctionWeak || (corrected == nil && inputWasHigh)) {
            actions.append(definition.correctionAction)
        }
        return Array(actions.prefix(2))
    }

    private static func noiseDefinitions(correctionSettings: CorrectionSettings, masteringSettings: MasteringSettings) -> [NoiseDefinition] {
        [
            NoiseDefinition(
                id: "hiss",
                label: "ヒス・シュワシュワ",
                cautionDB: -54,
                warningDB: -48,
                masteringWorseningCautionDB: 2.0,
                correctionAction: action(
                    id: "hiss-correction",
                    stage: .correction,
                    title: "補正: 高域の自然さ / ノイズ検出しきい値",
                    detail: "\(formatPercent(correctionSettings.highNaturalness)) → \(formatPercent(min(1.0, correctionSettings.highNaturalness + 0.16))) / \(formatPercent(correctionSettings.noiseDetectionSensitivity)) → \(formatPercent(min(1.0, correctionSettings.noiseDetectionSensitivity + 0.12)))"
                ),
                masteringAction: action(
                    id: "hiss-mastering",
                    stage: .mastering,
                    title: "マスタリング: エアー帯域",
                    detail: "\(format(masteringSettings.highShelfGain)) → \(format(max(-0.20, masteringSettings.highShelfGain - 0.18)))"
                )
            ),
            NoiseDefinition(
                id: "sibilance",
                label: "サ行・歯擦音",
                cautionDB: 8,
                warningDB: 12,
                masteringWorseningCautionDB: 2.0,
                correctionAction: action(
                    id: "sibilance-correction",
                    stage: .correction,
                    title: "補正: 高域の自然さ / エアー補完",
                    detail: "\(formatPercent(correctionSettings.highNaturalness)) → \(formatPercent(min(1.0, correctionSettings.highNaturalness + 0.16))) / \(formatPercent(correctionSettings.airRepair)) → \(formatPercent(max(0, correctionSettings.airRepair - 0.12)))"
                ),
                masteringAction: action(
                    id: "sibilance-mastering",
                    stage: .mastering,
                    title: "マスタリング: ハーシュネス抑制",
                    detail: "\(formatPercent(masteringSettings.deEsserAmount)) → \(formatPercent(min(1.0, masteringSettings.deEsserAmount + 0.10)))"
                )
            ),
            NoiseDefinition(
                id: "shimmer",
                label: "高域のチラつき",
                cautionDB: -42,
                warningDB: -36,
                masteringWorseningCautionDB: 1.5,
                correctionAction: action(
                    id: "shimmer-correction",
                    stage: .correction,
                    title: "補正: 高域の自然さ / エアー補完",
                    detail: "\(formatPercent(correctionSettings.highNaturalness)) → \(formatPercent(min(1.0, correctionSettings.highNaturalness + 0.12))) / \(formatPercent(correctionSettings.airRepair)) → \(formatPercent(max(0, correctionSettings.airRepair - 0.10)))"
                ),
                masteringAction: action(
                    id: "shimmer-mastering",
                    stage: .mastering,
                    title: "マスタリング: エアー帯域 / ハーシュネス抑制",
                    detail: "\(format(masteringSettings.highShelfGain)) → \(format(max(-0.20, masteringSettings.highShelfGain - 0.12))) / \(formatPercent(masteringSettings.deEsserAmount)) → \(formatPercent(min(1.0, masteringSettings.deEsserAmount + 0.08)))"
                )
            ),
            NoiseDefinition(
                id: "mud",
                label: "こもり・低いザラつき",
                cautionDB: -7,
                warningDB: -4,
                masteringWorseningCautionDB: 1.8,
                correctionAction: action(
                    id: "mud-correction",
                    stage: .correction,
                    title: "補正: 中低域整理",
                    detail: "\(formatPercent(correctionSettings.lowMidCleanup)) → \(formatPercent(min(1.0, correctionSettings.lowMidCleanup + 0.16)))"
                ),
                masteringAction: action(
                    id: "mud-mastering",
                    stage: .mastering,
                    title: "マスタリング: 中低域",
                    detail: "\(format(masteringSettings.lowMidGain)) → \(format(masteringSettings.lowMidGain - 0.10))"
                )
            ),
            NoiseDefinition(
                id: "hum",
                label: "ハム・電源ノイズ",
                cautionDB: 6,
                warningDB: 10,
                masteringWorseningCautionDB: 2.0,
                correctionAction: action(
                    id: "hum-correction",
                    stage: .correction,
                    title: "補正: ノイズ検出しきい値 / 低域整理",
                    detail: "\(formatPercent(correctionSettings.noiseDetectionSensitivity)) → \(formatPercent(min(1.0, correctionSettings.noiseDetectionSensitivity + 0.16))) / \(formatPercent(correctionSettings.lowCleanup)) → \(formatPercent(min(1.0, correctionSettings.lowCleanup + 0.14)))"
                ),
                masteringAction: action(
                    id: "hum-mastering",
                    stage: .mastering,
                    title: "マスタリング: 低域",
                    detail: "\(format(masteringSettings.lowShelfGain)) → \(format(max(0, masteringSettings.lowShelfGain - 0.16)))"
                )
            ),
            NoiseDefinition(
                id: "rumble",
                label: "低域ゴロゴロ",
                cautionDB: -9,
                warningDB: -5,
                masteringWorseningCautionDB: 1.8,
                correctionAction: action(
                    id: "rumble-correction",
                    stage: .correction,
                    title: "補正: 低域整理",
                    detail: "\(formatPercent(correctionSettings.lowCleanup)) → \(formatPercent(min(1.0, correctionSettings.lowCleanup + 0.18)))"
                ),
                masteringAction: action(
                    id: "rumble-mastering",
                    stage: .mastering,
                    title: "マスタリング: 低域",
                    detail: "\(format(masteringSettings.lowShelfGain)) → \(format(max(0, masteringSettings.lowShelfGain - 0.16)))"
                )
            ),
            NoiseDefinition(
                id: "room",
                label: "環境音・部屋鳴り",
                cautionDB: -42,
                warningDB: -36,
                masteringWorseningCautionDB: 2.0,
                correctionAction: action(
                    id: "room-correction",
                    stage: .correction,
                    title: "補正: 補正の強さ / 原音保持",
                    detail: "\(formatPercent(correctionSettings.correctionIntensity)) → \(formatPercent(min(1.0, correctionSettings.correctionIntensity + 0.14))) / \(formatPercent(correctionSettings.originalRetention)) → \(formatPercent(max(0, correctionSettings.originalRetention - 0.10)))"
                ),
                masteringAction: action(
                    id: "room-mastering",
                    stage: .mastering,
                    title: "マスタリング: ダイナミクス保持",
                    detail: "\(format(masteringSettings.dynamicsRetention)) → \(format(min(1.0, masteringSettings.dynamicsRetention + 0.10)))"
                )
            )
        ]
    }

    private static func action(id: String, stage: NoiseCheckAction.Stage, title: String, detail: String) -> NoiseCheckAction {
        NoiseCheckAction(id: id, stage: stage, title: title, detail: detail)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private static func formatPercent(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func formatDelta(_ value: Double) -> String {
        String(format: value >= 0 ? "+%.1f dB" : "%.1f dB", value)
    }
}

private struct NoiseDefinition {
    let id: String
    let label: String
    let cautionDB: Double
    let warningDB: Double
    let masteringWorseningCautionDB: Double
    let correctionAction: NoiseCheckAction
    let masteringAction: NoiseCheckAction
}
