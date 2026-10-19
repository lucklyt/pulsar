import SwiftUI

/// Bruno / Postman 风格客户端代码生成浮层 (Code Snippet Modal)
public struct CodeSnippetView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool
    let request: RequestModel

    @State private var selectedLanguage: CodeLanguage = .golang
    @State private var resolveVariables: Bool = true
    @State private var isCopied: Bool = false

    public init(appState: AppState, isPresented: Binding<Bool>, request: RequestModel) {
        self.appState = appState
        self._isPresented = isPresented
        self.request = request
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏：标题与操作
            HStack(spacing: 12) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("生成客户端代码 (Code Snippets)")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(request.serviceName.isEmpty ? "gRPC Service" : request.serviceName)/\(request.methodName.isEmpty ? "Method" : request.methodName)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 解析变量开关
                Toggle("解析环境变量", isOn: $resolveVariables)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("开启后使用当前环境变量的实际值替换 {{variable}}")

                // 一键复制代码按钮
                Button(action: copySnippetToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "已复制" : "复制代码")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(isCopied ? .green : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                // 关闭按钮
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 语言切换栏
            HStack(spacing: 6) {
                ForEach(CodeLanguage.allCases) { lang in
                    Button(action: {
                        selectedLanguage = lang
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: lang.iconName)
                                .font(.system(size: 10))
                            Text(lang.rawValue)
                                .font(.system(size: 11, weight: selectedLanguage == lang ? .semibold : .regular))
                        }
                        .foregroundColor(selectedLanguage == lang ? .accentColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedLanguage == lang ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // 代码预览区
            ScrollView {
                let codeText = currentSnippet
                Text(codeText)
                    .font(.system(size: 11, design: .monospaced))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 720, height: 500)
    }

    private var currentSnippet: String {
        let effConfig = appState.resolveEffectiveConfig(for: request)
        let effReq = effConfig.effectiveRequest

        let finalAddress: String
        let finalPayload: String
        let finalHeaders: [MetadataHeader]
        let finalAuth: AuthConfig
        let finalTLS: TLSConfig
        var finalReq = effReq

        if resolveVariables {
            finalAddress = EnvironmentEngine.shared.resolve(
                template: effReq.address,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            finalPayload = EnvironmentEngine.shared.resolve(
                template: effReq.payload,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            finalHeaders = effReq.metadata.map { h in
                var resolvedH = h
                resolvedH.value = EnvironmentEngine.shared.resolve(
                    template: h.value,
                    environment: appState.activeEnvironment,
                    globalVariables: appState.workspace.globalVariables
                )
                return resolvedH
            }
            var authCopy = effConfig.effectiveAuth
            authCopy.bearerToken = EnvironmentEngine.shared.resolve(
                template: authCopy.bearerToken,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            authCopy.apiKeyValue = EnvironmentEngine.shared.resolve(
                template: authCopy.apiKeyValue,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            authCopy.username = EnvironmentEngine.shared.resolve(
                template: authCopy.username,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            authCopy.password = EnvironmentEngine.shared.resolve(
                template: authCopy.password,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            finalAuth = authCopy

            var tlsCopy = effConfig.effectiveSecurity
            tlsCopy.serverNameOverride = EnvironmentEngine.shared.resolve(
                template: tlsCopy.serverNameOverride,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            finalTLS = tlsCopy

            finalReq.serviceName = EnvironmentEngine.shared.resolve(
                template: effReq.serviceName,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
            finalReq.methodName = EnvironmentEngine.shared.resolve(
                template: effReq.methodName,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )
        } else {
            finalAddress = effReq.address
            finalPayload = effReq.payload
            finalHeaders = effReq.metadata
            finalAuth = effConfig.effectiveAuth
            finalTLS = effConfig.effectiveSecurity
        }

        return CodeSnippetEngine.shared.generateSnippet(
            language: selectedLanguage,
            request: finalReq,
            effectiveAddress: finalAddress,
            effectivePayload: finalPayload,
            effectiveHeaders: finalHeaders,
            effectiveAuth: finalAuth,
            effectiveTLS: finalTLS
        )
    }

    private func copySnippetToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentSnippet, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            isCopied = false
        }
    }
}
