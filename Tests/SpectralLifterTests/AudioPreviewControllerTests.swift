import Testing
@testable import SpectralLifter

@MainActor
struct AudioPreviewControllerTests {
    @Test
    func comparisonPairSwitchesTargets() {
        let controller = AudioPreviewController()

        controller.setComparisonPair(.inputVsCorrected)

        #expect(controller.comparisonTarget(for: .a) == .input)
        #expect(controller.comparisonTarget(for: .b) == .corrected)

        controller.setComparisonPair(.correctedVsMastered)

        #expect(controller.comparisonTarget(for: .a) == .corrected)
        #expect(controller.comparisonTarget(for: .b) == .mastered)
    }
}
