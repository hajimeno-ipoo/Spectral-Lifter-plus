# Veloura Lucent ノイズ除去改善 最終修正方針と実装計画

作成日: 2026-05-01

## 0. 目的

この計画の目的は、Veloura Lucent の「ノイズ除去が弱い」「弱い / 標準 / 強いの段階差が実測に出ない」「補正後またはマスタリング後にノイズが戻る」という問題を、処理責務の整理と実測検証によって改善することです。

今回の修正では、単にノイズ除去係数を強くするのではなく、次の3点を中心に直します。

1. 補正段は、ノイズ除去・前処理・最低限の修復に限定する
2. マスタリング段は、音色・音圧・空気感・広がり・最終音量を担当する
3. ノイズ除去の強度設定が、実測値に明確に反映されるようにする

補正は「掃除と修復」、マスタリングは「仕上げ」として分離します。

## 1. 現状の実測結果

追加された検証 `NoiseWorkflowVerificationTests.swift` により、次の傾向が確認されています。

| 確認項目 | 実測結果 |
|---|---|
| 入力 → 補正後 → マスタリング後 | 測定済み |
| 弱い / 標準 / 強いの段階差 | ほぼ出ていない |
| 補正でノイズが下がるか | サ行・シマーは約 -1.1 dB。ただしヒスは少し増える |
| マスタリングで戻るか | ヒスが約 +1.2〜+1.3 dB、サ行が約 +0.6 dB戻る |
| 優先して触る箇所 | まず補正本体。マスタリングだけでは根本解決しにくい |

代表値:

| 強さ | ヒス 補正 | ヒス マスタリング後 | サ行 補正 | サ行 マスタリング後 |
|---|---:|---:|---:|---:|
| 弱い | +0.6 dB | さらに +1.3 dB | -1.1 dB | +0.6 dB戻り |
| 標準 | +0.5 dB | さらに +1.3 dB | -1.1 dB | +0.6 dB戻り |
| 強い | +0.3 dB | さらに +1.2 dB | -1.1 dB | +0.6 dB戻り |

この結果から、現状は「強い」にしても十分に強くなっていません。さらに、補正後に残った、または増えた高域ノイズが、マスタリングで持ち上げられている可能性が高いです。

## 2. 現状コードから見た問題点

### 2.1 補正段に仕上げ処理が混ざっている

現在の `NativeAudioProcessor` は、概ね次の順序で処理しています。

```text
loadAudio
→ analyze
→ neuralPrediction
→ denoise
→ harmonicUpscale
→ multibandDynamics
→ loudnessFinalize
→ saveAudio
```

参照:
- `NativeAudioProcessor.swift`
- `SpectralGateDenoiser`
- `HarmonicUpscaler`
- `MultibandDynamicsProcessor`
- `LoudnessProcessor`

現状の問題は、補正段の中に以下のような仕上げ寄り処理が含まれていることです。

| 処理 | 問題 |
|---|---|
| `MultibandDynamicsProcessor` | 小さいノイズや高域成分を前に出す可能性がある |
| `LoudnessProcessor` | 補正後に残ったノイズまで元音量に近づけて持ち上げる可能性がある |
| `HarmonicUpscaler` の air / presence / transient 系 | ヒスやシマーを「空気感」として再生成する可能性がある |

補正済みファイルは完成品ではなく、マスタリング前の素材です。したがって、補正段で音圧や最終音量を作る必要はありません。

### 2.2 denoiser のマスク合成が保守的すぎる

現在の `SpectralGateDenoiser` には、次のようなマスク合成があります。

```swift
let denoiseMask = max(rawMask, granularMask)
let mask = min(1.0, max(floor, min(denoiseMask, shimmerMask)) + transientLift)
```

音声処理のマスクでは、一般に `1.0` に近いほど残し、`0.0` に近いほど削る意味になります。

そのため、

```swift
max(rawMask, granularMask)
```

は「より残すほう」を選ぶ処理です。

この設計は音楽成分を守るには安全ですが、ヒス・シュワシュワ・シマーを落としたい場面では、strong 設定でも削減量が出にくくなります。

さらに `transientLift` が最終マスクに足されるため、削った高域が戻りやすい構造です。

### 2.3 マスタリングは残ったノイズを持ち上げている

