import Testing
@testable import VelouraLucent

struct MasteringProfileTests {
    @Test
    func profilesExposeDifferentSettings() {
        let naturalProfile = MasteringProfile.natural
        let streamingProfile = MasteringProfile.streaming
        let forwardProfile = MasteringProfile.forward

        let natural = naturalProfile.settings
        let streaming = streamingProfile.settings
        let forward = forwardProfile.settings

        #expect(natural.targetLoudness < streaming.targetLoudness)
        #expect(streaming.targetLoudness < forward.targetLoudness)
        #expect(streaming.targetLoudness == -16.7)
        #expect(forward.targetLoudness <= -14.8)
        #expect(streaming.lowShelfGain == 0.72)
        #expect(streaming.lowMidGain == -0.34)
        #expect(streaming.highShelfGain == 0.48)
        #expect(natural.saturationAmount < forward.saturationAmount)
        #expect(forward.saturationAmount <= 0.12)
        #expect(natural.dynamicsRetention > streaming.dynamicsRetention)
        #expect(streaming.dynamicsRetention > forward.dynamicsRetention)
        #expect(natural.finishingIntensity < streaming.finishingIntensity)
        #expect(streaming.finishingIntensity < forward.finishingIntensity)
        #expect(streaming.stereoWidth >= natural.stereoWidth)
        #expect(natural.multibandCompression.low.ratio < forward.multibandCompression.low.ratio)
        #expect(streaming.multibandCompression.high.attackMs < natural.multibandCompression.high.attackMs)
        #expect(natural.deEsserAmount < forward.deEsserAmount)
        #expect(streaming.lowMidGain <= natural.lowMidGain)
        #expect(naturalProfile.title == "自然")
        #expect(streamingProfile.title == "聴きやすく整える")
        #expect(forwardProfile.title == "押し出し強め")
    }

    @Test
    func aggressiveMasteringSettingsExposeWarningsWithoutChangingRanges() {
        var settings = MasteringProfile.streaming.settings

        #expect(settings.aggressiveSettingWarnings.isEmpty)

        settings.targetLoudness = -11.8
        #expect(settings.aggressiveSettingWarnings.contains("かなり大きい仕上げです。音が平坦に聞こえやすくなります。"))

        settings.peakCeilingDB = -0.6
        #expect(settings.aggressiveSettingWarnings.contains("歪みやすい設定です。配信や再生環境によって音割れする可能性があります。"))
    }
}
