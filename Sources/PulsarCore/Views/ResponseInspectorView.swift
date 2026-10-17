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