現在の `MasteringProcessor` には、tone、de-esser、multiband compression、saturation、stereo width、high return guard、loudness の処理があります。

マスタリング側に high return guard があること自体は良い設計です。  
ただし、補正段でヒスが残る、または増えている状態では、マスタリングのコンプ・サチュレーション・ラウドネス処理により、ノイズが再び目立ちやすくなります。

したがって、まず補正段で「ノイズが増えない状態」を作る必要があります。

## 3. 対象ノイズの分類と担当場所

今回見るノイズは以下です。

| ノイズ | 見るべきもの | 主処理場所 | 方針 |
|---|---|---|---|
| ヒス・シュワシュワ | 小音量区間の高域ノイズ床 | 補正 | 高域ノイズ床を下げ、マスタリングでは戻さない |
| サ行・シマー | 5kHz〜14kHzの短時間突出 | 補正＋マスタリング | 補正で異常突出を抑え、最終 de-esser で整える |
| ハム・電源ノイズ | 50/60Hzと倍音の周辺比 | 補正 | 早い段階で狭く削る |
| 低域ゴロゴロ | 20Hz〜150Hzの持続成分 | 補正 | 解析やコンプ前に不要低域を抑える |
| こもり・低いザラつき | 200Hz〜1kHzの過剰な持続成分 | 補正＋マスタリング | 補正では持続ノイズだけ軽く抑え、音色はマスタリングで整える |
| 環境音・部屋鳴り | 小音量区間の広帯域残留 | 補正 | ノイズ床として推定し、後段で持ち上げない |

## 4. 最終的な責務分担

### 4.1 補正段に置くもの

補正段は、素材をきれいにする場所です。

| 処理 | 補正に置く理由 |
|---|---|
| HumRemover | 50/60Hzハムは早く狭く取るべき |
| RumbleReducer | 低域揺れは後段コンプを誤動作させるため前処理する |
| NoiseProfileEstimator | 小音量区間やbin別低パーセンタイルからノイズ床を推定する |
| SpectralGateDenoiser | ヒス・環境音・広帯域ノイズ床を抑える中核 |
| SibilanceShimmerGuard | 5〜14kHzの短時間突出を軽く抑える |
| LowMidResidueGuard | 200Hz〜1kHzの持続ざらつきを軽く抑える |
| CorrectionHarmonicRepair | 欠けた高域を最低限だけ修復する |
| PeakSafetyLimiter | 中間素材のクリップを防ぐ |

### 4.2 マスタリング段に置くもの

マスタリング段は、完成品として整える場所です。

| 処理 | マスタリングに置く理由 |
|---|---|
| Tone EQ | 音色の最終調整 |
| De-esser | 最終音量・EQ後に出るサ行を整える |
| Multiband Compression | 密度・音圧作り |
| Saturation | 倍音・質感作り |
| MasteringAirEnhancer | 空気感、presence、transient excitement |
| Stereo Width | 広がりの調整 |
| High Return Guard | 仕上げで戻った高域を抑える |
| Final Loudness / Limiter | 最終音量とピーク制御 |

### 4.3 補正からマスタリングへ移す候補

| 現在の処理 | 移動方針 | 理由 |
|---|---|---|
| 補正段の `LoudnessProcessor` | マスタリングへ集約 | 中間段で音量を戻すとノイズも戻る |
| 補正段の `MultibandDynamicsProcessor` | マスタリングへ移動、または補正では無効化 | 音圧・密度作りは仕上げ責務 |
| `HarmonicUpscaler` の air / presence / transient 系 | マスタリングへ移動 | 空気感・抜け・アタック強調は音作り |
| `HarmonicUpscaler` の最低限の高域修復 | 補正に残す | 欠けた成分の修復は補正の役割 |

## 5. 最終パイプライン

### 5.1 補正段

```text
load audio
→ analyze original

→ HumDetector / HumRemover
   50/60Hz と倍音を検出し、必要な場合だけ狭く削る

→ RumbleReducer
   20Hz〜150Hz の持続的なゴロゴロを抑える

→ NoiseProfileEstimator
   小音量区間または bin ごとの低パーセンタイルでノイズ床を推定する

→ SpectralGateDenoiser
   ヒス・シュワシュワ・環境音の床を抑える

→ SibilanceShimmerGuard
   5kHz〜14kHz の短時間突出を抑える

→ analyze denoised

→ LowMidResidueGuard
   200Hz〜1kHz の過剰な持続成分だけ軽く抑える

→ CorrectionHarmonicRepair
   欠けた高域を最低限だけ修復する
   air / presence / transient excitement は強く足さない

→ PeakSafetyLimiter

→ write corrected file
```

