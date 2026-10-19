import SwiftUI

/// Bruno 风格响应观测面板：清晰的状态指标卡片、分栏布局快速切换、实时流式气泡与指标分析
public struct ResponseInspectorView: View {
    let response: RPCResponse?
    let streamEvents: [StreamEvent]
    let currentRequest: RequestModel?
    let isExecuting: Bool
    @ObservedObject var appState: AppState

    @State private var selectedTab: ResponseTab = .body
    @State private var isDiffCopied: Bool = false

    enum ResponseTab: String, CaseIterable, Identifiable {
        case body = "响应体"
        case headers = "响应头"
        case timeline = "时间线"
        case assertions = "断言测试"
        case diff = "快照对比"
        case stats = "统计指标"

        var id: String { rawValue }
    }

    private let primaryTabs: [ResponseTab] = [.body, .headers, .timeline]
    private let secondaryTabs: [ResponseTab] = [.assertions, .diff, .stats]

    private var visibleTabs: [ResponseTab] {
        if primaryTabs.contains(selectedTab) {
            return primaryTabs
        } else {
            return primaryTabs + [selectedTab]
        }
    }

    private func tabBadge(_ tab: ResponseTab) -> String? {
        switch tab {
        case .body:
            return nil
        case .headers:
            let totalHeaders = (response?.initialMetadata.count ?? 0) + (response?.trailingMetadata.count ?? 0)
            return totalHeaders > 0 ? "\(totalHeaders)" : nil
        case .timeline:
            let allEvents = (response?.streamEvents ?? []) + streamEvents
            if !allEvents.isEmpty || currentRequest?.callType != .unary {
                return "\(allEvents.count)"
            }
            return nil
        case .assertions:
            if let resp = response, !resp.assertionResults.isEmpty {
                let passed = resp.assertionResults.filter { $0.passed }.count
                return "\(passed)/\(resp.assertionResults.count)"
            } else if let req = currentRequest, !req.assertions.isEmpty {
                return "\(req.assertions.filter { $0.isEnabled }.count)"
            }
            return nil
        case .diff:
            let hasSnapshot = (currentRequest != nil && appState.responseSnapshots[currentRequest!.id] != nil)
            return hasSnapshot ? "快照" : nil
        case .stats:
            return nil
        }
    }

