# Veloura Lucent performance baseline

## Source

- Date: 2026-05-16
- Evidence: user-provided screenshot `スクリーンショット 2026-05-16 16.46.19.png`
- Input file name: not visible in the screenshot
- Correction settings: not visible in the screenshot
- Mastering settings: not visible in the screenshot

This report records only values visible in the provided log screenshot. Unknown values are marked as not visible.

## Correction Log Baseline

| Item | Time |
| --- | ---: |
| 読み込み | 0.03秒 |
| 低域ノイズ | 717.93秒 |
| ノイズ除去 | 314.72秒 |
| サ行保護 | 94.20秒 |
| 再解析 | 180.24秒 |
| 解析補助 | 0.00秒 |
| 高域修復 | 22.49秒 |
| 補正後高域保持 | 361.32秒 |
| ピーク保護 | 32.59秒 |
| 書き出し | 1.88秒 |
| 合計 | 4488.70秒 |

### Correction Route

| Route item | Status |
| --- | --- |
| 低域整理 | 実行 |
| ノイズ除去 | 実行 |
| サ行保護 | 実行 |
| 高域修復 | 実行 |
| 修復後シマー保護 | スキップ |
| 低中域整理 | スキップ |
| シマー制限 | スキップ |
| ピーク保護 | 実行 |

### Correction Counts

| Item | Count |
| --- | ---: |
| 低域ノイズ/測定回数 | 1 |
| ノイズ除去/STFT再利用 | 2 |
| ルート/補正/実行工程数 | 5/8 |
| ルート/補正/スキップ工程数 | 3/8 |

## Mastering Log Baseline

| Item | Time |
| --- | ---: |
| 読み込み | 0.03秒 |
| 原音参照読み込み | 0.02秒 |
| 音色 | 37.57秒 |
| ディエッサー | 15.81秒 |
| ダイナミクス | 27.80秒 |
| 倍音 | 1.32秒 |
| 空気感 | 45.56秒 |
| 広がり | 60.44秒 |
| ラウドネス | 682.73秒 |
| ノイズ戻りガード | 457.88秒 |
| 保存 | 0.04秒 |
| 合計 | 3076.72秒 |

### Mastering Route

| Route item | Status |
| --- | --- |
| 音色 | 実行 |
| ディエッサー | 実行 |
| ダイナミクス | 実行 |
| 倍音 | 実行 |
| 空気感 | 実行 |
| ステレオ幅 | 実行 |
| ラウドネス | 実行 |
| 高域戻りガード | スキップ |
| ノイズ戻りガード | 実行 |

### Mastering Counts

| Item | Count |
| --- | ---: |
| ノイズ戻り/軽量測定 | 4/243区間 |
| ノイズ戻り/軽量判定 | 1/3, 2/3, 3/3 |
| ノイズ戻り/軽量判定回数 | 3 |
| ルート/マスタリング/実行工程数 | 8/9 |
| ルート/マスタリング/スキップ工程数 | 1/9 |

## Visible Timing Gap

The following gap is calculated only from the visible screenshot lines above.

| Area | Total | Sum of visible timed items | Visible gap |
| --- | ---: | ---: | ---: |
| 補正 | 4488.70秒 | 1725.40秒 | 2763.30秒 |
| マスタリング | 3076.72秒 | 1329.20秒 | 1747.52秒 |

## Notes for Implementation

- The baseline shows that visible per-stage times do not explain the total time.
- The implementation must add timing logs for already-running work only.
- The implementation must not add new correction, mastering, or safety stages.
- Values not visible in the screenshot must be collected by future instrumentation instead of guessed.
