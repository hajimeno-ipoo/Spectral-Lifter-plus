import Testing
@testable import VelouraLucent

struct NoiseCheckReportServiceTests {
    @Test
    func reportShowsInputCorrectedMasteredAndDeltas() throws {
        let input = snapshot(hiss: -48, sibilance: 10, shimmer: -38, mud: -5, hum: 8, rumble: -7, room: -40)
        let corrected = snapshot(hiss: -56, sibilance: 6, shimmer: -44, mud: -8, hum: 4, rumble: -10, room: -46)
        let mastered = snapshot(hiss: -52, sibilance: 9, shimmer: -40, mud: -7, hum: 5, rumble: -9, room: -43)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.input?.severity == .warning)
        #expect(hiss.corrected?.severity == .low)
        #expect(hiss.mastered?.severity == .caution)
        #expect(hiss.correctionDeltaDB == -8)
        #expect(hiss.masteringDeltaDB == 4)
        #expect(hiss.correctionEffectText.contains("大きく改善"))
        #expect(hiss.masteringEffectText.contains("戻りあり"))
        #expect(hiss.recommendedActions.map(\.stage) == [.mastering])
        #expect(hiss.recommendedActions.first?.title.contains("エアー帯域") == true)
    }

    @Test
    func lowSeverityDoesNotShowAdvice() throws {
        let metrics = snapshot(hiss: -62, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: metrics,
            corrected: metrics,
            mastered: metrics,
            correctionSettings: DenoiseStrength.gentle.settings,
            settings: MasteringProfile.natural.settings
        ))

        #expect(report.rows.allSatisfy { $0.recommendedActions.isEmpty })
        #expect(report.severity == .low)
    }

    @Test
    func resolvedNoiseUsesCurrentSeverityInsteadOfInputSeverity() throws {
        let input = snapshot(hiss: -47, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)
        let corrected = snapshot(hiss: -60, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)
        let mastered = snapshot(hiss: -61, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.natural.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.input?.severity == .warning)
        #expect(hiss.corrected?.severity == .low)
        #expect(hiss.mastered?.severity == .low)
        #expect(hiss.severity == .low)
        #expect(report.severity == .low)
    }

    @Test
    func correctedIssueUsesCorrectionAdviceOnly() throws {
        let input = snapshot(hiss: -58, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)
        let corrected = snapshot(hiss: -48, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.recommendedActions.map(\.stage) == [.correction])
        #expect(hiss.recommendedActions.first?.title.contains("補正") == true)
    }

    @Test
    func improvedCorrectionDoesNotShowCorrectionAction() throws {
        let input = snapshot(hiss: -45, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)
        let corrected = snapshot(hiss: -50, sibilance: 3, shimmer: -52, mud: -12, hum: 2, rumble: -14, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let hiss = try #require(report.rows.first { $0.id == "hiss" })
        #expect(hiss.correctionDeltaDB == -5)
        #expect(hiss.recommendedActions.isEmpty)
    }

    @Test
    func shimmerRowIsReportedSeparatelyFromSibilance() throws {
        let metrics = snapshot(hiss: -62, sibilance: 3, shimmer: -38, mud: -12, hum: 2, rumble: -14, room: -52)

        let report = try #require(NoiseCheckReportService.makeReport(
            input: metrics,
            corrected: metrics,
            mastered: metrics,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ))

        let sibilance = try #require(report.rows.first { $0.id == "sibilance" })
        let shimmer = try #require(report.rows.first { $0.id == "shimmer" })
        #expect(sibilance.label == "サ行・歯擦音")
        #expect(shimmer.label == "高域のチラつき")
        #expect(shimmer.severity == .caution)
    }

    @Test
    func reportRequiresAtLeastOneStage() {
        #expect(NoiseCheckReportService.makeReport(
            input: nil,
            corrected: nil,
            mastered: nil,
            correctionSettings: DenoiseStrength.balanced.settings,
            settings: MasteringProfile.streaming.settings
        ) == nil)
    }

    private func snapshot(
        hiss: Double,
        sibilance: Double,
        shimmer: Double,
        mud: Double,
        hum: Double,
        rumble: Double,
        room: Double
    ) -> NoiseMeasurementSnapshot {
        NoiseMeasurementSnapshot(values: [
            value("hiss", "ヒス・シュワシュワ", hiss),
            value("sibilance", "サ行・歯擦音", sibilance),
            value("shimmer", "高域のチラつき", shimmer),
            value("mud", "こもり・低いザラつき", mud),
            value("hum", "ハム・電源ノイズ", hum),
            value("rumble", "低域ゴロゴロ", rumble),
            value("room", "環境音・部屋鳴り", room)
        ])
    }

    private func value(_ id: String, _ label: String, _ level: Double) -> NoiseMeasurementValue {
        NoiseMeasurementValue(id: id, label: label, comparableLevelDB: level, measuredLevelDB: level + 1)
    }
}
