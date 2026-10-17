import SwiftUI

/// Bruno 风格请求配置卡片：带徽标计数的选项卡、Bruno 式 Key-Value 表格、JSON 载荷编辑器与协议文档
public struct RequestEditorView: View {
    @Binding var request: RequestModel
    @State private var selectedTab: EditorTab = .body
    @State private var isBulkHeaderEdit: Bool = false
    @State private var bulkHeaderText: String = ""

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

                tabButton(.auth, badge: request.auth.type == .none ? nil : request.auth.type.rawValue)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Metadata 请求头 (gRPC Metadata)")
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                Button(action: {
                    request.metadata.append(MetadataHeader(key: "", value: ""))
                }) {
                    Label("添加行", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
            }

            if request.metadata.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("暂未配置任何请求头 (Metadata)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("添加第一条请求头") {
                        request.metadata.append(MetadataHeader(key: "x-client-version", value: "2.0.0"))
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Bruno 表格式 Key-Value 列表
                VStack(spacing: 0) {
                    // 表头
                    HStack(spacing: 8) {
                        Text("").frame(width: 20)
                        Text("键名 (Header Key)").frame(width: 180, alignment: .leading)
                        Text("键值 (支持变量 {{var}})").frame(maxWidth: .infinity, alignment: .leading)
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
                                    Toggle("", isOn: $header.isEnabled)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                        .frame(width: 20)

                                    TextField("header-name", text: $header.key)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 180)

                                    TextField("header value", text: $header.value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)

                                    Button(action: {
                                        request.metadata.removeAll { $0.id == header.id }
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

    // MARK: - 4. Settings 编辑区

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
                            .pickerStyle(.segmented)
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
