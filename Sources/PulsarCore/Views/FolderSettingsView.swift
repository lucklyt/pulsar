import SwiftUI

/// Bruno 风格文件夹级设置窗口 (Folder Settings)
/// 支持为文件夹配置专属共享请求头 (Shared Headers) 与鉴权覆盖 (Auth Override)
public struct FolderSettingsView: View {
    @ObservedObject var appState: AppState
    let collectionId: UUID
    let folderId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: FolderTab = .headers
    @State private var localFolder: FolderModel
    @State private var isBulkHeaderEdit: Bool = false
    @State private var bulkHeaderText: String = ""

    enum FolderTab: String, CaseIterable, Identifiable {
        case headers = "共享请求头"
        case auth = "文件夹鉴权"

        var id: String { rawValue }
    }

    public init(appState: AppState, collectionId: UUID, folderId: UUID) {
        self.appState = appState
        self.collectionId = collectionId
        self.folderId = folderId
        let found = appState.workspace.collections.first(where: { $0.id == collectionId })?
            .folders.first(where: { $0.id == folderId }) ?? FolderModel(name: "文件夹设置", collectionId: collectionId)
        _localFolder = State(initialValue: found)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))

                Text("文件夹设置 - \(localFolder.name)")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                Button("取消", role: .cancel) {
                    dismiss()
                }

                Button("保存配置") {
                    appState.updateFolder(in: collectionId, folder: localFolder)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 选项卡
            HStack(spacing: 0) {
                ForEach(FolderTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)

                            if tab == .headers && localFolder.sharedMetadata.count > 0 {
                                Text("\(localFolder.sharedMetadata.count)")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case .headers:
                        folderHeadersView
                    case .auth:
                        folderAuthView
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 620, height: 420)
    }

    private var folderHeadersView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("文件夹共享请求头 (Folder Metadata)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("该文件夹内的所有请求会自动合并此 Header。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Bruno 风格模式切换
                Picker("", selection: Binding<Bool>(
                    get: { isBulkHeaderEdit },
                    set: { willBeBulk in
                        if willBeBulk {
                            bulkHeaderText = HeaderBulkConverter.toBulkText(headers: localFolder.sharedMetadata)
                        } else {
                            localFolder.sharedMetadata = HeaderBulkConverter.fromBulkText(bulkHeaderText)
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
                        localFolder.sharedMetadata.append(MetadataHeader(key: "", value: ""))
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
                            localFolder.sharedMetadata = HeaderBulkConverter.fromBulkText($0)
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 200)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                    HStack {
                        let lines = bulkHeaderText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        Text("共识别 \(lines.count) 项文件夹共享 Header (格式: key: value)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else if localFolder.sharedMetadata.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 30)
                    Text("当前文件夹暂无专属共享 Header，会自动继承集合级配置。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("").frame(width: 20)
                        Text("键名 (Header Key / 补全)").frame(width: 180, alignment: .leading)
                        Text("键值 (支持 {{var}} 与预设)").frame(maxWidth: .infinity, alignment: .leading)
                        Text("").frame(width: 24)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                    Divider()

                    ForEach($localFolder.sharedMetadata) { $header in
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
                            .frame(width: 180)

                            HeaderValueAutocompleteField(
                                value: $header.value,
                                headerKey: header.key,
                                appState: appState
                            )

                            Button(action: {
                                localFolder.sharedMetadata.removeAll { $0.id == header.id }
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

    private var folderAuthView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("文件夹级鉴权模式 (Folder Authentication)")
                    .font(.system(size: 13, weight: .semibold))
                Text("选择继承自集合，或为该文件夹独立指定鉴权凭据。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Picker("鉴权模式", selection: $localFolder.auth.type) {
                Text("继承自集合 (Inherit)").tag(AuthConfig.AuthType.inherit)
                Text("无认证 (None)").tag(AuthConfig.AuthType.none)
                Text("Bearer Token").tag(AuthConfig.AuthType.bearer)
                Text("API Key").tag(AuthConfig.AuthType.apiKey)
                Text("Basic Auth").tag(AuthConfig.AuthType.basic)
            }
            .pickerStyle(.segmented)

            switch localFolder.auth.type {
            case .inherit:
                Text("✅ 已启用继承：本文件夹内所有请求将默认使用上级集合配置的鉴权凭据。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

            case .none:
                Text("本文件夹强制设置为无认证。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

            case .bearer:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bearer Token (支持引用环境凭据 {{jwt_token}}):")
                        .font(.system(size: 11, weight: .medium))
                    TextField("token...", text: $localFolder.auth.bearerToken)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }

            case .apiKey:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("键名:")
                            .font(.system(size: 11, weight: .medium))
                        TextField("x-api-key", text: $localFolder.auth.apiKeyName)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("值:")
                            .font(.system(size: 11, weight: .medium))
                        TextField("key...", text: $localFolder.auth.apiKeyValue)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                }

            case .basic:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("用户名:")
                            .font(.system(size: 11, weight: .medium))
                        TextField("user", text: $localFolder.auth.username)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密码:")
                            .font(.system(size: 11, weight: .medium))
                        SecureField("password", text: $localFolder.auth.password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }
}
