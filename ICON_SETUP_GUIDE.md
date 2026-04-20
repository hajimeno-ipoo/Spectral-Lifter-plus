# Veloura Lucent アイコン設定メモ

## 結論

- このプロジェクトでは、アイコン設定が 2 系統あります。
- 1つは `.app` として起動する時の設定です。
- もう1つは Xcode から Swift Package を直接実行する時の設定です。
- どちらか片方だけだと、片方の起動方法で見た目が崩れます。

---

## この会話で何が起きたか

### 1. 最初にやったこと

- 指定画像 `Resources/icon/アイコン.png` をアプリアイコンに使いました。
- 最初は `Resources/AppIcon-1024.png` に差し替えて、`script/build_and_run.sh` で `.icns` を作る形にしました。

### 2. 起きた問題

- ターミナル経由で起動した `.app` では、アイコンは出るが、見た目が期待と違いました。
- Xcode から直接起動すると、Dock に黒い `exec` アイコンが出ました。

### 3. 誤解だったこと

- 「画像本体が半透明だからおかしい」は誤りでした。
- 実際は、元画像の本体はほぼ不透明で、周囲だけ透過でした。
- 問題は画像そのものより、起動経路ごとのアイコン設定方法の違いでした。

### 4. 修正したこと

- `.icns` 直差し中心の古いやり方から、Asset Catalog を作る方式へ変更しました。
- さらに、Xcode から直接起動した時にも同じ PNG を Dock アイコンへ明示適用するようにしました。

---

## なぜ Xcode 起動とターミナル起動で違ったのか

### ターミナル起動

- `./script/build_and_run.sh` は、`dist/Veloura Lucent.app` を自前で作ります。
- この時、`Contents/Resources` にアイコン関連ファイルを入れます。
- そのため、`.app` として起動した場合は、バンドル内アイコン設定が使われます。

### Xcode 起動

- Xcode からの実行は、`.app` を完全に組み立てて開く形とは挙動が違うことがあります。
- Swift Package の生実行に近く、Dock が汎用の `exec` アイコンになる場合があります。
- そのため、起動後に `NSApp.applicationIconImage` を使って、Dock アイコンを明示的に上書きする必要がありました。

---

## 今のアイコン設定の全体像

```text
元画像
  Resources/AppIcon-1024.png

ターミナル起動用
  script/build_and_run.sh
    -> Asset Catalog を一時生成
    -> Assets.car を作成
    -> dist/Veloura Lucent.app に同梱
    -> Info.plist にアイコン名を書く

Xcode 直起動用
  Package.swift
    -> AppIcon-1024.png を SwiftPM リソースとして登録
  Sources/VelouraLucent/App/VelouraLucentApp.swift
    -> 起動時に PNG を読み込み
    -> Dock アイコンへ明示適用
```

---

## どのファイルが何を担当しているか

### 1. 元画像

- `Resources/AppIcon-1024.png`
- アイコンの元画像です。
- アイコンを変える時は、まずこの画像を差し替えます。

### 2. Xcode 直起動時の設定

- `Package.swift`
- `Sources/VelouraLucent/Resources/AppIcon-1024.png` を SwiftPM リソースとして読み込めるようにしています。

該当内容:

```swift
.executableTarget(
    name: "VelouraLucent",
    path: "Sources/VelouraLucent",
    resources: [
        .process("Resources/AppIcon-1024.png")
    ]
)
```

- `Sources/VelouraLucent/App/VelouraLucentApp.swift`
- 起動時に `Bundle.main` と `Bundle.module` から画像を探して、Dock アイコンへ設定しています。

考え方:

- `Bundle.main`
  - `.app` の中に入っているリソースを見るための入口です。
- `Bundle.module`
  - Swift Package のリソースを見るための入口です。
- どちらでも読めるようにして、起動方法の違いを吸収しています。

### 3. ターミナル起動時の設定

- `script/build_and_run.sh`
- このスクリプトが `.app` を組み立てます。

主な役割:

- `Resources/AppIcon-1024.png` から各サイズ画像を作る
- 一時的な `Assets.xcassets/AppIcon.appiconset` を作る
- `xcrun actool` で `Assets.car` を作る
- `Info.plist` に `CFBundleIconFile` と `CFBundleIconName` を書く
- `AppIcon-1024.png` 自体も `Contents/Resources` に入れる

---

## 今の設定方法

### A. ターミナルから起動する場合

使うコマンド:

```bash
./script/build_and_run.sh
```

確認用:

```bash
./script/build_and_run.sh --verify
```

この起動方法では、`dist/Veloura Lucent.app` が作られ、その `.app` に入ったアイコン設定が使われます。

### B. Xcode から起動する場合

- Xcode でそのまま Run して構いません。
- 起動後、`VelouraLucentApp.swift` 内の `applyDockIcon()` が走り、Dock アイコンを上書きします。

---

## アイコンを変更したい時の手順

### いちばん簡単な手順

1. `Resources/AppIcon-1024.png` を差し替える
2. 同じ画像を `Sources/VelouraLucent/Resources/AppIcon-1024.png` にも反映する
3. ターミナルなら `./script/build_and_run.sh --verify`
4. Xcode でも Run して確認する

### なぜ 2か所あるのか

- `Resources/AppIcon-1024.png`
  - `.app` を組み立てるスクリプト用です。
- `Sources/VelouraLucent/Resources/AppIcon-1024.png`
  - Xcode 直起動時に SwiftPM リソースとして読むためです。

---

## 見た目が期待と違う時に見る場所

### 1. Xcode で黒い `exec` が出る

見る場所:

- `Package.swift`
- `Sources/VelouraLucent/App/VelouraLucentApp.swift`
- `Sources/VelouraLucent/Resources/AppIcon-1024.png`

疑う点:

- SwiftPM リソースに画像が入っていない
- `applyDockIcon()` で画像を読めていない

### 2. ターミナル起動では出るが見た目が違う

見る場所:

- `script/build_and_run.sh`
- `dist/Veloura Lucent.app/Contents/Resources/Assets.car`
- `dist/Veloura Lucent.app/Contents/Resources/AppIcon-1024.png`
- `dist/Veloura Lucent.app/Contents/Info.plist`

疑う点:

- `.app` へ組み込まれたアイコン設定
- macOS 側の Dock 表示やキャッシュ
- 元画像の余白や見せ方

---

## 現在の実装で大事なポイント

- `.app` 用のアイコン設定だけでは不十分です。
- Xcode 直起動では、起動後に Dock アイコンを上書きする必要があります。
- 逆に、起動後上書きだけでも不十分で、`.app` 側の `Assets.car` も必要です。
- そのため、今は「バンドル設定」と「起動時上書き」の両方を使っています。

---

## 変更後に確認する場所

- ターミナル起動:
  - `./script/build_and_run.sh --verify`
- Xcode 起動:
  - Run して Dock の見た目を見る
- 生成物確認:
  - `dist/Veloura Lucent.app/Contents/Resources/Assets.car`
  - `dist/Veloura Lucent.app/Contents/Resources/AppIcon-1024.png`
  - `dist/Veloura Lucent.app/Contents/Info.plist`

---

## 今後の運用メモ

- アイコン画像を差し替えたら、Xcode とターミナルの両方で確認する
- 片方だけ合っていても完了にしない
- 画像変更後は、まず `.app` 側、次に Xcode 直起動側を見る
- 「黒い `exec`」は画像の問題ではなく、起動経路側の問題として疑う