### 5.2 マスタリング段

```text
load corrected audio
→ analyze corrected

→ tone EQ
   こもり、明るさ、全体バランスを調整する

→ de-esser
   最終的なサ行を抑える

→ multiband compression
   密度と音圧を作る

→ saturation
   倍音と質感を作る

→ MasteringAirEnhancer
   空気感、presence、transient を必要量だけ足す

→ stereo width
   広がりを調整する

→ high return guard
   高域ノイズ・サ行・シマーの戻りを抑える

→ final loudness / limiter

→ write mastered file
```

## 6. ノイズ別の処理方針

### 6.1 ヒス・シュワシュワ

対象:
- 小音量区間の高域ノイズ床
- 主に 12kHz〜20kHz

処理:
- 補正段で落とす
- マスタリングでは戻さない
- 補正段の loudness 復元を外す
- 補正段の multiband dynamics を外す
- `SpectralGateDenoiser` の高域マスクを強める
- `HarmonicUpscaler` の air 系は補正段から外す

期待:
- strong で入力比 0.0 dB以下
- 理想は -0.3 dB以下
- マスタリング後の high return は +0.5 dB以下

### 6.2 サ行・シマー

対象:
- 5kHz〜14kHzの短時間突出
- サ行、チリつき、キラキラした粒子感

処理:
- 補正では異常な突出だけ抑える
- マスタリングでは de-esser で最終調整する
- 補正で削りすぎない
- 2kHz〜5kHzの声の芯を守る

期待:
- 補正でシマーが gentle より strong のほうが下がる
- マスタリング後のサ行戻りは +0.4 dB以下

### 6.3 ハム・電源ノイズ

対象:
- 50Hz / 60Hz
- 100/120Hz、150/180Hz、200/240Hzなどの倍音

処理:
- 補正の早い段階で処理する
- 50Hz系か60Hz系かを自動判定する
- 周辺帯域に対して突出している場合だけ狭く notch する
- 常時固定削減は避ける

期待:
- ハムが検出された場合、基音と倍音の周辺比が低下する
- 検出されない場合は音を変えすぎない

### 6.4 低域ゴロゴロ

対象:
- 20Hz〜150Hzの持続成分
- 風、床振動、マイク揺れ、交通振動

処理:
- HumRemover の後、SpectralGateDenoiser の前で処理する
- 20Hz〜35Hzは比較的積極的に抑える
- 35Hz〜80Hzはキックやベースに注意する
- 80Hz〜150Hzは持続成分だけを対象にする

期待:
- rumbleSustainDB が入力比で低下する
- 低域楽器の基音を削りすぎない

### 6.5 こもり・低いザラつき

対象:
- 200Hz〜1kHzの過剰な持続成分
- 箱鳴り、こもり、鼻詰まり感、低いザラつき

処理:
- 補正では持続的なノイズ成分だけ軽く抑える
- 音色としてのこもり調整はマスタリングの Tone EQ に任せる
- makeup gain はしない
- 強く削らない

期待:
- lowMidResidueDB が入力比で軽く低下する
- 声や楽器の厚みを失わない

### 6.6 環境音・部屋鳴り

対象:
- 小音量区間の広帯域残留
- エアコン、部屋鳴り、遠い雑音、反射音

処理:
- bin ごとの低パーセンタイルノイズ推定を使う
- 完全除去ではなくノイズ床の低下を目指す
- 後段の loudness や air enhancer で持ち上げない

期待:
- broadbandQuietResidualDB が低下する
- 無音部分が自然に静かになる
- 音声や音楽の余韻を不自然に切らない

## 7. 実装計画

### Phase 0: 現状検証を固定する

目的:
- 変更前の問題を再現可能にする
- 以降の変更が良くなったか、悪化したかを判断できるようにする

作業:
- `NoiseWorkflowVerificationTests.swift` を維持
- 入力、補正後、マスタリング後を測定
- gentle / balanced / strong の3段階を必ず比較
- レポート出力を保存できるようにする

