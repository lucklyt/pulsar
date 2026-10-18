import SwiftUI

/// Bruno 风格请求主控制栏：名称与保存操作、一体化 URL 与方法胶囊、Proto 服务快速选单及发送按钮
public struct RequestHeaderView: View {
    @Binding var request: RequestModel
    @ObservedObject var appState: AppState

    @State private var isProtoMethodMenuPresented: Bool = false

    public var body: some View {
        VStack(spacing: 8) {
            // 第一行：请求标题与快捷操作 (Save, Copy CLI)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))

                    TextField("请求标题", text: Binding(
                        get: { request.name },
                        set: {
                            request.name = $0
                            appState.markDirty(id: request.id)
                        }
                    ))
                    .font(.system(size: 14, weight: .bold))
                    .textFieldStyle(.plain)
                }

                Spacer()

                // Bruno 风格 Save 按钮 (带未保存高亮与 ⌘S 快捷键)
                Button(action: {
                    appState.saveActiveRequest()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("保存")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)

                        Text("⌘S")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(appState.dirtyTabIds.contains(request.id) ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .keyboardShortcut("s", modifiers: .command)
                .help("保存修改 (⌘S)")
            }

            // 第二行：Bruno 一体化地址与发送控制栏 (URL Bar)
            HStack(spacing: 8) {
                // 一体化输入卡片
                HStack(spacing: 0) {
                    // Method 类型下拉选择器 (Bruno 风格彩色胶囊)
                    Menu {
                        ForEach(GRPCCallType.allCases) { type in
                            Button(type.displayName) {
                                request.callType = type
                                appState.markDirty(id: request.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(request.callType.shortTag)
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundColor(callTypeColor)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(callTypeColor.opacity(0.12))
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 20)

                    // gRPC 目标地址输入框
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))

                        TextField("gRPC 目标地址 (如 {{grpc_host}}:{{grpc_port}} 或 nacos://...)", text: Binding(
                            get: { request.address },
                            set: {
                                request.address = $0
                                appState.markDirty(id: request.id)
                            }
                        ))
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.plain)

                        if request.address.contains("{{") {
                            let unresolved = EnvironmentEngine.shared.findUnresolvedVariables(
                                in: request.address,
                                environment: appState.activeEnvironment,
                                globalVariables: appState.workspace.globalVariables
                            )
                            if !unresolved.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                    Text(unresolved.joined(separator: ", "))
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(3)
                                .help("存在未定义变量: \(unresolved.joined(separator: ", "))")
                            } else {
                                let resolved = EnvironmentEngine.shared.resolve(
                                    template: request.address,
                                    environment: appState.activeEnvironment,
                                    globalVariables: appState.workspace.globalVariables
                                )
                                Text("VAR")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(3)
                                    .help("解析结果: \(resolved)")
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                )

                // 发送 / 终止按钮 (Bruno 风格显眼蓝色大按钮)
                if appState.isExecuting {
                    Button(action: {
                        appState.cancelExecution()
                    }) {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("取消")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                } else {
                    Button(action: {
                        appState.executeCurrentRequest()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                            Text("发送")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text("⌘↵")
                                .font(.system(size: 10, design: .monospaced))
                                .opacity(0.7)
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("发送 gRPC 请求 (⌘ + Return)")
                }
            }

            // 第三行：Service 与 Method 选择栏 (带 Proto 快速填充菜单)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("服务:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    TextField("helloworld.Greeter", text: Binding(
                        get: { request.serviceName },
                        set: {
                            request.serviceName = $0
                            appState.markDirty(id: request.id)
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .cornerRadius(5)

                HStack(spacing: 4) {
                    Text("方法:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    TextField("SayHello", text: Binding(
                        get: { request.methodName },
                        set: {
                            request.methodName = $0
                            appState.markDirty(id: request.id)
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .cornerRadius(5)

                // 从本地 Proto 选择菜单
                let loadedMethods = ProtoRepository.shared.allServices.flatMap { $0.methods }
                if !loadedMethods.isEmpty {
                    Menu {
                        ForEach(ProtoRepository.shared.allServices) { svc in
                            Section(header: Text(svc.name)) {
                                ForEach(svc.methods) { m in
                                    Button("\(m.name) (\(m.callType.shortTag))") {
                                        request.serviceName = m.serviceName
                                        request.methodName = m.name
                                        request.callType = m.callType
                                        if let inputMsg = ProtoRepository.shared.findMessage(by: m.inputMessage.name) {
                                             request.payload = MockJSONGenerator.shared.generateMockJSON(for: inputMsg)
                                        }
                                        ProtoRepository.shared.applyExtensions(to: &request, method: m)
                                        appState.markDirty(id: request.id)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.gearshape")
                            Text("Proto 选单")
                                .lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 7))
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var callTypeColor: Color {
        switch request.callType {
        case .unary: return .blue
        case .serverStreaming: return .purple
        case .clientStreaming: return .orange
        case .bidiStreaming: return .green
        }
    }
}
