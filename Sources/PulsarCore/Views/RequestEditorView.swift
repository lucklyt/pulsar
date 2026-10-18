import SwiftUI

/// Bruno 风格请求配置卡片：带徽标计数的选项卡、Bruno 式 Key-Value 表格、JSON 载荷编辑器与协议文档
public struct RequestEditorView: View {
    @Binding var request: RequestModel
    @ObservedObject var appState: AppState

    @State private var selectedTab: EditorTab = .body
    @State private var isBulkHeaderEdit: Bool = false
    @State private var bulkHeaderText: String = ""
    @State private var isInheritedHeadersExpanded: Bool = true

    enum EditorTab: String, CaseIterable, Identifiable {
        case body = "请求体"
        case headers = "请求头"
        case auth = "认证鉴权"
        case settings = "连接配置"
        case schema = "Proto 文档"

        var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Bruno 风格紧凑选项卡栏：左对齐自适应紧凑宽度，零多余空白
            HStack(spacing: 0) {
                tabButton(.body, badge: nil)

                let headerCount = request.metadata.filter { $0.isEnabled && !$0.key.isEmpty }.count
                tabButton(.headers, badge: headerCount > 0 ? "\(headerCount)" : nil)

                let authBadge: String? = {
                    if request.auth.type == .inherit {
                        let eff = appState.resolveEffectiveConfig(for: request)
                        return eff.effectiveAuth.type == .none ? "继承:无" : "继承"
                    } else if request.auth.type == .none {
                        return nil
                    } else {
                        return request.auth.type.rawValue
                    }
                }()
                tabButton(.auth, badge: authBadge)
                tabButton(.settings, badge: nil)
                tabButton(.schema, badge: request.serviceName.isEmpty ? nil : "Proto")

                Spacer()
            }
            .padding(.horizontal, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 选项卡内容容器
            Group {
                switch selectedTab {
                case .body:
                    bodyEditorView
                case .headers:
                    headersEditorView
                case .auth:
                    authEditorView
                case .settings:
                    settingsEditorView
                case .schema:
                    schemaDocsView
                }
            }
            .padding(12)
        }
    }

    private func tabButton(_ tab: EditorTab, badge: String?) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
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

    // MARK: - 1. JSON Body 编辑区