測定指標:

| 指標 | 帯域 | 目的 |
|---|---:|---|
| hissFloorDB | 12kHz〜20kHz | ヒス・シュワシュワ |
| sibilancePeakDB | 5kHz〜10kHz | サ行 |
| shimmerPeakDB | 8kHz〜14kHz | シマー |
| humRatioDB | 50/60Hzと倍音 | ハム |
| rumbleSustainDB | 20Hz〜150Hz | 低域ゴロゴロ |
| lowMidResidueDB | 200Hz〜1kHz | こもり・低いザラつき |
| broadbandQuietResidualDB | 150Hz〜14kHz | 環境音・部屋鳴り |
| highReturnDB | 10kHz以上 | マスタリング後の高域戻り |
| lowReturnDB | 20Hz〜150Hz | マスタリング後の低域戻り |
| peakDBFS | 全帯域 | クリップ確認 |
| loudnessDB | 全帯域 | 音量差確認 |

### Phase 1: 補正段から LoudnessProcessor を外す

目的:
- 補正後に残ったノイズを元音量へ戻さない

変更前:

```swift
let shaped = MultibandDynamicsProcessor().process(signal: upscaled)
let finalized = LoudnessProcessor().process(signal: shaped, referenceSignal: signal)
```

変更後:

```swift
let repaired = upscaled
let finalized = PeakSafetyLimiter().process(signal: repaired)
```

補足:
- 中間ファイルの音量が少し小さくなることは許容する
- 最終音量はマスタリングの責務にする
- 補正段ではクリップ防止だけ行う

合格条件:
- 補正後ヒスが現状より悪化しない
- 補正後のピークが 0 dBFS を超えない
- `swift test` が通る

### Phase 2: 補正段から MultibandDynamicsProcessor を外す

目的:
- 補正段で小さいノイズや高域成分を前に出さない

変更前:

```swift
let shaped = MultibandDynamicsProcessor().process(signal: upscaled)
```

変更後:

```swift
let shaped = upscaled
```

合格条件:
- 補正後ヒスが下がる、または少なくとも増えない
- サ行・シマーの戻りが増えない
- 音量差はマスタリング側で吸収する

必要なら後で、補正段に戻す処理は `ArtifactGuardDynamics` として別名化する。

`ArtifactGuardDynamics` の条件:
- makeup gain をしない
- 音圧を作らない
- 高域の突発ピークだけ軽く抑える
- 低域や中域の音楽成分には触りすぎない

### Phase 3: SpectralGateDenoiser の高域マスクを修正する

目的:
- weak / balanced / strong の差を実測に出す
- high band のヒス・シマーに strong が効くようにする

変更前:

```swift
let denoiseMask = max(rawMask, granularMask)
let mask = min(1.0, max(floor, min(denoiseMask, shimmerMask)) + transientLift)
```

変更案:

```swift
let highBandWeight = min(1, max(0, Float((frequency - 8_000) / 8_000)))

let combinedNoiseMask =
    rawMask * (1 - highBandWeight)
    + min(rawMask, granularMask) * highBandWeight

let transientProtection: Float
if frequency < 5_000 {
    transientProtection = transientLift
} else if frequency < 10_000 {
    transientProtection = transientLift * 0.5
} else if frequency < 16_000 {
    transientProtection = transientLift * 0.2
} else {
    transientProtection = 0
}

let mask = min(
    1.0,
    max(floor, min(combinedNoiseMask, shimmerMask)) + transientProtection
)
```

意図:

| 帯域 | 挙動 |
|---|---|
| 5kHz未満 | 音楽成分と声の芯を守る |
| 5kHz〜10kHz | サ行を見つつ、保護は少し弱める |
| 10kHz〜16kHz | シマーを抑える |
| 16kHz以上 | ヒス・シュワシュワを強めに抑える |

合格条件:
- strong の hiss が gentle より 0.3 dB以上低い
- strong の shimmer が gentle より 0.3 dB以上低い
- strong 補正後の hissDeltaFromInputDB が 0.0 dB以下

### Phase 4: strong tuning を調整する

目的:
- strong が実際に strong として機能するようにする

候補:

```swift
case .strong:
    return DenoiseTuning(
        passes: 3,
        thresholdMultiplier: 1.85,
        lowBandFloor: 0.10,
        highBandFloor: 0.14,
        quietPercentile: 30,
        transientProtection: 0.12,
        granularReduction: 0.48,
        shimmerStabilization: 0.24,
        coreProtection: 0.50,
        exceptionRelaxation: 0.40
    )
```

注意:
- これは最初から固定値として採用せず、Phase 3 の後で比較する
- `highBandFloor` を下げすぎると、暗さや金物の不自然さが出る
- `granularReduction` を上げすぎると、チリつきは減るが、余韻が崩れる場合がある

### Phase 5: HumRemover を追加する

目的:
- 50/60Hz と倍音の電源ノイズを補正前段で処理する

処理位置:

```text
analyze original
→ HumDetector / HumRemover
→ RumbleReducer
```

検出:
- 50Hz系: 50, 100, 150, 200, 250Hz
- 60Hz系: 60, 120, 180, 240, 300Hz
- 各周波数の周辺比を計算する
- 50Hz系と60Hz系のどちらが優勢か判定する

処理:
- 周辺比が閾値を超えた場合だけ narrow notch
- Q は高め
- 倍音は強さに応じて段階的に削る
- 音楽成分が強い場合は削りすぎない

合格条件:
- ハムが検出された素材で humRatioDB が低下する
- ハムがない素材では低域の音色変化が小さい

### Phase 6: RumbleReducer を追加する

目的:
- 20Hz〜150Hz の持続的な低域ノイズを前処理で抑える

処理位置:

```text
HumRemover
→ RumbleReducer
→ NoiseProfileEstimator
```

帯域別方針:

| 帯域 | 方針 |
|---|---|
| 20Hz〜35Hz | 比較的積極的に抑える |
| 35Hz〜80Hz | キック・ベースに注意して慎重に抑える |
| 80Hz〜150Hz | 持続成分だけ対象にする |

合格条件:
- rumbleSustainDB が入力比で低下する
- 35Hz〜120Hzの音楽的ピークが不自然に削れない

### Phase 7: NoiseProfileEstimator を改善する

目的:
- 環境音・部屋鳴り・広帯域残留を拾いやすくする

現状の課題:
- 静かなフレームを選んでノイズプロファイルを作るだけでは、音楽や声が常にある素材で精度が落ちる

改善案:
- フレーム単位だけでなく、bin単位の低パーセンタイルを使う
- 小音量区間がない素材でも、各周波数で持続している床を推定する

擬似コード:

```swift
var magnitudesByBin = Array(repeating: [Float](), count: binCount)

for frameIndex in 0..<spectrogram.frameCount {
    let frameStart = frameIndex * binCount

    for binIndex in 0..<binCount {
        let index = frameStart + binIndex
        let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
        magnitudesByBin[binIndex].append(magnitude)
    }
}

for binIndex in 0..<binCount {
    let binNoise = SpectralDSP.percentile(magnitudesByBin[binIndex], 12)
    noiseProfile[binIndex] = binNoise * coefficients.highBandBias[binIndex]
}
```

合格条件:
- broadbandQuietResidualDB が低下する
- 無音部分や小音量部分が自然に静かになる
- 余韻が不自然に切れない

### Phase 8: denoise 後の再解析を追加する

目的:
- 高域補完の判断を、元音源ではなく denoise 後の状態に合わせる

変更案:

```swift
let originalAnalysis = AudioAnalyzer(mode: resolvedAnalysisMode).analyze(signal: signal)

let denoised = SpectralGateDenoiser(strength: denoiseStrength).process(signal: signal)

let postDenoiseAnalysis = AudioAnalyzer(mode: resolvedAnalysisMode).analyze(signal: denoised)

let repairPrediction = NeuralFoldoverEstimator().predict(
    features: NeuralFoldoverFeatures(
        harmonicConfidence: postDenoiseAnalysis.harmonicConfidence,
        shimmerRatio: postDenoiseAnalysis.shimmerRatio,
        brightnessRatio: postDenoiseAnalysis.brightnessRatio,
        transientAmount: postDenoiseAnalysis.transientAmount,
        cutoffFrequency: originalAnalysis.cutoffFrequency,
        noiseAmount: postDenoiseAnalysis.noiseAmount,
        rolloffDepth: originalAnalysis.rolloffDepth,
        airBandEnergyRatio: postDenoiseAnalysis.airBandEnergyRatio,
        artifactBandRatio: postDenoiseAnalysis.artifactBandRatio
    )
)
```

