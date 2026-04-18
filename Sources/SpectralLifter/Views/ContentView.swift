import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var job = ProcessingJob()
    @State private var preview = AudioPreviewController()

    private let metricColumns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                inputSection
                outputSection
                masteringSection
                PreviewPanelView(
                    preview: preview,
                    inputFileURL: job.inputFile,
                    correctedFileURL: job.hasExistingOutput ? job.outputFile : nil,
                    masteredFileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil
                )
                correctionActionSection
                masteringActionSection
                progressSection
                spectrogramSection
                metricsSection
                logSection
            }
            .padding(24)
        }
        .frame(minWidth: 1_060, minHeight: 860)
        .onChange(of: job.selectedMasteringProfile) { _, newValue in
            job.applyMasteringProfile(newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spectral Lifter")
                .font(.largeTitle.bold())
            Text("補正で荒れを整えたあと、別機能のマスタリングで仕上げまで行います。")
                .foregroundStyle(.secondary)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入力ファイル")
                .font(.headline)

            HStack {
                Text(job.inputFile?.path(percentEncoded: false) ?? "まだ選択されていません")
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("音声を選ぶ") {
                    if let url = FilePanelService.chooseAudioFile() {
                        job.prepareForSelection(url)
                        preview.stopPlayback()
                        preparePreviewCards()
                        analyzeMetrics(for: url, target: .input)
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プレビュー用の一時保持")
                .font(.headline)

            outputPathRow(title: "補正後プレビュー", fileURL: job.outputFile, placeholder: "補正を実行すると一時ファイルが作られます")
            outputPathRow(title: "最終版プレビュー", fileURL: job.masteredOutputFile, placeholder: "マスタリングを実行すると一時ファイルが作られます")
        }
    }

    private func outputPathRow(title: String, fileURL: URL?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(fileURL?.path(percentEncoded: false) ?? placeholder)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var masteringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("マスタリング")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("仕上がり")
                        .font(.subheadline.weight(.semibold))
                    Picker("仕上がり", selection: $job.selectedMasteringProfile) {
                        ForEach(MasteringProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("説明")
                        .font(.subheadline.weight(.semibold))
                    Text(job.selectedMasteringProfile.summary)
                        .foregroundStyle(.secondary)
                    Text(job.isUsingCustomMasteringSettings ? "詳細設定を調整中です" : "プリセットの既定値を使用しています")
                        .font(.caption)
                        .foregroundStyle(job.isUsingCustomMasteringSettings ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup(isExpanded: $job.showAdvancedMasteringSettings) {
                advancedMasteringSettings
                    .padding(.top, 8)
            } label: {
                Text("詳細設定")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var advancedMasteringSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("プリセットの既定値を細かく調整できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("プリセットへ戻す") {
                    job.resetMasteringSettingsToProfile()
                }
                .disabled(!job.isUsingCustomMasteringSettings)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                sliderCard(title: "LUFS目標", valueText: String(format: "%.1f LUFS", job.editableMasteringSettings.targetLoudness)) {
                    Slider(
                        value: binding(
                            get: { Double(job.editableMasteringSettings.targetLoudness) },
                            set: { newValue in
                                job.updateMasteringSettings { settings in
                                    settings.targetLoudness = Float(newValue)
                                }
                            }
                        ),
                        in: -18 ... -9,
                        step: 0.1
                    )
                }

                sliderCard(title: "True Peak", valueText: String(format: "%.1f dB", job.editableMasteringSettings.peakCeilingDB)) {
                    Slider(
                        value: binding(
                            get: { Double(job.editableMasteringSettings.peakCeilingDB) },
                            set: { newValue in
                                job.updateMasteringSettings { settings in
                                    settings.peakCeilingDB = Float(newValue)
                                }
                            }
                        ),
                        in: -2 ... -0.2,
                        step: 0.1
                    )
                }

                sliderCard(title: "低域の厚み", valueText: String(format: "%.2f", job.editableMasteringSettings.lowShelfGain)) {
                    Slider(
                        value: binding(
                            get: { Double(job.editableMasteringSettings.lowShelfGain) },
                            set: { newValue in
                                job.updateMasteringSettings { settings in
                                    settings.lowShelfGain = Float(newValue)
                                }
                            }
                        ),
                        in: 0 ... 3,
                        step: 0.05
                    )
                }

                sliderCard(title: "高域の明るさ", valueText: String(format: "%.2f", job.editableMasteringSettings.highShelfGain)) {
                    Slider(
                        value: binding(
                            get: { Double(job.editableMasteringSettings.highShelfGain) },
                            set: { newValue in
                                job.updateMasteringSettings { settings in
                                    settings.highShelfGain = Float(newValue)
                                }
                            }
                        ),
                        in: 0 ... 3,
                        step: 0.05
                    )
                }

                compressorControlCard(title: "低域コンプ", settings: job.editableMasteringSettings.multibandCompression.low) { field, value in
                    job.updateMasteringSettings { settings in
                        switch field {
                        case .ratio:
                            settings.multibandCompression.low.ratio = Float(value)
                        case .threshold:
                            settings.multibandCompression.low.thresholdDB = Float(value)
                        }
                    }
                }

                compressorControlCard(title: "中域コンプ", settings: job.editableMasteringSettings.multibandCompression.mid) { field, value in
                    job.updateMasteringSettings { settings in
                        switch field {
                        case .ratio:
                            settings.multibandCompression.mid.ratio = Float(value)
                        case .threshold:
                            settings.multibandCompression.mid.thresholdDB = Float(value)
                        }
                    }
                }

                compressorControlCard(title: "高域コンプ", settings: job.editableMasteringSettings.multibandCompression.high) { field, value in
                    job.updateMasteringSettings { settings in
                        switch field {
                        case .ratio:
                            settings.multibandCompression.high.ratio = Float(value)
                        case .threshold:
                            settings.multibandCompression.high.thresholdDB = Float(value)
                        }
                    }
                }

                sliderCard(title: "ステレオ幅", valueText: String(format: "%.2f", job.editableMasteringSettings.stereoWidth)) {
                    Slider(
                        value: binding(
                            get: { Double(job.editableMasteringSettings.stereoWidth) },
                            set: { newValue in
                                job.updateMasteringSettings { settings in
                                    settings.stereoWidth = Float(newValue)
                                }
                            }
                        ),
                        in: 0.8 ... 1.4,
                        step: 0.01
                    )
                }

                sliderCard(title: "サチュレーション量", valueText: String(format: "%.2f", job.editableMasteringSettings.saturationAmount)) {
                    Slider(
                        value: binding(
                            get: { Double(job.editableMasteringSettings.saturationAmount) },
                            set: { newValue in
                                job.updateMasteringSettings { settings in
                                    settings.saturationAmount = Float(newValue)
                                }
                            }
                        ),
                        in: 0 ... 0.45,
                        step: 0.01
                    )
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("試聴比較")
                    .font(.headline)
                Spacer()
                Text(preview.playbackLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            comparisonControlSection

            HStack(spacing: 14) {
                previewCard(title: "入力音声", target: .input, fileURL: job.inputFile, tint: .blue)
                previewCard(title: "補正後", target: .corrected, fileURL: job.hasExistingOutput ? job.outputFile : nil, tint: .green)
                previewCard(title: "最終版", target: .mastered, fileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, tint: .orange)
            }
        }
    }

    private var comparisonControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("比較対象", selection: binding(
                    get: { preview.comparisonPair },
                    set: { preview.setComparisonPair($0) }
                )) {
                    ForEach(AudioComparisonPair.allCases) { pair in
                        Text(pair.title).tag(pair)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
            }

            HStack(spacing: 10) {
                Text(preview.comparisonPair.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Text("vol.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: binding(
                            get: { Double(preview.playbackVolume) },
                            set: { preview.setPlaybackVolume(Float($0)) }
                        ),
                        in: 0 ... 1,
                        step: 0.01
                    )
                    .frame(width: 120)
                    Text("\(Int((preview.playbackVolume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }

                Toggle(
                    "ラウドネス合わせ比較",
                    isOn: binding(
                        get: { preview.isLoudnessMatchedComparisonEnabled },
                        set: { preview.setLoudnessMatchedComparisonEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("現在: \(preview.comparisonPair.title(for: preview.activeComparisonSide))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Aを再生") {
                    preview.playComparisonSide(.a)
                }
                .disabled(comparisonFileURL(for: .a) == nil)

                Button("Bを再生") {
                    preview.playComparisonSide(.b)
                }
                .disabled(comparisonFileURL(for: .b) == nil)

                Button("A/B切替") {
                    preview.toggleComparisonSide()
                }
                .disabled(comparisonFileURL(for: .a) == nil || comparisonFileURL(for: .b) == nil)
            }
        }
    }

    private func previewCard(title: String, target: AudioPreviewTarget, fileURL: URL?, tint: Color) -> some View {
        let snapshot = preview.snapshot(for: target)
        let liveBands = preview.liveBandLevels[target] ?? AudioBandCatalog.previewBands.map {
            LiveBandSample(id: $0.id, label: $0.label, level: 0)
        }
        let isActive = preview.activeTarget == target
        let comparisonSide = preview.comparisonSide(for: target)
        let playbackState = preview.playbackState(for: target)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                if let comparisonSide, preview.isInComparisonPair(target) {
                    Text(preview.comparisonPair.title(for: comparisonSide))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isActive ? tint.opacity(0.22) : Color.secondary.opacity(0.12)))
                }
                Spacer()
                Text(preview.playbackTimeText(for: target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(fileURL?.lastPathComponent ?? "まだ確認できません")
                .lineLimit(2)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)

            waveformPreview(snapshot: snapshot, tint: tint, progress: preview.playbackProgress(for: target))

            VStack(spacing: 6) {
                ForEach(liveBands) { band in
                    HStack(spacing: 8) {
                        Text(band.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                                Capsule()
                                    .fill(tint.opacity(isActive ? 0.95 : 0.45))
                                    .frame(width: proxy.size.width * band.level)
                            }
                        }
                        .frame(height: 6)
                    }
                    .frame(height: 10)
                }
            }

            HStack(spacing: 8) {
                Button(primaryPlaybackButtonTitle(for: target)) {
                    preview.startPlayback(for: fileURL, target: target)
                }
                .disabled(fileURL == nil || playbackState == .playing)

                Button("一時停止") {
                    preview.pausePlayback(target: target)
                }
                .disabled(playbackState != .playing)

                Button("停止") {
                    preview.stopPlayback(target: target)
                }
                .disabled(fileURL == nil || playbackState == .stopped)

                if let fileURL {
                    Button("Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func primaryPlaybackButtonTitle(for target: AudioPreviewTarget) -> String {
        switch preview.playbackState(for: target) {
        case .paused:
            return "再開"
        case .playing, .stopped:
            return "再生"
        }
    }

    private func waveformPreview(snapshot: AudioPreviewSnapshot, tint: Color, progress: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let points = snapshot.waveform
            let clampedProgress = max(0, min(1, progress))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))

                if !points.isEmpty {
                    Canvas { context, size in
                        let step = size.width / CGFloat(max(points.count - 1, 1))
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height / 2))

                        for (index, sample) in points.enumerated() {
                            let x = CGFloat(index) * step
                            let amplitude = CGFloat(sample) * size.height * 0.42
                            path.addLine(to: CGPoint(x: x, y: size.height / 2 - amplitude))
                        }

                        for (index, sample) in points.enumerated().reversed() {
                            let x = CGFloat(index) * step
                            let amplitude = CGFloat(sample) * size.height * 0.42
                            path.addLine(to: CGPoint(x: x, y: size.height / 2 + amplitude))
                        }

                        path.closeSubpath()
                        context.fill(path, with: .color(tint.opacity(0.28)))
                    }
                }

                Rectangle()
                    .fill(tint)
                    .frame(width: 2)
                    .offset(x: width * clampedProgress)
                    .opacity(snapshot.duration > 0 ? 1 : 0)
            }
        }
        .frame(height: 54)
    }

    private var correctionActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("補正")
                .font(.headline)

            actionButtonRow(
                primaryTitle: job.isProcessing ? "補正中..." : "補正を実行",
                onPrimary: startCorrectionProcessing,
                primaryDisabled: job.inputFile == nil || job.isProcessing || job.isMastering,
                exportTitle: "補正を書き出し",
                onExport: exportCorrectedAudio,
                exportDisabled: !job.hasExistingOutput || job.isProcessing,
                previewTitle: "プレビューを開く",
                onPreview: {
                    guard let outputFile = job.outputFile else { return }
                    NSWorkspace.shared.open(outputFile)
                },
                previewDisabled: !job.hasExistingOutput || job.isProcessing,
                statusText: job.statusMessage,
                statusColor: correctionStatusColor,
                captionText: job.isAnalyzingMetrics ? "比較を更新中" : "試聴状態は上の試聴比較に表示します"
            )
        }
    }

    private var masteringActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("マスタリング")
                .font(.headline)

            actionButtonRow(
                primaryTitle: job.isMastering ? "マスタリング中..." : "マスタリングを実行",
                onPrimary: startMasteringProcessing,
                primaryDisabled: !job.hasExistingOutput || job.isMastering || job.isProcessing,
                exportTitle: "最終版を書き出し",
                onExport: exportMasteredAudio,
                exportDisabled: !job.hasExistingMasteredOutput || job.isMastering,
                previewTitle: "プレビューを開く",
                onPreview: {
                    guard let outputFile = job.masteredOutputFile else { return }
                    NSWorkspace.shared.open(outputFile)
                },
                previewDisabled: !job.hasExistingMasteredOutput || job.isMastering,
                statusText: job.masteringStatusMessage,
                statusColor: masteringStatusColor,
                captionText: job.isUsingCustomMasteringSettings ? "詳細設定を反映します" : job.selectedMasteringProfile.summary
            )
        }
    }

    private func actionButtonRow(
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        primaryDisabled: Bool,
        exportTitle: String,
        onExport: @escaping () -> Void,
        exportDisabled: Bool,
        previewTitle: String,
        onPreview: @escaping () -> Void,
        previewDisabled: Bool,
        statusText: String,
        statusColor: Color,
        captionText: String
    ) -> some View {
        HStack(spacing: 12) {
            Button(primaryTitle, action: onPrimary)
                .disabled(primaryDisabled)

            Button(exportTitle, action: onExport)
                .disabled(exportDisabled)

            Button(previewTitle, action: onPreview)
                .disabled(previewDisabled)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .foregroundStyle(statusColor)
                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            progressBlock(
                title: "補正の進行状況",
                status: job.progressLabel,
                tint: correctionStatusColor,
                value: job.progressValue,
                steps: ProcessingStep.allCases,
                activeStep: job.activeStep,
                completedSteps: job.completedSteps
            )

            masteringProgressBlock
        }
    }

    private func progressBlock(
        title: String,
        status: String,
        tint: Color,
        value: Double,
        steps: [ProcessingStep],
        activeStep: ProcessingStep?,
        completedSteps: Set<ProcessingStep>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: value)
                .tint(tint)

            HStack(spacing: 8) {
                ForEach(steps, id: \.self) { step in
                    progressBadge(
                        title: step.title,
                        isCompleted: completedSteps.contains(step),
                        isActive: activeStep == step
                    )
                }
            }
        }
    }

    private var masteringProgressBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("マスタリングの進行状況")
                    .font(.headline)
                Spacer()
                Text(masteringProgressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: masteringProgressValue)
                .tint(masteringStatusColor)

            HStack(spacing: 8) {
                ForEach(MasteringStep.allCases, id: \.self) { step in
                    progressBadge(
                        title: step.title,
                        isCompleted: job.completedMasteringSteps.contains(step),
                        isActive: job.masteringActiveStep == step
                    )
                }
            }
        }
    }

    private func progressBadge(title: String, isCompleted: Bool, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : isActive ? "dot.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? Color.green : isActive ? Color.orange : Color.secondary)
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.orange.opacity(0.14) : isCompleted ? Color.green.opacity(0.14) : Color.secondary.opacity(0.08))
        )
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("数値と視覚比較")
                    .font(.headline)
                Spacer()
                if job.isAnalyzingMetrics {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            comparisonSection(
                title: "入力 -> 補正後",
                inputMetrics: job.inputMetrics,
                outputMetrics: job.outputMetrics,
                emptyMessage: "補正後の比較は、補正を実行すると表示されます。"
            )

            comparisonSection(
                title: "補正後 -> 最終版",
                inputMetrics: job.outputMetrics,
                outputMetrics: job.masteredMetrics,
                emptyMessage: "最終版の比較は、マスタリングを実行すると表示されます。"
            )
        }
    }

    private var spectrogramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("スペクトログラム")
                .font(.headline)

            if let input = job.inputSpectrogram {
                let bounds = combinedSpectrogramBounds(input: input, corrected: job.outputSpectrogram, mastered: job.masteredSpectrogram)
                HStack(alignment: .top, spacing: 14) {
                    spectrogramCard(title: "入力", snapshot: input, tint: .blue, bounds: bounds)
                    spectrogramCard(title: "補正後", snapshot: job.outputSpectrogram ?? .empty, tint: .green, bounds: bounds)
                    spectrogramCard(title: "最終版", snapshot: job.masteredSpectrogram ?? .empty, tint: .orange, bounds: bounds)
                }
            } else {
                Text("音声を選ぶと、ここに入力・補正後・最終版の時間と帯域の変化が表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func spectrogramCard(title: String, snapshot: SpectrogramSnapshot, tint: Color, bounds: (min: Double, max: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if snapshot.cells.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 180)
                    .overlay {
                        Text("まだ表示できません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Chart(snapshot.cells) { cell in
                    RectangleMark(
                        xStart: .value("時間開始", cell.timeStart),
                        xEnd: .value("時間終了", cell.timeEnd),
                        yStart: .value("周波数開始", cell.frequencyStart),
                        yEnd: .value("周波数終了", cell.frequencyEnd)
                    )
                    .foregroundStyle(tint.opacity(spectrogramOpacity(for: cell.levelDB, bounds: bounds)))
                    .lineStyle(.init(lineWidth: 0))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(values: [100, 1_000, 10_000]) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let frequency = value.as(Double.self) {
                                Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                            }
                        }
                    }
                }
                .chartXScale(domain: 0 ... max(snapshot.duration, 0.1))
                .chartYScale(domain: 80 ... 24_000, type: .log)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.black.opacity(0.06))
                        .border(Color.black.opacity(0.08))
                }
                .frame(height: 180)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func combinedSpectrogramBounds(
        input: SpectrogramSnapshot,
        corrected: SpectrogramSnapshot?,
        mastered: SpectrogramSnapshot?
    ) -> (min: Double, max: Double) {
        let snapshots = [input, corrected, mastered].compactMap { $0 }.filter { !$0.cells.isEmpty }
        let minLevel = snapshots.map(\.minLevelDB).min() ?? -96
        let maxLevel = snapshots.map(\.maxLevelDB).max() ?? -24
        return (minLevel, maxLevel)
    }

    private func spectrogramOpacity(for levelDB: Double, bounds: (min: Double, max: Double)) -> Double {
        let normalized = max(0, min(1, (levelDB - bounds.min) / max(bounds.max - bounds.min, 1)))
        return 0.04 + pow(normalized, 0.55) * 0.96
    }

    private func comparisonSection(
        title: String,
        inputMetrics: AudioMetricSnapshot?,
        outputMetrics: AudioMetricSnapshot?,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let inputMetrics {
                VStack(spacing: 12) {
                    LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                        metricCard(title: "Peak", input: inputMetrics.peakDBFS, output: outputMetrics?.peakDBFS, format: .dBFS, positiveIsBetter: false)
                        metricCard(title: "RMS", input: inputMetrics.rmsDBFS, output: outputMetrics?.rmsDBFS, format: .dBFS, positiveIsBetter: false)
                        metricCard(title: "重心", input: inputMetrics.centroidHz, output: outputMetrics?.centroidHz, format: .hertz, positiveIsBetter: true)
                        metricCard(title: "12kHz+", input: inputMetrics.hf12Ratio, output: outputMetrics?.hf12Ratio, format: .ratio(5), positiveIsBetter: true)
                        metricCard(title: "16kHz+", input: inputMetrics.hf16Ratio, output: outputMetrics?.hf16Ratio, format: .ratio(6), positiveIsBetter: true)
                        metricCard(title: "18kHz+", input: inputMetrics.hf18Ratio, output: outputMetrics?.hf18Ratio, format: .ratio(6), positiveIsBetter: true)
                    }

                    bandChart(input: inputMetrics.bandEnergies, output: outputMetrics?.bandEnergies ?? [])
                }
            } else {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricCard(title: String, input: Double, output: Double?, format: MetricFormat, positiveIsBetter: Bool) -> some View {
        let delta = output.map { $0 - input }
        let color: Color = {
            guard let delta else { return .secondary }
            if abs(delta) < 0.000001 { return .secondary }
            let improved = positiveIsBetter ? delta > 0 : delta < 0
            return improved ? .green : .orange
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text("入力  \(formattedValue(input, format: format))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("出力  \(output.map { formattedValue($0, format: format) } ?? "--")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(output == nil ? .secondary : .primary)
            Text(delta.map { "差分  \(formattedDelta($0, format: format))" } ?? "差分  --")
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func bandChart(input: [BandEnergyMetric], output: [BandEnergyMetric]) -> some View {
        let outputMap = Dictionary(uniqueKeysWithValues: output.map { ($0.id, $0) })
        let pairs = input.map { ($0, outputMap[$0.id]) }
        let levels = pairs.flatMap { [$0.0.levelDB, $0.1?.levelDB ?? $0.0.levelDB] }
        let maxLevel = (levels.max() ?? 0) + 3
        let minLevel = min((levels.min() ?? -60), -40) - 3

        return VStack(alignment: .leading, spacing: 10) {
            Text("帯域別の見え方")
                .font(.headline)

            ForEach(pairs, id: \.0.id) { inputMetric, outputMetric in
                let delta = outputMetric.map { $0.levelDB - inputMetric.levelDB }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(inputMetric.label)
                            .font(.caption.bold())
                        Text(inputMetric.rangeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        bandBar(title: "入力", value: inputMetric.levelDB, minLevel: minLevel, maxLevel: maxLevel, tint: .blue)
                        bandBar(title: "出力", value: outputMetric?.levelDB, minLevel: minLevel, maxLevel: maxLevel, tint: .green)
                    }

                    Spacer(minLength: 0)

                    diffSummary(delta: delta)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func diffSummary(delta: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("差分")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(delta.map { formattedDelta($0, format: .dBFS) } ?? "--")
                .font(.caption.monospacedDigit())
                .foregroundStyle(deltaChipColor(for: delta))

            Capsule()
                .fill(deltaChipColor(for: delta).opacity(delta == nil ? 0.18 : 0.9))
                .frame(width: deltaChipWidth(for: delta), height: 8)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.35), lineWidth: delta == nil ? 0 : 0.6)
                }
        }
        .frame(width: 94, alignment: .trailing)
    }

    private func bandBar(title: String, value: Double?, minLevel: Double, maxLevel: Double, tint: Color) -> some View {
        let normalized = value.map { max(0, min(1, ($0 - minLevel) / max(maxLevel - minLevel, 1))) } ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.map { formattedValue($0, format: .dBFS) } ?? "--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * normalized)
                }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func deltaChipColor(for delta: Double?) -> Color {
        guard let delta else { return .secondary }
        let magnitude = abs(delta)
        if magnitude < 0.15 {
            return .secondary
        }
        return delta >= 0 ? .green : .red
    }

    private func deltaChipWidth(for delta: Double?) -> CGFloat {
        guard let delta else { return 18 }
        let magnitude = min(abs(delta), 3)
        return 18 + CGFloat(magnitude / 3) * 34
    }

    private var logSection: some View {
        HStack(alignment: .top, spacing: 14) {
            logCard(title: "補正ログ", text: job.logText, placeholder: "ここに補正ログが表示されます。")
            logCard(title: "マスタリングログ", text: job.masteringLogText, placeholder: "ここにマスタリングログが表示されます。")
        }
    }

    private func logCard(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var correctionStatusColor: Color {
        if job.isProcessing {
            return .orange
        }
        if job.lastError != nil {
            return .red
        }
        if job.hasExistingOutput {
            return .green
        }
        return .secondary
    }

    private var masteringStatusColor: Color {
        if job.isMastering {
            return .orange
        }
        if job.masteringLastError != nil {
            return .red
        }
        if job.hasExistingMasteredOutput {
            return .green
        }
        return .secondary
    }

    private var masteringProgressValue: Double {
        if !job.isMastering && job.masteringStatusMessage == "完了" {
            return 1
        }
        let total = Double(MasteringStep.allCases.count)
        let completed = Double(job.completedMasteringSteps.count)
        let activeBoost = job.masteringActiveStep == nil ? 0 : 0.5
        return min(0.98, (completed + activeBoost) / total)
    }

    private var masteringProgressLabel: String {
        if let step = job.masteringActiveStep {
            return "\(step.title) を実行中"
        }
        return job.masteringStatusMessage
    }

    private func startCorrectionProcessing() {
        guard let inputFile = job.inputFile else { return }

        Task {
            job.beginProcessing()

            do {
                let outputFile = try await AudioProcessingService().process(inputFile: inputFile) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }

                await MainActor.run {
                    job.beginMetricAnalysis()
                }

                async let correctedSnapshotTask: AudioPreviewSnapshot = Task.detached(priority: .utility) {
                    try AudioFileService.makePreviewSnapshot(for: outputFile)
                }.value
                async let correctedMetricsTask: AudioMetricSnapshot = Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: outputFile)
                }.value
                async let correctedSpectrogramTask: SpectrogramSnapshot = Task.detached(priority: .utility) {
                    try AudioFileService.makeSpectrogramSnapshot(for: outputFile)
                }.value

                let correctedSnapshot = try await correctedSnapshotTask
                let correctedMetrics = try await correctedMetricsTask
                let correctedSpectrogram = try await correctedSpectrogramTask

                await MainActor.run {
                    job.finishSuccess(outputFile)
                    preview.preparePreview(for: job.inputFile, target: .input)
                    preview.setPreviewSnapshot(correctedSnapshot, for: .corrected, sourceURL: outputFile)
                    preview.preparePreview(for: nil, target: .mastered)
                    job.finishOutputMetricAnalysis(correctedMetrics)
                    job.finishOutputSpectrogram(correctedSpectrogram)
                }
            } catch {
                await MainActor.run {
                    job.failMetricAnalysis()
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }

    private func startMasteringProcessing() {
        guard let correctedFile = job.outputFile else { return }

        Task {
            job.beginMastering()

            do {
                let masteredFile = try await MasteringService().process(
                    inputFile: correctedFile,
                    settings: job.editableMasteringSettings
                ) { message in
                    Task { @MainActor in
                        job.appendMasteringLog(message)
                    }
                }

                await MainActor.run {
                    job.beginMetricAnalysis()
                }

                async let masteredSnapshotTask: AudioPreviewSnapshot = Task.detached(priority: .utility) {
                    try AudioFileService.makePreviewSnapshot(for: masteredFile)
                }.value
                async let masteredMetricsTask: AudioMetricSnapshot = Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: masteredFile)
                }.value
                async let masteredSpectrogramTask: SpectrogramSnapshot = Task.detached(priority: .utility) {
                    try AudioFileService.makeSpectrogramSnapshot(for: masteredFile)
                }.value

                let masteredSnapshot = try await masteredSnapshotTask
                let masteredMetrics = try await masteredMetricsTask
                let masteredSpectrogram = try await masteredSpectrogramTask

                await MainActor.run {
                    job.finishMasteringSuccess(masteredFile)
                    preview.setPreviewSnapshot(masteredSnapshot, for: .mastered, sourceURL: masteredFile)
                    job.finishMasteredMetricAnalysis(masteredMetrics)
                    job.finishMasteredSpectrogram(masteredSpectrogram)
                }
            } catch {
                await MainActor.run {
                    job.failMetricAnalysis()
                    job.finishMasteringFailure(error.localizedDescription)
                }
            }
        }
    }

    private enum MetricTarget {
        case input
        case corrected
        case mastered
    }

    private enum MetricFormat {
        case dBFS
        case hertz
        case ratio(Int)
    }

    private func analyzeMetrics(for url: URL, target: MetricTarget) {
        Task {
            await MainActor.run {
                job.beginMetricAnalysis()
            }

            do {
                let metrics = try await Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: url)
                }.value
                let spectrogram = try await Task.detached(priority: .utility) {
                    try AudioFileService.makeSpectrogramSnapshot(for: url)
                }.value

                await MainActor.run {
                    switch target {
                    case .input:
                        job.finishInputMetricAnalysis(metrics)
                        job.finishInputSpectrogram(spectrogram)
                    case .corrected:
                        job.finishOutputMetricAnalysis(metrics)
                        job.finishOutputSpectrogram(spectrogram)
                    case .mastered:
                        job.finishMasteredMetricAnalysis(metrics)
                        job.finishMasteredSpectrogram(spectrogram)
                    }
                }
            } catch {
                await MainActor.run {
                    job.failMetricAnalysis()
                }
            }
        }
    }

    private func preparePreviewCards() {
        preview.preparePreview(for: job.inputFile, target: .input)
        preview.preparePreview(for: job.hasExistingOutput ? job.outputFile : nil, target: .corrected)
        preview.preparePreview(for: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, target: .mastered)
    }

    private func exportCorrectedAudio() {
        guard let sourceURL = job.outputFile, let inputFile = job.inputFile else { return }
        let suggestedName = AudioProcessingService.defaultOutputURL(for: inputFile).lastPathComponent
        let allowedTypes = allowedAudioTypes(for: sourceURL.pathExtension)
        guard let destinationURL = FilePanelService.chooseSaveLocation(suggestedFileName: suggestedName, allowedContentTypes: allowedTypes) else {
            return
        }
        do {
            try replaceFile(from: sourceURL, to: destinationURL)
            job.finishCorrectedExport(destinationURL)
        } catch {
            job.finishFailure(error.localizedDescription)
        }
    }

    private func exportMasteredAudio() {
        guard let sourceURL = job.masteredOutputFile else { return }
        let baseURL = job.inputFile.map { MasteringService.defaultOutputURL(for: $0) } ?? sourceURL
        let suggestedName = baseURL.lastPathComponent
        let allowedTypes = allowedAudioTypes(for: sourceURL.pathExtension)
        guard let destinationURL = FilePanelService.chooseSaveLocation(suggestedFileName: suggestedName, allowedContentTypes: allowedTypes) else {
            return
        }
        do {
            try replaceFile(from: sourceURL, to: destinationURL)
            job.finishMasteredExport(destinationURL)
        } catch {
            job.finishMasteringFailure(error.localizedDescription)
        }
    }

    private func replaceFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func allowedAudioTypes(for fileExtension: String) -> [UTType] {
        [UTType(filenameExtension: fileExtension), .audio].compactMap { $0 }
    }

    private enum CompressorField {
        case threshold
        case ratio
    }

    private func compressorControlCard(
        title: String,
        settings: BandCompressorSettings,
        onChange: @escaping (CompressorField, Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(String(format: "Threshold %.1f dB / Ratio %.2f", settings.thresholdDB, settings.ratio))
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: binding(get: { Double(settings.thresholdDB) }, set: { onChange(.threshold, $0) }), in: -36 ... -12, step: 0.5)
            Slider(value: binding(get: { Double(settings.ratio) }, set: { onChange(.ratio, $0) }), in: 1.1 ... 4.0, step: 0.05)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sliderCard<Content: View>(title: String, valueText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(valueText)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonFileURL(for side: AudioComparisonSide) -> URL? {
        switch preview.comparisonTarget(for: side) {
        case .input:
            return job.inputFile
        case .corrected:
            return job.hasExistingOutput ? job.outputFile : nil
        case .mastered:
            return job.hasExistingMasteredOutput ? job.masteredOutputFile : nil
        }
    }

    private func binding<Value>(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { @MainActor in get() },
            set: { @MainActor newValue in set(newValue) }
        )
    }

    private func formattedValue(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: "%.2f dB", value)
        case .hertz:
            return String(format: "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: "%.\(decimals)f", value)
        }
    }

    private func formattedDelta(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: value >= 0 ? "+%.2f dB" : "%.2f dB", value)
        case .hertz:
            return String(format: value >= 0 ? "+%.0f Hz" : "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)
        }
    }
}

#Preview {
    ContentView()
}