    private var bodyEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Text("JSON Payload")
                        .font(.system(size: 11, weight: .semibold))
                    Text("• 支持 {{variable}} 变量")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Bruno 风格快捷变量插入器
                Menu {
                    if let env = appState.activeEnvironment, !env.variables.isEmpty {
                        Section("当前环境变量 (\(env.name))") {
                            ForEach(env.variables.filter { $0.isEnabled }) { v in
                                Button("{{\(v.key)}} (\(v.isSecret ? "******" : v.value))") {
                                    insertVariable("{{\(v.key)}}")
                                }
                            }
                        }
                    }
                    if !appState.workspace.globalVariables.isEmpty {
                        Section("全局变量") {
                            ForEach(appState.workspace.globalVariables.filter { $0.isEnabled }) { v in
                                Button("{{\(v.key)}} (\(v.isSecret ? "******" : v.value))") {
                                    insertVariable("{{\(v.key)}}")
                                }
                            }
                        }
                    }
                    Section("动态内置变量") {
                        ForEach(EnvironmentEngine.shared.availableBuiltins, id: \.key) { b in
                            Button("{{\(b.key)}} - \(b.desc)") {
                                insertVariable("{{\(b.key)}}")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "curlybraces")
                        Text("插入变量")
                    }
                    .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(4)

                Button("格式化 (Prettify)") {
                    prettifyJSON()
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)

                Button("生成 Mock 范例") {
                    generateMockPayload()
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)

                Button("清空") {
                    request.payload = "{\n  \n}"
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }

            TextEditor(text: $request.payload)
                .font(.system(size: 12, design: .monospaced))
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

            // 变量解析诊断提示 (若存在未解析的引用变量)
            let unresolvedVars = EnvironmentEngine.shared.findUnresolvedVariables(
                in: request.payload,
                environment: appState.activeEnvironment,
                globalVariables: appState.workspace.globalVariables
            )

            if !unresolvedVars.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("未定义的环境变量: " + unresolvedVars.map { "{{\($0)}}" }.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Spacer()
                    Button("配置环境变量") {
                        appState.isEnvironmentModalPresented = true
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }

            HStack {
                Text("\(request.payload.components(separatedBy: .newlines).count) 行")
                Text("•")
                Text("\(request.payload.count) 字符")
                Spacer()
                Text("Content-Type: application/grpc+proto")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
    }

    private func insertVariable(_ snippet: String) {
        request.payload += snippet
    }

    private func prettifyJSON() {
        guard let data = request.payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return
        }
        request.payload = prettyString
    }

    private func generateMockPayload() {
        if !request.methodName.isEmpty,
           let method = ProtoRepository.shared.findMethod(by: "\(request.serviceName)/\(request.methodName)"),
           let inputMsg = ProtoRepository.shared.findMessage(by: method.inputMessage.name) {
            request.payload = MockJSONGenerator.shared.generateMockJSON(for: inputMsg)
            return
        }

        // 默认演示结构
        let dummy = ProtoMessageDescriptor(
            name: "Request",
            fullName: "demo.Request",
            fields: [
                ProtoFieldDescriptor(name: "id", number: 1, kind: .string),
                ProtoFieldDescriptor(name: "count", number: 2, kind: .int32),
                ProtoFieldDescriptor(name: "tags", number: 3, kind: .string, isRepeated: true)
            ]
        )
        request.payload = MockJSONGenerator.shared.generateMockJSON(for: dummy)
    }

    // MARK: - 2. Headers (Metadata) 编辑区

    private var headersEditorView: some View {
        let effective = appState.resolveEffectiveConfig(for: request)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Metadata 请求头 (gRPC Metadata)")
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                // Bruno 风格模式切换分段控制器：表格 (Key-Value) vs 批量编辑 (Bulk Edit)
                Picker("", selection: Binding<Bool>(
                    get: { isBulkHeaderEdit },
                    set: { willBeBulk in
                        if willBeBulk {
                            bulkHeaderText = HeaderBulkConverter.toBulkText(headers: request.metadata)
                        } else {
                            request.metadata = HeaderBulkConverter.fromBulkText(bulkHeaderText)
                            appState.markDirty(id: request.id)
                        }
                        isBulkHeaderEdit = willBeBulk
                    }
                )) {
                    Text("表格").tag(false)
                    Text("批量编辑 (Bulk)").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 145)

                if !isBulkHeaderEdit {
                    Button(action: {
                        request.metadata.append(MetadataHeader(key: "", value: ""))
                        appState.markDirty(id: request.id)
                    }) {
                        Label("添加行", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // 1. 继承自上级的共享请求头 (Bruno 风格继承层级展示)
            if !effective.inheritedMetadata.isEmpty {
                DisclosureGroup(
                    isExpanded: $isInheritedHeadersExpanded,
                    content: {
                        VStack(spacing: 4) {
                            ForEach(effective.inheritedMetadata, id: \.header.id) { inherited in
                                let isOverridden = request.metadata.contains {
                                    $0.key.trimmingCharacters(in: .whitespaces).lowercased() == inherited.header.key.trimmingCharacters(in: .whitespaces).lowercased()
                                }

                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 10))
                                        .frame(width: 18)

                                    Text(inherited.header.key)
                                        .font(.system(size: 11, design: .monospaced))
                                        .strikethrough(isOverridden)
                                        .foregroundColor(isOverridden ? .secondary : .primary)
                                        .frame(width: 170, alignment: .leading)

                                    Text(inherited.header.value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .strikethrough(isOverridden)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(inherited.source)
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)

                                    if isOverridden {
                                        Text("被当前请求覆盖")
                                            .font(.system(size: 9))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundColor(.orange)
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(6)
                    },
                    label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.down.right.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 10))
                            Text("继承自上级的共享请求头 (\(effective.inheritedMetadata.count) 个)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                )
            }

            // 检查请求头中是否存在未解析的环境变量
            let unresolvedHeaderVars: [String] = {
                var list: [String] = []
                for h in request.metadata where h.isEnabled && !h.value.isEmpty {
                    let missing = EnvironmentEngine.shared.findUnresolvedVariables(
                        in: h.value,
                        environment: appState.activeEnvironment,
                        globalVariables: appState.workspace.globalVariables
                    )
                    for m in missing where !list.contains(m) {
                        list.append(m)
                    }
                }
                return list
            }()

            if !unresolvedHeaderVars.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("请求头包含未定义变量: " + unresolvedHeaderVars.map { "{{\($0)}}" }.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Spacer()
                    Button("配置环境变量") {
                        appState.isEnvironmentModalPresented = true
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }

            if isBulkHeaderEdit {
                // Bruno 风格 Bulk Edit 纯文本多行编辑模式
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 11))
                        Text("每行格式为 `Key: Value`，以 # 开头的行为禁用项。可直接从 cURL 或日志中一键粘贴！")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("清空") {
                            bulkHeaderText = ""
                            request.metadata = []
                            appState.markDirty(id: request.id)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.bordered)
                    }

                    TextEditor(text: Binding(
                        get: { bulkHeaderText },
                        set: {
                            bulkHeaderText = $0
                            request.metadata = HeaderBulkConverter.fromBulkText($0)
                            appState.markDirty(id: request.id)
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                    HStack {
                        let lines = bulkHeaderText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        let disabledCount = lines.filter {
                            let t = $0.trimmingCharacters(in: .whitespaces)
                            return t.starts(with: "#") || t.starts(with: "//")
                        }.count
                        Text("共识别 \(lines.count) 项 Header (其中 \(disabledCount) 项已禁用)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else if request.metadata.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("当前请求未附加专属请求头")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("添加专属请求头") {
                        request.metadata.append(MetadataHeader(key: "x-client-version", value: "2.0.0"))
                        appState.markDirty(id: request.id)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Bruno 表格式 Key-Value 列表 (集成 Header 智能补全与预设)
                VStack(spacing: 0) {
                    // 表头
                    HStack(spacing: 8) {
                        Text("").frame(width: 20)
                        Text("键名 (Header Key / 补全)").frame(width: 190, alignment: .leading)
                        Text("键值 (支持变量 {{var}} 与常用预置)").frame(maxWidth: .infinity, alignment: .leading)
                        Text("").frame(width: 30)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)

                    Divider()

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach($request.metadata) { $header in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: Binding(
                                        get: { header.isEnabled },
                                        set: {
                                            header.isEnabled = $0
                                            appState.markDirty(id: request.id)
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .frame(width: 20)

                                    HeaderKeyAutocompleteField(
                                        key: Binding(
                                            get: { header.key },
                                            set: {
                                                header.key = $0
                                                appState.markDirty(id: request.id)
                                            }
                                        ),
                                        onSelectDefinition: { def in
                                            if header.value.isEmpty, let firstVal = def.presetValues.first {
                                                header.value = firstVal
                                            }
                                            appState.markDirty(id: request.id)
                                        }
                                    )
                                    .frame(width: 190)

                                    HeaderValueAutocompleteField(
                                        value: Binding(
                                            get: { header.value },
                                            set: {
                                                header.value = $0
                                                appState.markDirty(id: request.id)
                                            }
                                        ),
                                        headerKey: header.key,
                                        appState: appState
                                    )

                                    Button(action: {
                                        request.metadata.removeAll { $0.id == header.id }
                                        appState.markDirty(id: request.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 24)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - 3. Auth 编辑区

    private var authEditorView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("认证类型 (Authorization):")
                    .font(.system(size: 12, weight: .semibold))

                Picker("", selection: $request.auth.type) {
                    ForEach(AuthConfig.AuthType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }

            Divider()

            switch request.auth.type {
            case .inherit:
                let effective = appState.resolveEffectiveConfig(for: request)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: effective.effectiveAuth.type == .none ? "info.circle" : "checkmark.shield.fill")
                            .foregroundColor(effective.effectiveAuth.type == .none ? .secondary : .green)
                            .font(.system(size: 18))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("当前生效鉴权: \(effective.effectiveAuth.type.rawValue)")
                                .font(.system(size: 13, weight: .semibold))
                            Text("来源: \(effective.authSource)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(effective.effectiveAuth.type == .none ? Color.gray.opacity(0.08) : Color.green.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(effective.effectiveAuth.type == .none ? Color.gray.opacity(0.2) : Color.green.opacity(0.25), lineWidth: 1)
                    )

                    if effective.effectiveAuth.type == .bearer {
                        HStack {
                            Text("继承的 Bearer Token:")
                                .font(.system(size: 11, weight: .medium))
                            Text(effective.effectiveAuth.bearerToken.isEmpty ? "(未填写)" : effective.effectiveAuth.bearerToken)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else if effective.effectiveAuth.type == .apiKey {
                        HStack {
                            Text("继承的 API Key:")
                                .font(.system(size: 11, weight: .medium))
                            Text("\(effective.effectiveAuth.apiKeyName) = \(effective.effectiveAuth.apiKeyValue)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else if effective.effectiveAuth.type == .basic {
                        HStack {
                            Text("继承的 Basic 账户:")
                                .font(.system(size: 11, weight: .medium))
                            Text(effective.effectiveAuth.username)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    Button(action: {
                        let targetType = (effective.effectiveAuth.type == .inherit || effective.effectiveAuth.type == .none) ? .bearer : effective.effectiveAuth.type
                        request.auth.type = targetType
                        request.auth.bearerToken = effective.effectiveAuth.bearerToken
                        request.auth.apiKeyName = effective.effectiveAuth.apiKeyName
                        request.auth.apiKeyValue = effective.effectiveAuth.apiKeyValue
                        request.auth.username = effective.effectiveAuth.username
                        request.auth.password = effective.effectiveAuth.password
                    }) {
                        Label("为此请求配置独立鉴权 (覆盖继承)", systemImage: "pencil.line")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }

            case .none:
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前无需附加认证令牌。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("如果服务要求 Bearer Token 或 API Key，请在上方选择认证方式。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            case .bearer:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bearer Token (支持引用环境凭据 {{jwt_token}}):")
                        .font(.system(size: 11, weight: .medium))
                    TextField("ey...", text: $request.auth.bearerToken)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            case .apiKey:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata 键名 (Header Name):")
                        .font(.system(size: 11, weight: .medium))
                    TextField("x-api-key", text: $request.auth.apiKeyName)
                        .textFieldStyle(.roundedBorder)

                    Text("API Key 值 (支持 {{secret_key}}):")
                        .font(.system(size: 11, weight: .medium))
                    TextField("输入 Key", text: $request.auth.apiKeyValue)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            case .basic:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username:")
                        .font(.system(size: 11, weight: .medium))
                    TextField("用户名", text: $request.auth.username)
                        .textFieldStyle(.roundedBorder)

                    Text("Password:")
                        .font(.system(size: 11, weight: .medium))
                    SecureField("密码", text: $request.auth.password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer()
        }
    }

    // MARK: - 4. Settings 编辑区 (Bruno 风格卡片布局，杜绝 Form 错乱)

    private var settingsEditorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. TLS & 安全连接卡片
                VStack(alignment: .leading, spacing: 10) {
                    Label("TLS 与连接安全", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .bold))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("连接模式:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .leading)

                            Picker("", selection: $request.tls.mode) {
                                ForEach(TLSConfig.Mode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 240)
                        }

                        if request.tls.mode == .inherit {
                            let effective = appState.resolveEffectiveConfig(for: request)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("当前生效 TLS: \(effective.effectiveRequest.tls.mode.rawValue)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("来源: \(effective.securitySource)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(6)
                        }

                        if request.tls.mode != .plaintext {
                            Toggle("跳过服务端证书有效性校验 (Insecure Skip Verify)", isOn: $request.tls.insecureSkipVerify)
                                .font(.system(size: 11))
                                .toggleStyle(.checkbox)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("SNI / ServerName 覆盖 (可选):")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("例如 grpc.example.com", text: $request.tls.serverNameOverride)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }

                        if request.tls.mode == .tlsCustomCA || request.tls.mode == .mtls {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("自定义 Root CA 证书路径 (.pem / .crt):")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("/path/to/ca.pem", text: $request.tls.rootCAPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                    Button("浏览...") {
                                        selectFile { path in
                                            request.tls.rootCAPath = path
                                        }
                                    }
                                    .font(.system(size: 11))
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        if request.tls.mode == .mtls {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("客户端双向认证凭据 (mTLS):")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)

                                HStack {
                                    TextField("Client Cert 路径 (.pem)", text: $request.tls.clientCertPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                    Button("浏览...") {
                                        selectFile { path in
                                            request.tls.clientCertPath = path
                                        }
                                    }
                                    .font(.system(size: 11))
                                    .buttonStyle(.bordered)
                                }

                                HStack {
                                    TextField("Client Key 路径 (.key)", text: $request.tls.clientKeyPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                    Button("浏览...") {
                                        selectFile { path in
                                            request.tls.clientKeyPath = path
                                        }
                                    }
                                    .font(.system(size: 11))
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                    )
                }

                // 2. 服务发现与寻址 (Nacos Discovery)
                VStack(alignment: .leading, spacing: 10) {
                    Label("服务发现与路由 (Discovery)", systemImage: "network")
                        .font(.system(size: 12, weight: .bold))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("寻址协议:")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 80, alignment: .leading)

                            Picker("", selection: $request.discovery.scheme) {
                                ForEach(ServiceDiscoveryConfig.ProtocolScheme.allCases, id: \.self) { scheme in
                                    Text(scheme.rawValue).tag(scheme)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if request.discovery.scheme == .nacos {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nacos 集群地址 (多节点逗号分隔):")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    TextField("127.0.0.1:8848, 127.0.0.1:8849", text: $request.discovery.nacosClusters)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                }

                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Namespace (命名空间):")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                        TextField("public", text: $request.discovery.nacosNamespace)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11, design: .monospaced))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("GroupName (分组):")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                        TextField("DEFAULT_GROUP", text: $request.discovery.nacosGroupName)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11, design: .monospaced))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ServiceName (服务名):")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    TextField("providers:com.example.DemoService:1.0.0", text: $request.discovery.nacosServiceName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                    )
                }

                // 3. 调用超时设置 (Timeout)
                VStack(alignment: .leading, spacing: 10) {
                    Label("调用超时控制 (Timeout)", systemImage: "timer")
                        .font(.system(size: 12, weight: .bold))

                    HStack(spacing: 12) {
                        Slider(value: $request.timeoutSeconds, in: 1...120, step: 1)

                        HStack(spacing: 4) {
                            Text("\(Int(request.timeoutSeconds))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                            Text("秒 (s)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 60, alignment: .trailing)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                    )
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func selectFile(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }

    // MARK: - 5. Schema / Docs 文档区

    private var schemaDocsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let method = ProtoRepository.shared.findMethod(by: "\(request.serviceName)/\(request.methodName)") {
                HStack {
                    Text("Proto 协议文档: \(method.fullName)")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    if !method.options.isEmpty {
                        Text("\(method.options.count) 项注解")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                    }
                }

                Divider()

                if !method.comments.isEmpty {
                    Text("文档注释:")
                        .font(.system(size: 11, weight: .semibold))
                    Text(method.comments)
                        .font(.system(size: 11))
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                Text("RPC 签名:")
                    .font(.system(size: 11, weight: .semibold))
                Text("rpc \(method.name) (\(method.inputMessage.name)) returns (\(method.outputMessage.name));")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)

                Spacer()
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("未关联到本地 Proto 结构定义")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("在顶部点击“Proto 选单”选择对应 Service/Method 即可在此查看架构文档")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
