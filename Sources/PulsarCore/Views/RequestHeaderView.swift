import SwiftUI

/// Bruno 风格请求主控制栏：名称与保存操作、一体化 URL 与方法胶囊、Proto 服务快速选单及发送按钮
public struct RequestHeaderView: View {
    @Binding var request: RequestModel
    @ObservedObject var appState: AppState

    @State private var isCodeSnippetPresented: Bool = false

    public var body: some View {
        VStack(spacing: 8) {
            // 第一行：请求标题与快捷操作 (Save, Code Snippets)
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

                // Bruno 风格代码片段生成按钮 (Code Snippets)
                Button(action: {
                    isCodeSnippetPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 11))
                        Text("代码生成")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("生成多语言客户端调用代码 (Go, Python, TypeScript, Swift, cURL)")
                .sheet(isPresented: $isCodeSnippetPresented) {
                    CodeSnippetView(appState: appState, isPresented: $isCodeSnippetPresented, request: request)
                }

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

            // 第三行：Service 与 Method 智能选择与自动补全输入栏 (专属过滤与联动)
            let allServices = ProtoRepository.shared.allServices
            let historyServices = appState.workspaceServices

            HStack(spacing: 8) {
                ServiceAutocompleteField(
                    serviceName: $request.serviceName,
                    methodName: $request.methodName,
                    allServices: allServices,
                    historyServices: historyServices,
                    onSelectService: { svc in
                        applyService(svc)
                    }
                )

                MethodAutocompleteField(
                    serviceName: request.serviceName,
                    methodName: $request.methodName,
                    allServices: allServices,
                    onSelectMethod: { m in
                        applyMethod(m)
                    }
                )
            }

            // 第四行：服务与方法实时智能推荐胶囊栏 (布局内自适应展开，绝不遮挡、绝不截断)
            let currentSvc = request.serviceName.trimmingCharacters(in: .whitespaces)
            let currentMtd = request.methodName.trimmingCharacters(in: .whitespaces)

            let matchedService = allServices.first {
                $0.fullName.lowercased() == currentSvc.lowercased() ||
                $0.name.lowercased() == currentSvc.lowercased()
            }

            if matchedService == nil && !allServices.isEmpty {
                let candidateServices = currentSvc.isEmpty ? allServices : allServices.filter {
                    $0.fullName.lowercased().contains(currentSvc.lowercased()) ||
                    $0.name.lowercased().contains(currentSvc.lowercased())
                }
                if !candidateServices.isEmpty {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                            Text(currentSvc.isEmpty ? "快速选服务:" : "匹配服务:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(candidateServices.prefix(6)) { svc in
                                    Button(action: {
                                        applyService(svc)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "cube.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(.blue)
                                            Text(svc.fullName)
                                                .font(.system(size: 10, design: .monospaced))
                                            Text("(\(svc.methods.count))")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.08))
                                        .cornerRadius(4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.top, 2)
                }
            } else if let svc = matchedService {
                let isMethodMatched = svc.methods.contains { $0.name == currentMtd }
                if !isMethodMatched && !svc.methods.isEmpty {
                    let candidateMethods = currentMtd.isEmpty ? svc.methods : svc.methods.filter {
                        $0.name.lowercased().contains(currentMtd.lowercased())
                    }
                    if !candidateMethods.isEmpty {
                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                                Text(currentMtd.isEmpty ? "选择「\(svc.name)」方法:" : "匹配方法:")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(candidateMethods) { m in
                                        Button(action: {
                                            applyMethod(m)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "function")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.green)
                                                Text(m.name)
                                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                Text(m.callType.shortTag)
                                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                                    .padding(.horizontal, 3)
                                                    .padding(.vertical, 1)
                                                    .background(callTypeBadgeColor(m.callType).opacity(0.15))
                                                    .foregroundColor(callTypeBadgeColor(m.callType))
                                                    .cornerRadius(2)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.08))
                                            .cornerRadius(4)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func applyService(_ svc: ProtoServiceDescriptor) {
        request.serviceName = svc.fullName
        if !svc.methods.contains(where: { $0.name == request.methodName }) {
            if svc.methods.count == 1, let single = svc.methods.first {
                applyMethod(single)
                return
            } else {
                request.methodName = ""
            }
        }
        appState.markDirty(id: request.id)
    }

    private func applyMethod(_ m: ProtoMethodDescriptor) {
        if !m.serviceName.isEmpty {
            request.serviceName = m.serviceName
        }
        request.methodName = m.name
        request.callType = m.callType
        if request.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.payload == "{}" {
            if let inputMsg = ProtoRepository.shared.findMessage(by: m.inputMessage.name) {
                request.payload = MockJSONGenerator.shared.generateMockJSON(for: inputMsg)
            }
        }
        ProtoRepository.shared.applyExtensions(to: &request, method: m)
        appState.markDirty(id: request.id)
    }

    private var callTypeColor: Color {
        callTypeBadgeColor(request.callType)
    }

    private func callTypeBadgeColor(_ type: GRPCCallType) -> Color {
        switch type {
        case .unary: return .blue
        case .serverStreaming: return .purple
        case .clientStreaming: return .orange
        case .bidiStreaming: return .green
        }
    }
}