使い分け:

| 特徴量 | 使う解析 |
|---|---|
| cutoffFrequency | originalAnalysis |
| rolloffDepth | originalAnalysis |
| noiseAmount | postDenoiseAnalysis |
| shimmerRatio | postDenoiseAnalysis |
| airBandEnergyRatio | postDenoiseAnalysis |
| artifactBandRatio | postDenoiseAnalysis |
| transientAmount | postDenoiseAnalysis |
| brightnessRatio | postDenoiseAnalysis |

合格条件:
- 補正後ヒスが再び増えない
- 高域補完がノイズ量に応じて控えめになる

### Phase 9: HarmonicUpscaler を分割する

目的:
- 修復と演出を分離する

新設案:

```swift
struct CorrectionHarmonicRepair {
    func process(
        signal: AudioSignal,
        analysis: AnalysisData,
        prediction: NeuralFoldoverPrediction
    ) -> AudioSignal
}

struct MasteringAirEnhancer {
    func process(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings
    ) -> AudioSignal
}
```

補正側に残すもの:
- foldover 系の最低限の高域修復
- 欠落した帯域の控えめな補完
- noiseAmount / artifactBandRatio による強いガード

マスタリング側に移すもの:
- air
- presence
- transient excitement
- 明るさの演出
- 抜け感の演出

補正側ガード例:

```swift
let noiseGuard = max(
    0.25,
    1.0 - analysis.noiseAmount * 0.60 - analysis.artifactBandRatio * 0.50
)

let guardedRepairMix = repairMix * noiseGuard
let guardedFoldoverMix = foldoverMix * noiseGuard
```

合格条件:
- 補正後ヒスが入力比で増えない
- 高域修復後に shimmer が増えすぎない
- マスタリング側で必要な空気感を足せる

### Phase 10: MasteringAirEnhancer をマスタリングに追加する

目的:
- 空気感・presence・transient を補正ではなく仕上げで制御する

配置:

```text
tone
→ de-esser
→ multiband compression
→ saturation
→ MasteringAirEnhancer
→ stereo width
→ high return guard
→ final loudness
```

理由:
- saturation 後に倍音を見て空気感を調整できる
- stereo width 前に高域量を制御できる
- high return guard 前に置くことで、足しすぎた高域を最後に抑えられる
- final loudness 前に置くことで、音量処理後の戻りを測定できる

合格条件:
- マスタリング後の highReturnDB が +0.5 dB以下
- サ行戻りが +0.4 dB以下
- 空気感が必要以上に失われない

## 8. テスト計画

### 8.1 実行コマンド

```bash
swift test --filter NoiseWorkflowVerificationTests/correctionAndMasteringNoiseWorkflowProducesReport
swift test
git diff --check
```

### 8.2 段階差テスト

目的:
- weak / balanced / strong の差を保証する

例:

```swift
XCTAssertLessThanOrEqual(
    strong.corrected.hissDB,
    gentle.corrected.hissDB - 0.3
)

XCTAssertLessThanOrEqual(
    strong.corrected.shimmerDB,
    gentle.corrected.shimmerDB - 0.3
)
```

### 8.3 補正後ヒス増加防止テスト

目的:
- strong でヒスが増えないことを保証する

例:

```swift
XCTAssertLessThanOrEqual(
    strong.corrected.hissDeltaFromInputDB,
    0.0
)
```

理想値:

```swift
XCTAssertLessThanOrEqual(
    strong.corrected.hissDeltaFromInputDB,
    -0.3
)
```

### 8.4 マスタリング後戻り量テスト

目的:
- マスタリングでノイズが戻りすぎないことを保証する

例:

```swift
XCTAssertLessThanOrEqual(
    mastered.hissReboundDB,
    0.5
)

XCTAssertLessThanOrEqual(
    mastered.sibilanceReboundDB,
    0.4
)
```

### 8.5 ハム・ゴロゴロ検出時のみ削減するテスト

目的:
- 存在しないノイズに過剰処理しない

