import SwiftUI

/// Bruno 风格响应观测面板：清晰的状态指标卡片、分栏布局快速切换、实时流式气泡与指标分析
public struct ResponseInspectorView: View {
    let response: RPCResponse?
    let streamEvents: [StreamEvent]
    let currentRequest: RequestModel?
    let isExecuting: Bool
    @ObservedObject var appState: AppState

    @State private var selectedTab: ResponseTab = .body

    enum ResponseTab: String, CaseIterable, Identifiable {
        case body = "响应体"
        case assertions = "断言测试"
        case headers = "响应头"
        case timeline = "时间线"
        case stats = "统计指标"
        case grpcurl = "CLI 导出"

        var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 整合一体化响应菜单栏 (左侧 Bruno 紧凑选项卡 + 右侧状态与时延)
            HStack(spacing: 0) {
                // 左侧 Bruno 风格紧凑选项卡 (自适应内容宽度，零多余空白)
                HStack(spacing: 0) {
                    tabButton(.body, badge: nil)

                    if let resp = response, !resp.assertionResults.isEmpty {
                        let passed = resp.assertionResults.filter { $0.passed }.count
                        tabButton(.assertions, badge: "\(passed)/\(resp.assertionResults.count)")
                    } else if let req = currentRequest, !req.assertions.isEmpty {
                        tabButton(.assertions, badge: "\(req.assertions.filter { $0.isEnabled }.count)")
                    }

                    let totalHeaders = (response?.initialMetadata.count ?? 0) + (response?.trailingMetadata.count ?? 0)
                    tabButton(.headers, badge: totalHeaders > 0 ? "\(totalHeaders)" : nil)

                    let allEvents = (response?.streamEvents ?? []) + streamEvents
                    if !allEvents.isEmpty || currentRequest?.callType != .unary {
                        tabButton(.timeline, badge: "\(allEvents.count)")
                    }

                    tabButton(.stats, badge: nil)
                    tabButton(.grpcurl, badge: "cURL")
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
                case .timeline:
                    streamTimelineView
                case .headers:
                    headersTrailersView
                case .stats:
                    statisticsView
                case .grpcurl:
                    grpcurlExportView
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

    // MARK: - 5. grpcurl Command

    private var grpcurlExportView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("终端复现指令 (grpcurl CLI):")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: {
                    if let req = currentRequest {
                        let activeImportPaths = ProtoRepository.shared.importPaths.filter { $0.isEnabled }.map { $0.path }
                        let cmd = GrpcurlExporter.shared.export(
                            request: req,
                            resolvedAddress: req.address,
                            resolvedPayload: req.payload,
                            importPaths: activeImportPaths
                        )
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    }
                }) {
                    Label("复制命令", systemImage: "terminal")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderedProminent)
            }

            if let req = currentRequest {
                let activeImportPaths = ProtoRepository.shared.importPaths.filter { $0.isEnabled }.map { $0.path }
                let cmd = GrpcurlExporter.shared.export(
                    request: req,
                    resolvedAddress: req.address,
                    resolvedPayload: req.payload,
                    importPaths: activeImportPaths
                )
                ScrollView {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
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