    private var hasSecondaryActiveBadge: Bool {
        secondaryTabs.contains { tabBadge($0) != nil }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 整合一体化响应菜单栏 (左侧 Bruno 风格折叠选项卡 + 右侧状态与时延)
            HStack(spacing: 0) {
                // 左侧 Bruno 风格折叠选项卡 (常驻 Response, Headers, Timeline + 更多选单)
                HStack(spacing: 0) {
                    ForEach(visibleTabs) { tab in
                        tabButton(tab, badge: tabBadge(tab))
                    }

                    // Bruno 风格折叠“更多”菜单
                    Menu {
                        ForEach(secondaryTabs) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                HStack {
                                    if selectedTab == tab {
                                        Text("✓ " + tab.rawValue)
                                    } else {
                                        Text(tab.rawValue)
                                    }
                                    if let b = tabBadge(tab) {
                                        Text(" (\(b))")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("更多" + (hasSecondaryActiveBadge && !secondaryTabs.contains(selectedTab) ? " •" : ""))
                            .font(.system(size: 11, weight: secondaryTabs.contains(selectedTab) ? .semibold : .regular))
                            .foregroundColor(secondaryTabs.contains(selectedTab) ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("更多响应观测 (断言结果、快照对比、统计指标)")
                }

                Spacer(minLength: 8)

                // 右侧状态码、时延、数据尺寸及清空
                rightStatusView
            }
            .padding(.horizontal, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 选项卡内容区
            Group {
                switch selectedTab {
                case .body:
                    responseBodyView
                case .assertions:
                    assertionsResultsView
                case .diff:
                    responseDiffView
                case .timeline:
                    streamTimelineView
                case .headers:
                    headersTrailersView
                case .stats:
                    statisticsView
                }
            }
            .padding(12)
        }
    }

    private func tabButton(_ tab: ResponseTab, badge: String?) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .lineLimit(1)

                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if selectedTab == tab {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    @ViewBuilder
    private var rightStatusView: some View {
        HStack(spacing: 6) {
            if let resp = response {
                // Status Badge (0 OK / Error)
                HStack(spacing: 4) {
                    Circle()
                        .fill(resp.isSuccess ? Color.green : Color.red)
                        .frame(width: 5, height: 5)

                    Text("\(resp.statusCode) \(resp.statusName)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(resp.isSuccess ? .green : .red)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((resp.isSuccess ? Color.green : Color.red).opacity(0.12))
                .cornerRadius(4)

                // Latency Pill
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                    Text(String(format: "%.1f ms", resp.durationMs))
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(4)

                // Size Pill
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                    Text("\(resp.responseSize) B")
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(4)

                // 断言执行结果指示徽标
                if !resp.assertionResults.isEmpty {
                    let passed = resp.assertionResults.filter { $0.passed }.count
                    let total = resp.assertionResults.count
                    let allPassed = passed == total

                    Button(action: {
                        selectedTab = .assertions
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: allPassed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 8))
                            Text(allPassed ? "\(passed)/\(total) 断言通过" : "\(total - passed) 断言失败")
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(allPassed ? .green : .red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((allPassed ? Color.green : Color.red).opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(allPassed ? "所有断言校验全部通过！点击查看明细" : "存在未通过的断言校验，点击查看明细")
                }

                // 变量提取成功指示徽标
                if !resp.extractedVariables.isEmpty {
                    Button(action: {
                        selectedTab = .assertions
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                            Text("已提取 \(resp.extractedVariables.count) 变量")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("已自动更新环境变量:\n" + resp.extractedVariables.map { "{{$0.key}} = \($0.value)" }.joined(separator: "\n"))
                }

                // 清空响应按钮
                Button(action: {
                    if let reqId = currentRequest?.id {
                        appState.responses.removeValue(forKey: reqId)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("清空当前响应内容")

                // Bruno 风格分栏方向快速切换 (左右并排 ⇄ 上下并排)
                Button(action: {
                    appState.layoutMode = (appState.layoutMode == .horizontal ? .vertical : .horizontal)
                }) {
                    Image(systemName: appState.layoutMode == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("切换分栏方向: 当前为\(appState.layoutMode.rawValue)，点击切换为\(appState.layoutMode == .horizontal ? "上下并排" : "左右并排")")

            } else if isExecuting {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Sending...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                Text("Ready")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - 1. Response Body

    private var responseBodyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("JSON Response Body")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let payload = response?.responsePayload, !payload.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload, forType: .string)
                    }) {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                }
            }

            ScrollView {
                Text(response?.responsePayload ?? "/* 尚未执行调用，点击 Send 按钮以查看返回结果 */")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - 2. Stream Timeline

    private var streamTimelineView: some View {
        VStack(alignment: .leading, spacing: 8) {
            let events = (response?.streamEvents ?? []) + streamEvents
            HStack {
                Text("流式消息时序流水 (Streaming Timeline)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("共 \(events.count) 帧")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if events.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("当前无流式帧。对于 Server Streaming / Bidi 流，每帧收发将在此处实时流水记录。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(events) { ev in
                            StreamEventBubbleView(event: ev)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2.5 响应快照对比视图 (Response Snapshot & JSON Semantic Diff)

    @ViewBuilder
    private var responseDiffView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let req = currentRequest {
                let snapshot = appState.responseSnapshots[req.id]

                if let base = snapshot {
                    if let curr = response {
                        let report = ResponseDiffEngine.shared.compare(baseline: base, current: curr)

                        // 顶栏操作区
                        HStack(spacing: 8) {
                            // 快照时间标签
                            HStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                Text("基准快照 (\(base.statusName))")
                                    .font(.system(size: 11, weight: .semibold))
                            }

                            Spacer()

                            // 更新快照
                            Button("更新快照") {
                                appState.saveResponseSnapshot(for: req.id, response: curr)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .buttonStyle(.plain)

                            // 复制 Diff 报告
                            Button(action: {
                                let text = report.exportMarkdownReport()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                isDiffCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                    isDiffCopied = false
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: isDiffCopied ? "checkmark" : "doc.on.doc")
                                    Text(isDiffCopied ? "已复制" : "复制 Diff")
                                }
                                .font(.system(size: 11))
                            }
                            .foregroundColor(isDiffCopied ? .green : .primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .buttonStyle(.plain)

                            // 清除快照
                            Button("清除") {
                                appState.clearResponseSnapshot(for: req.id)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(4)
                            .buttonStyle(.plain)
                        }

                        // 差异指标对比横幅
                        HStack(spacing: 8) {
                            if report.isIdentical {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                    Text("响应数据完全一致 (Zero Diff)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                            } else {
                                if report.addedCount > 0 {
                                    Text("+\(report.addedCount) 新增")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                if report.removedCount > 0 {
                                    Text("-\(report.removedCount) 删除")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }

                            // 耗时差
                            let latStr = String(format: "%+.1f ms", report.latencyDeltaMs)
                            HStack(spacing: 3) {
                                Image(systemName: "bolt")
                                Text("耗时: \(latStr)")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(report.latencyDeltaMs <= 0 ? .green : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)

                            // 体积差
                            let sizeStr = report.sizeDeltaBytes >= 0 ? "+\(report.sizeDeltaBytes) B" : "\(report.sizeDeltaBytes) B"
                            HStack(spacing: 3) {
                                Image(systemName: "archivebox")
                                Text("体积: \(sizeStr)")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)

                            Spacer()
                        }

                        // Diff 行展示区
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(report.lines) { line in
                                    HStack(alignment: .top, spacing: 6) {
                                        // 旧行号
                                        Text(line.oldLineNumber.map { "\($0)" } ?? " ")
                                            .frame(width: 26, alignment: .trailing)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.6))

                                        // 新行号
                                        Text(line.newLineNumber.map { "\($0)" } ?? " ")
                                            .frame(width: 26, alignment: .trailing)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.6))

                                        // 符号
                                        Text(line.kind.rawValue)
                                            .frame(width: 12, alignment: .center)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(line.kind == .added ? .green : (line.kind == .removed ? .red : .secondary))

                                        // 内容
                                        Text(line.content)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(line.kind == .added ? .green : (line.kind == .removed ? .red : .primary))
                                            .textSelection(.enabled)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(line.kind == .added ? Color.green.opacity(0.1) : (line.kind == .removed ? Color.red.opacity(0.1) : Color.clear))
                                }
                            }
                            .padding(6)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                        )

                    } else {
                        // 有快照但当前未发起请求
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "camera.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("已保存基准快照 (状态: \(base.statusName), 耗时: \(String(format: "%.1f", base.durationMs)) ms)")
                                .font(.system(size: 12, weight: .semibold))
                            Text("点击顶部【发送 (⌘↵)】即可将最新响应与此快照进行实时差异对比")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Button("清除此快照") {
                                appState.clearResponseSnapshot(for: req.id)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // 无快照
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("暂无基准快照 (No Baseline Snapshot)")
                            .font(.system(size: 13, weight: .bold))
                        Text("将当前响应保存为快照后，可实时检测后端代码变更后的字段修改、延迟增减与状态码差异。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)

                        if let curr = response {
                            Button(action: {
                                appState.saveResponseSnapshot(for: req.id, response: curr)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                    Text("保存当前响应为基线快照")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("请先发送一次请求以捕获响应")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "cursorarrow.and.square.on.square.dashed")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("请先在左侧选择一个有效请求")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 3. Headers & Trailers

    private var headersTrailersView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Initial Metadata
                VStack(alignment: .leading, spacing: 6) {
                    Text("Initial Metadata (响应头):")
                        .font(.system(size: 11, weight: .bold))

                    if let headers = response?.initialMetadata, !headers.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(headers.keys.sorted(), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .frame(width: 160, alignment: .leading)
                                    Text(headers[key] ?? "")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                Divider()
                            }
                        }
                    } else {
                        Text("无 Initial Metadata").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                // Trailing Metadata
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trailing Metadata (Trailers):")
                        .font(.system(size: 11, weight: .bold))

                    if let trailers = response?.trailingMetadata, !trailers.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(trailers.keys.sorted(), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .frame(width: 160, alignment: .leading)
                                    Text(trailers[key] ?? "")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                Divider()
                            }
                        }
                    } else {
                        Text("无 Trailing Metadata").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 4. Statistics

    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("性能度量与耗时分解 (Timing Stats):")
                .font(.system(size: 11, weight: .bold))

            if let stats = response?.stats {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("DNS Lookup").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(String(format: "%.2f ms", stats.dnsLookupMs)).font(.system(size: 11, design: .monospaced))
                    }
                    GridRow {
                        Text("TCP Handshake").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(String(format: "%.2f ms", stats.tcpConnectMs)).font(.system(size: 11, design: .monospaced))
                    }
                    GridRow {
                        Text("TLS Handshake").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(String(format: "%.2f ms", stats.tlsHandshakeMs)).font(.system(size: 11, design: .monospaced))
                    }
                    GridRow {
                        Text("Time to First Byte (TTFB)").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(String(format: "%.2f ms", stats.ttfbMs)).font(.system(size: 11, design: .monospaced))
                    }
                    GridRow {
                        Text("总往返耗时 (Total Duration)").font(.system(size: 11, weight: .bold))
                        Text(String(format: "%.2f ms", stats.totalDurationMs)).font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            } else {
                Text("暂无网络统计数据").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }



    // MARK: - 断言测试与响应变量结果面板 (Bruno Assertions & Extracted Vars)

    private var assertionsResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let resp = response, !resp.assertionResults.isEmpty {
                let passed = resp.assertionResults.filter { $0.passed }.count
                let total = resp.assertionResults.count
                let allPassed = passed == total

                // 汇总指示卡片
                HStack(spacing: 10) {
                    Image(systemName: allPassed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(allPassed ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(allPassed ? "所有断言校验通过 (\(passed)/\(total))" : "部分断言未通过 (\(passed)/\(total) 通过)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(allPassed ? .green : .red)
                        Text(allPassed ? "返回状态码、时延和载荷完全符合声明式预期。" : "存在与预期不符的返回字段，请检查下方断言明细。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background((allPassed ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(8)

                // 逐条结果列表
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(resp.assertionResults) { res in
                            HStack(spacing: 10) {
                                Image(systemName: res.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(res.passed ? .green : .red)
                                    .font(.system(size: 14))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(res.expression)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        Text(res.op.shortSymbol)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        if res.op != .isDefined && res.op != .isNullOrEmpty {
                                            Text(res.expectedValue)
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text("实际值: \(res.actualValue.isEmpty ? "(空)" : res.actualValue)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text(res.message)
                                            .font(.system(size: 10))
                                            .foregroundColor(res.passed ? .secondary : .red)
                                    }
                                }

                                Spacer()

                                Text(res.passed ? "PASSED" : "FAILED")
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background((res.passed ? Color.green : Color.red).opacity(0.12))
                                    .foregroundColor(res.passed ? .green : .red)
                                    .cornerRadius(3)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                        }

                        // 如果该请求同时触发了响应变量提取，列出已同步项
                        if !resp.extractedVariables.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 11))
                                    Text("已提取并同步至活动环境变量 (\(resp.extractedVariables.count) 项)")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.top, 8)

                                ForEach(Array(resp.extractedVariables.sorted(by: { $0.key < $1.key })), id: \.key) { k, v in
                                    HStack {
                                        Text("{{\(k)}}")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.purple)
                                        Text("=")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Text(v)
                                            .font(.system(size: 11, design: .monospaced))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("已写入环境")
                                            .font(.system(size: 9))
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.06))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("当前请求尚未配置断言或尚未触发调用")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("可在左侧请求编辑器【断言测试】选项卡中添加免代码断言规则。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 流式气泡单个条目
struct StreamEventBubbleView: View {
    let event: StreamEvent

    var isOutbound: Bool {
        event.direction == .outbound
    }

    var body: some View {
        HStack {
            if isOutbound { Spacer() }

            VStack(alignment: isOutbound ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isOutbound ? "⬆️ Client Outbound" : "⬇️ Server Inbound")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isOutbound ? .blue : .purple)

                    Text("• \(event.byteSize) B")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    if !event.summary.isEmpty {
                        Text("• \(event.summary)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                if event.isHalfClose {
                    Text("--- End Of Stream (Half-Close) ---")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(4)
                } else {
                    Text(event.payload)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(isOutbound ? Color.blue.opacity(0.08) : Color.purple.opacity(0.08))
                        .cornerRadius(6)
                }
            }

            if !isOutbound { Spacer() }
        }
    }
}
