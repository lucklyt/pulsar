import SwiftUI
import UniformTypeIdentifiers

/// Bruno 风格集合根级设置窗口 (Collection Settings)
/// 支持为整个集合配置共享请求头 (Shared Headers)、默认认证 (Default Auth)、默认 TLS 证书及超时
public struct CollectionSettingsView: View {
    @ObservedObject var appState: AppState
    let collectionId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SettingsTab = .headers
    @State private var localCollection: CollectionModel
    @State private var isBulkHeaderEdit: Bool = false
    @State private var bulkHeaderText: String = ""

    enum SettingsTab: String, CaseIterable, Identifiable {
        case headers = "共享请求头"
        case auth = "默认鉴权"
        case security = "默认 TLS/安全"
        case general = "常规与超时"

        var id: String { rawValue }
    }

    public init(appState: AppState, collectionId: UUID) {
        self.appState = appState
        self.collectionId = collectionId
        let found = appState.workspace.collections.first(where: { $0.id == collectionId }) ?? CollectionModel(name: "集合设置")
        _localCollection = State(initialValue: found)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))

                Text("集合设置 - \(localCollection.name)")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                Button("取消", role: .cancel) {
                    dismiss()
                }

                Button("保存配置") {
                    appState.updateCollection(localCollection)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 选项卡切换栏
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)

                            if tab == .headers && localCollection.sharedMetadata.count > 0 {
                                Text("\(localCollection.sharedMetadata.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.gray.opacity(0.12))
                                    .cornerRadius(3)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // 内容区
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case .headers:
                        sharedHeadersView
                    case .auth:
                        sharedAuthView
                    case .security:
                        sharedSecurityView
                    case .general:
                        generalSettingsView
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 680, height: 480)
    }

    // MARK: - 1. 共享 Headers
    private var sharedHeadersView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("集合级共享请求头 (Shared Metadata)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("此处配置的 Header 会自动被该集合下所有请求继承合并（子请求同名 Header 可覆盖）。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Bruno 风格模式切换
                Picker("", selection: Binding<Bool>(
                    get: { isBulkHeaderEdit },
                    set: { willBeBulk in
                        if willBeBulk {
                            bulkHeaderText = HeaderBulkConverter.toBulkText(headers: localCollection.sharedMetadata)
                        } else {
                            localCollection.sharedMetadata = HeaderBulkConverter.fromBulkText(bulkHeaderText)
                        }
                        isBulkHeaderEdit = willBeBulk
                    }
                )) {
                    Text("表格").tag(false)
                    Text("批量编辑 (Bulk)").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                if !isBulkHeaderEdit {
                    Button(action: {
                        localCollection.sharedMetadata.append(MetadataHeader(key: "", value: ""))
                    }) {
                        Label("添加 Header", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if isBulkHeaderEdit {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: Binding(
                        get: { bulkHeaderText },
                        set: {
                            bulkHeaderText = $0
                            localCollection.sharedMetadata = HeaderBulkConverter.fromBulkText($0)
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 220)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                    HStack {
                        let lines = bulkHeaderText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        Text("共识别 \(lines.count) 项共享 Header (格式: key: value)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else if localCollection.sharedMetadata.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 40)
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("当前集合暂未配置任何共享 Header")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("添加通用租户/追踪头 (如 x-tenant-id)") {
                        localCollection.sharedMetadata.append(MetadataHeader(key: "x-tenant-id", value: "tenant_default"))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("").frame(width: 20)
                        Text("键名 (Header Key / 补全)").frame(width: 190, alignment: .leading)
                        Text("键值 (支持 {{var}} 与预设)").frame(maxWidth: .infinity, alignment: .leading)
                        Text("").frame(width: 24)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                    Divider()

                    ForEach($localCollection.sharedMetadata) { $header in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $header.isEnabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .frame(width: 20)

                            HeaderKeyAutocompleteField(
                                key: $header.key,
                                onSelectDefinition: { def in
                                    if header.value.isEmpty, let firstVal = def.presetValues.first {
                                        header.value = firstVal
                                    }
                                }
                            )
                            .frame(width: 190)

                            HeaderValueAutocompleteField(
                                value: $header.value,
                                headerKey: header.key,
                                appState: appState
                            )

                            Button(action: {
                                localCollection.sharedMetadata.removeAll { $0.id == header.id }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.8))
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .frame(width: 24)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. 默认 Auth
    private var sharedAuthView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("集合默认认证 (Default Authentication)")
                    .font(.system(size: 13, weight: .semibold))
                Text("当子请求选择【继承上级 (Inherit)】时，将自动使用此处的鉴权凭据。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Picker("认证类型", selection: $localCollection.auth.type) {
                Text("无认证 (None)").tag(AuthConfig.AuthType.none)
                Text("Bearer Token").tag(AuthConfig.AuthType.bearer)
                Text("API Key (Metadata)").tag(AuthConfig.AuthType.apiKey)
                Text("Basic Auth").tag(AuthConfig.AuthType.basic)
            }
            .pickerStyle(.segmented)

            switch localCollection.auth.type {
            case .none, .inherit:
                Text("当前集合未启用默认认证凭据。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

            case .bearer:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bearer Token (支持引用环境凭据 {{jwt_token}}):")
                        .font(.system(size: 11, weight: .medium))
                    TextField("ey...", text: $localCollection.auth.bearerToken)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }

            case .apiKey:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metadata 键名:")
                                .font(.system(size: 11, weight: .medium))
                            TextField("x-api-key", text: $localCollection.auth.apiKeyName)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key 值 (支持 {{secret_key}}):")
                                .font(.system(size: 11, weight: .medium))
                            TextField("key...", text: $localCollection.auth.apiKeyValue)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

            case .basic:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("用户名:")
                            .font(.system(size: 11, weight: .medium))
                        TextField("admin", text: $localCollection.auth.username)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密码:")
                            .font(.system(size: 11, weight: .medium))
                        SecureField("password", text: $localCollection.auth.password)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    // MARK: - 3. 默认 TLS 安全
    private var sharedSecurityView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("集合默认 TLS / mTLS 安全配置")
                    .font(.system(size: 13, weight: .semibold))
                Text("当子请求选择【继承集合默认】时，将自动生效此处的传输加密与双向证书配置。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Picker("传输安全模式", selection: $localCollection.security.mode) {
                Text("明文传输").tag(TLSConfig.Mode.plaintext)
                Text("标准 TLS").tag(TLSConfig.Mode.tlsSystem)
                Text("自定义根证书 (CA)").tag(TLSConfig.Mode.tlsCustomCA)
                Text("双向认证 (mTLS)").tag(TLSConfig.Mode.mtls)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("跳过服务端证书校验 (Insecure Skip Verify)", isOn: $localCollection.security.insecureSkipVerify)
                    .font(.system(size: 11))

                if localCollection.security.mode == .tlsCustomCA || localCollection.security.mode == .mtls {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自定义 Root CA 根证书路径:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("/path/to/ca.crt", text: $localCollection.security.rootCAPath)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            Button("浏览...") {
                                pickFile { localCollection.security.rootCAPath = $0 }
                            }
                            .font(.system(size: 11))
                        }
                    }
                }

                if localCollection.security.mode == .mtls {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("客户端证书 (Client Cert):")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("/path/to/client.crt", text: $localCollection.security.clientCertPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                Button("浏览...") {
                                    pickFile { localCollection.security.clientCertPath = $0 }
                                }
                                .font(.system(size: 11))
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("客户端私钥 (Client Key):")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("/path/to/client.key", text: $localCollection.security.clientKeyPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                Button("浏览...") {
                                    pickFile { localCollection.security.clientKeyPath = $0 }
                                }
                                .font(.system(size: 11))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. 常规与超时
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("集合名称:")
                    .font(.system(size: 11, weight: .medium))
                TextField("名称", text: $localCollection.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("默认超时控制 (Timeout):")
                    .font(.system(size: 11, weight: .medium))
                HStack(spacing: 12) {
                    Slider(value: $localCollection.timeoutSeconds, in: 1...120, step: 1)
                    Text("\(Int(localCollection.timeoutSeconds)) 秒 (s)")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("集合说明 (Notes / Documentation):")
                    .font(.system(size: 11, weight: .medium))
                TextEditor(text: $localCollection.notes)
                    .font(.system(size: 11))
                    .frame(height: 80)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }

    private func pickFile(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}
