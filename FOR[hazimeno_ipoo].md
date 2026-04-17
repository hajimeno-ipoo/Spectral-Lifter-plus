# Spectral Lifter Plus の概要

## これは何をするアプリか
- 音声ファイルを読み込みます。
- 高い音の不足を少し補います。
- 耳につくザラつきやシュワシュワ感を減らします。
- ブラウザではなく、Mac の普通のアプリとして動きます。

## 技術アーキテクチャの概要
- 画面: `SwiftUI`
- 音声ファイルの読み書き: `AVFoundation`
- 周波数ごとの計算: `Accelerate`
- 実行入口: `script/build_and_run.sh`

図にすると、こうです。

```text
Macアプリ(SwiftUI)
  -> AudioProcessingService
    -> NativeAudioProcessor
      -> AudioFileService
      -> SpectralDSP
      -> 解析
      -> ノイズ除去
      -> 高域補完
      -> ダイナミクス調整
      -> 音量調整
```

## コードベースの構造
- `Sources/SpectralLifter/App/`
  - アプリの起動です。
- `Sources/SpectralLifter/Views/`
  - 画面です。
- `Sources/SpectralLifter/Models/`
  - 画面の状態です。
- `Sources/SpectralLifter/Services/`
  - 音声処理、音声ファイルの読み書き、ファイル選択などです。
- `Sources/SpectralLifter/Support/`
  - FFT まわりなどの共通処理です。
- `Tests/SpectralLifterTests/`
  - 動作確認用のテストです。
- `script/build_and_run.sh`
  - ビルドしてアプリを起動するスクリプトです。

## その技術を選んだ理由
- `SwiftUI`
  - Mac アプリの見た目を素直に組みやすいからです。
- `AVFoundation`
  - macOS 標準の音声読み書きが使えるからです。
- `Accelerate`
  - 周波数処理を Swift のまま実装しやすいからです。

## よくあるバグと修正方法
- 音声ファイルを開けない
  - 壊れたファイルか、対応外の形式の可能性があります。
- 出力ファイルができない
  - 元ファイルの場所に書き込み権限があるか確認します。
- 処理が重い
  - 長い音声や高負荷の環境では時間がかかります。

## 落とし穴と回避方法
- 処理は完全な AI モデルではありません
  - 高域補完は簡潔なヒューリスティック処理です。
- 入力ごとに効き方が変わります
  - いつも同じ結果にはなりません。
- 長尺ファイルは重くなります
  - まず短い音で効き方を確認すると安全です。

## ベストプラクティス
- まずは `./script/build_and_run.sh` で起動します。
- `swift build` と `swift test` を通してから変更を重ねます。
- 音声処理は段階ごとに聞いて確認します。
- 無理に複雑な仕組みにせず、今の処理順を保って改善します。
