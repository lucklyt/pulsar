import SwiftUI

/// Bruno 风格集合自动化测试运行器窗口 (Collection Runner View)
public struct CollectionRunnerView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool
    let initialConfig: CollectionRunConfig

    @State private var config: CollectionRunConfig
    @State private var isRunning: Bool = false
    @State private var isCompleted: Bool = false
    @State private var currentProgress: (current: Int, total: Int)? = nil
    @State private var summary: CollectionRunSummary? = nil
    @State private var selectedFilter: ResultFilter = .all
    @State private var expandedResultIds: Set<UUID> = []
    @State private var runTask: Task<Void, Never>? = nil
    @State private var isExportCopied: Bool = false

    enum ResultFilter: String, CaseIterable, Identifiable {
        case all = "全部用例"
        case failed = "仅看失败"
        case passed = "仅看通过"

        var id: String { rawValue }
    }

    public init(appState: AppState, isPresented: Binding<Bool>, config: CollectionRunConfig) {
        self.appState = appState
        self._isPresented = isPresented
        self.initialConfig = config
        self._config = State(initialValue: config)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏：标题与关闭
            headerView

            Divider()

            if !isRunning && !isCompleted {
                // 1. 配置预检界面
                configurationView
            } else {
                // 2. 运行与结果展示界面
                runningAndResultsView
            }
        }
        .frame(width: 780, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 顶栏

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("集合自动化运行器 (Collection Runner)")
                    .font(.system(size: 14, weight: .bold))

                let scope = config.folderName.map { "\(config.collectionName) / \($0)" } ?? config.collectionName
                Text("运行范围: \(scope)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isRunning {
                Button("中止运行") {
                    cancelRunning()
                }
                .foregroundColor(.red)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12))
                .cornerRadius(5)
            }

            Button(action: {
                cancelRunning()
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 配置视图

    private var targetRequests: [RequestModel] {
        guard let col = appState.workspace.collections.first(where: { $0.id == config.collectionId }) else {
            return []
        }
        if let fId = config.folderId {
            return col.requests.filter { $0.folderId == fId }
        } else {
            return col.requests
        }
    }

    private var configurationView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                // 用例数量统计卡片
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("待执行请求")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(targetRequests.count) 个用例")
                            .font(.system(size: 18, weight: .bold))
                    }

                    Divider().frame(height: 36)

                    let totalAssertions = targetRequests.reduce(0) { $0 + $1.assertions.filter { $0.isEnabled }.count }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("包含断言规则")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(totalAssertions) 项检查")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }

                    Divider().frame(height: 36)

                    let totalVars = targetRequests.reduce(0) { $0 + $1.responseVars.filter { $0.isEnabled }.count }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下游变量提取")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(totalVars) 个字段")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 选项设置卡片
                VStack(alignment: .leading, spacing: 14) {
                    // 环境选择
                    HStack {
                        Text("运行环境:")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 90, alignment: .leading)

                        Picker("", selection: $config.environmentId) {
                            Text("无环境 (直接调用)").tag(nil as UUID?)
                            ForEach(appState.workspace.environments) { env in
                                Text("\(env.name)\(env.isProduction ? " [PROD]" : "")").tag(env.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }

                    // 请求延迟
                    HStack {
                        Text("请求间隔:")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 90, alignment: .leading)

                        Slider(value: $config.delayMs, in: 0...1000, step: 25)
                            .frame(width: 180)

                        Text("\(Int(config.delayMs)) ms")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                    }

                    // 熔断控制
                    HStack {
                        Text("异常熔断:")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 90, alignment: .leading)

                        Toggle("遇到首个失败用例时立即停止运行", isOn: $config.stopOnFirstFailure)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal, 36)

            Spacer()

            // 底部启动按钮
            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(action: startRunning) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("开始批量运行 (\(targetRequests.count) 个用例)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(targetRequests.isEmpty)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - 运行中与结果视图

    private var runningAndResultsView: some View {
        VStack(spacing: 0) {
            // 状态横幅
            if isRunning {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    if let p = currentProgress {
                        Text("正在运行 (\(p.current)/\(p.total)) ...")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("准备执行...")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
            } else if let s = summary {
                summaryBanner(s)
            }

            Divider()

            // 过滤器工具栏
            HStack {
                Picker("", selection: $selectedFilter) {
                    ForEach(ResultFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                if let s = summary {
                    // 导出 Markdown 报告
                    Button(action: {
                        let report = s.exportMarkdownReport()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                        isExportCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            isExportCopied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExportCopied ? "checkmark" : "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text(isExportCopied ? "报告已复制" : "导出 Markdown 报告")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(isExportCopied ? .green : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    // 重新运行按钮
                    Button(action: startRunning) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("重新运行")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // 用例列表
            let filteredResults = getFilteredResults()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredResults) { result in
                        resultRowView(result)
                    }
                }
                .padding(12)
            }
        }
    }

    private func summaryBanner(_ s: CollectionRunSummary) -> some View {
        HStack(spacing: 16) {
            Image(systemName: s.isAllPassed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                .font(.system(size: 24))
                .foregroundColor(s.isAllPassed ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                Text(s.isAllPassed ? "全部测试通过 (ALL PASSED)" : "存在失败用例 (TESTS FAILED)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(s.isAllPassed ? .green : .red)

                Text("用例: \(s.passedRequests)/\(s.totalRequests) 通过  |  断言: \(s.passedAssertions)/\(s.totalAssertions) 通过  |  总耗时: \(String(format: "%.1f", s.totalDurationMs)) ms  |  平均: \(String(format: "%.1f", s.averageDurationMs)) ms")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(s.isAllPassed ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
    }

    private func resultRowView(_ result: RequestRunResult) -> some View {
        let isExpanded = expandedResultIds.contains(result.id)

        return VStack(alignment: .leading, spacing: 0) {
            // 主条目
            HStack(spacing: 10) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isSuccess ? .green : .red)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.requestName)
                            .font(.system(size: 12, weight: .semibold))

                        Text(result.callType.shortTag)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(3)
                    }

                    Text("\(result.serviceName)/\(result.methodName)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 耗时胶囊
                Text("\(String(format: "%.1f", result.durationMs)) ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)

                // 状态码
                Text("\(result.statusCode)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(result.statusCode == 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((result.statusCode == 0 ? Color.green : Color.red).opacity(0.12))
                    .cornerRadius(4)

                // 断言徽章
                if !result.assertionResults.isEmpty {
                    let passedCount = result.assertionResults.filter { $0.passed }.count
                    let totalCount = result.assertionResults.count
                    let isAssertAllPassed = passedCount == totalCount

                    Text("\(passedCount)/\(totalCount) 断言")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isAssertAllPassed ? .green : .red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((isAssertAllPassed ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(3)
                }

                // 展开折叠箭头
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if isExpanded {
                    expandedResultIds.remove(result.id)
                } else {
                    expandedResultIds.insert(result.id)
                }
            }

            // 展开详情
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if let err = result.errorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                    }

                    // 断言明细
                    if !result.assertionResults.isEmpty {
                        Text("断言评估详情:")
                            .font(.system(size: 11, weight: .semibold))

                        VStack(spacing: 4) {
                            ForEach(result.assertionResults) { ar in
                                HStack(spacing: 6) {
                                    Image(systemName: ar.passed ? "checkmark" : "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ar.passed ? .green : .red)

                                    Text(ar.expression)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))

                                    Text(ar.op.rawValue)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)

                                    if !ar.expectedValue.isEmpty {
                                        Text("\"\(ar.expectedValue)\"")
                                            .font(.system(size: 11, design: .monospaced))
                                    }

                                    Spacer()

                                    Text(ar.message)
                                        .font(.system(size: 10))
                                        .foregroundColor(ar.passed ? .secondary : .red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            }
                        }
                    }

                    // 变量提取明细
                    if !result.extractedVariables.isEmpty {
                        Text("下游链路变量提取:")
                            .font(.system(size: 11, weight: .semibold))

                        HStack(spacing: 6) {
                            ForEach(Array(result.extractedVariables.keys.sorted()), id: \.self) { key in
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.purple)
                                    Text("{{\(key)}} = \(result.extractedVariables[key] ?? "")")
                                        .font(.system(size: 10, design: .monospaced))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }

                    // 响应载荷预览
                    if !result.responsePayload.isEmpty {
                        Text("响应数据载荷 (Payload):")
                            .font(.system(size: 11, weight: .semibold))

                        Text(result.responsePayload)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(8)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        )
    }

    private func getFilteredResults() -> [RequestRunResult] {
        guard let s = summary else { return [] }
        switch selectedFilter {
        case .all:
            return s.results
        case .failed:
            return s.results.filter { !$0.isSuccess }
        case .passed:
            return s.results.filter { $0.isSuccess }
        }
    }

    private func startRunning() {
        isRunning = true
        isCompleted = false
        currentProgress = (0, targetRequests.count)
        summary = nil

        let requestsToRun = targetRequests
        let runnerConfig = config
        let selectedEnv = appState.workspace.environments.first(where: { $0.id == config.environmentId })
        let globalVars = appState.workspace.globalVariables

        runTask = Task {
            let res = await CollectionRunnerEngine.shared.run(
                config: runnerConfig,
                requests: requestsToRun,
                baseEnvironment: selectedEnv,
                globalVariables: globalVars,
                resolveEffectiveConfig: { req in
                    appState.resolveEffectiveConfig(for: req)
                },
                isCancelled: {
                    Task.isCancelled
                },
                onProgress: { curr, total, latestResult in
                    Task { @MainActor in
                        self.currentProgress = (curr, total)
                    }
                }
            )

            await MainActor.run {
                self.summary = res
                self.isRunning = false
                self.isCompleted = true
            }
        }
    }

    private func cancelRunning() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }
}