方針:
- ハムあり素材では humRatioDB が下がる
- ハムなし素材では低域の変化量を制限する
- ゴロゴロあり素材では rumbleSustainDB が下がる
- 低域楽器がある素材では 35Hz〜120Hz の主成分を保護する

### 8.6 音質保護テスト

ノイズを下げるだけでは不十分です。音質劣化も検出します。

| 指標 | 目的 |
|---|---|
| 1kHz〜4kHz平均エネルギー | 声の芯が削れすぎていないか |
| 2kHz〜5kHz presence | 明瞭度が落ちすぎていないか |
| crest factor | 潰れすぎていないか |
| peakDBFS | クリップしていないか |
| 8kHz〜12kHz balance | 明るさが消えすぎていないか |
| 12kHz〜20kHz hiss | 高域ノイズ床が減ったか |
| 10kHz〜16kHz flicker | シマーが減ったか |

## 9. 合格条件

初期合格条件:

| 条件 | 目標 |
|---|---|
| `swift test` | 全通過 |
| `git diff --check` | 成功 |
| strong vs gentle の hiss | strong が gentle より 0.3 dB以上低い |
| strong vs gentle の shimmer | strong が gentle より 0.3 dB以上低い |
| strong 補正後 hiss | 入力比 0.0 dB以下 |
| strong 補正後 shimmer | 入力比で低下 |
| マスタリング後 hiss rebound | +0.5 dB以下 |
| マスタリング後 sibilance rebound | +0.4 dB以下 |
| ハム検出時 | humRatioDB が低下 |
| ゴロゴロ検出時 | rumbleSustainDB が低下 |
| ハムなし・ゴロゴロなし | 低域を変えすぎない |
| 補正済みファイル | 音量が少し小さくてもよい |
| マスタリング済みファイル | 音圧・音色・ノイズ戻りのバランスが取れている |

理想合格条件:

| 条件 | 目標 |
|---|---|
| strong 補正後 hiss | 入力比 -0.3 dB以下 |
| strong 補正後 shimmer | 入力比 -0.5 dB以下 |
| マスタリング後 high return | +0.3 dB以下 |
| サ行戻り | +0.3 dB以下 |
| broadband quiet residual | 入力比で明確に低下 |
| 聴感 | 暗すぎない、息が消えない、金物が不自然に潰れない |

## 10. 実装優先順位

| 優先 | 作業 | 理由 |
|---:|---|---|
| 1 | 補正段から `LoudnessProcessor` を外す | 全ノイズの持ち上げを止める |
| 2 | 補正段から `MultibandDynamicsProcessor` を外す | 小さいノイズを前に出さない |
| 3 | `SpectralGateDenoiser` の高域マスク修正 | ヒス・シュワシュワを直接改善する |
| 4 | `transientLift` の高域弱体化 | 高域ノイズの戻りを抑える |
| 5 | strong tuning の比較調整 | 強度差を明確にする |
| 6 | `HumRemover` 追加 | ハムは専用処理が必要 |
| 7 | `RumbleReducer` 追加 | 低域ゴロゴロは前処理すべき |
| 8 | `NoiseProfileEstimator` 改善 | 環境音・部屋鳴りに効く |
| 9 | denoise 後の再解析 | 高域補完の判断を正す |
| 10 | `LowMidResidueGuard` 追加 | こもり・低いザラつきを慎重に抑える |
| 11 | `HarmonicUpscaler` 分割 | 修復と演出を分ける |
| 12 | `MasteringAirEnhancer` 追加 | 空気感をマスタリングで制御する |
| 13 | high return guard と loudness の再調整 | 最終出力のノイズ戻りを抑える |

## 11. 変更の最小セット

まず短期間で効果確認するなら、次の4点だけを先に行います。

1. 補正段の `LoudnessProcessor` を外す
2. 補正段の `MultibandDynamicsProcessor` を外す
3. `SpectralGateDenoiser` の `max(rawMask, granularMask)` を高域で `min` 寄りに変更する
4. `transientLift` を高域で弱める

この最小セットで、次を確認します。

| 確認 | 期待 |
|---|---|
| 補正後ヒス | 増えなくなる |
| strong の効果 | gentle より明確に強くなる |
| サ行・シマー | 引き続き低下する |
| マスタリング後戻り | 現状より小さくなる |

この時点で改善が見えるなら、後続の HumRemover、RumbleReducer、HarmonicUpscaler 分割へ進めます。

## 12. リスクと対策

| リスク | 原因 | 対策 |
|---|---|---|
| 音が暗くなる | highBandFloor を下げすぎる | 8kHz〜12kHzの明るさ指標を監視する |
| 声の息が消える | サ行・高域を削りすぎる | 2kHz〜5kHz presence と 5kHz〜10kHz sibilance を分けて見る |
| 金物が不自然になる | shimmer抑制が強すぎる | 10kHz〜16kHzの短時間変動だけを対象にする |
| 低域が痩せる | RumbleReducerが強すぎる | 35Hz〜120Hzは慎重に処理する |
| 声が薄くなる | LowMidResidueGuardが強すぎる | 200Hz〜1kHzは軽い抑制に留める |
| 部屋鳴りがブツ切れになる | 環境音を完全除去しようとする | ノイズ床低下を目標にして完全除去を避ける |
| マスタリングで再び高域が戻る | air enhancer / loudnessが強い | high return guard と rebound テストを強化する |
| テストが素材依存で不安定 | ノイズが存在しない素材にも削減を求める | 検出された場合だけ削減を要求する条件にする |

## 13. PR分割案

大きな変更を一気に入れると原因追跡が難しくなります。PRは分けるのが安全です。

### PR 1: 検証基盤

内容:
- `NoiseWorkflowVerificationTests.swift` の指標拡張
- hiss / shimmer / sibilance / hum / rumble / lowMid / broadband residual の測定追加
- レポート出力整備

目的:
- 変更前の問題を固定する

### PR 2: 補正段の責務整理

内容:
- 補正段の `LoudnessProcessor` を外す
- 補正段の `MultibandDynamicsProcessor` を外す
- `PeakSafetyLimiter` を導入する

目的:
- ノイズを持ち上げる仕上げ処理を補正から外す

### PR 3: Denoiser強化

内容:
- 高域で `min(rawMask, granularMask)` 寄りにする
- `transientLift` を高域で弱める
- strong tuning を比較調整する

目的:
- ヒス・シュワシュワ・シマーに strong が効くようにする

### PR 4: 前処理ノイズ対策

内容:
- `HumRemover`
- `RumbleReducer`
- `NoiseProfileEstimator` 改善

目的:
- 高域以外のノイズにも対応する

### PR 5: 高域補完の分割

内容:
- `HarmonicUpscaler` を `CorrectionHarmonicRepair` と `MasteringAirEnhancer` に分割
- denoise 後の再解析を導入する
- 補正側に noise guard を入れる

目的:
- 修復と演出を分ける

### PR 6: マスタリングの戻り抑制

内容:
- `MasteringAirEnhancer` を saturation 後、stereo 前に追加
- `highReturnGuard` の閾値と rebound テストを調整
- final loudness 後の戻り量を確認する

目的:
- 仕上げでノイズを戻さない

## 14. 最終結論

最終方針は次の通りです。

補正段では、ノイズ除去・前処理・最低限の修復だけを行います。

```text
ハム除去
低域ゴロゴロ除去
広帯域ノイズ床推定
高域ヒス・シマー抑制
低中域の持続ざらつき抑制
最低限の高域修復
ピーク保護
```

マスタリング段では、完成品としての音作りを行います。

```text
音色調整
ディエッサー
マルチバンドコンプ
サチュレーション
空気感
広がり
高域戻り抑制
最終音量
```

最初に触るべき箇所は、補正段の `LoudnessProcessor` と `MultibandDynamicsProcessor` の切り離しです。  
次に `SpectralGateDenoiser` の高域マスク合成と `transientLift` の扱いを直します。  
その後で、ハム・低域ゴロゴロ・環境音・こもりを追加検出し、最後に `HarmonicUpscaler` を「補正側の修復」と「マスタリング側の演出」に分割します。

この順番なら、ノイズ除去が弱い問題、強度差が出ない問題、補正後にヒスが増える問題、マスタリングでノイズが戻る問題を、段階的かつ検証可能に改善できます。

## 15. 参照元

- NativeAudioProcessor.swift  
  https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/NativeAudioProcessor.swift

- MasteringProcessor.swift  
  https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/MasteringProcessor.swift

- Repository  
  https://github.com/hajimeno-ipoo/Veloura-Lucent
