import SwiftUI

/// Bruno 风格 gRPC 服务智能补全与下拉选单输入框
public struct ServiceAutocompleteField: View {
    @Binding public var serviceName: String
    @Binding public var methodName: String
    public var allServices: [ProtoServiceDescriptor]
    public var historyServices: [String]
    public var onSelectService: ((ProtoServiceDescriptor) -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        serviceName: Binding<String>,
        methodName: Binding<String>,
        allServices: [ProtoServiceDescriptor],
        historyServices: [String] = [],
        onSelectService: ((ProtoServiceDescriptor) -> Void)? = nil
    ) {
        self._serviceName = serviceName
        self._methodName = methodName
        self.allServices = allServices
        self.historyServices = historyServices
        self.onSelectService = onSelectService
    }

    private var matchingServices: [ProtoServiceDescriptor] {
        let q = serviceName.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allServices }
        return allServices.filter {
            $0.fullName.lowercased().contains(q) ||
            $0.name.lowercased().contains(q)
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cube.fill")
                .font(.system(size: 9))
                .foregroundColor(.blue.opacity(0.85))

            Text("服务:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            TextField("helloworld.Greeter", text: $serviceName)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !serviceName.isEmpty {
                Button(action: {
                    serviceName = ""
                    methodName = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("清空服务与方法")
            }

            // 下拉选择菜单 (Menu)
            Menu {
                // 1. 匹配的候选服务 (若当前有输入)
                if !serviceName.isEmpty && !matchingServices.isEmpty {
                    Section("匹配服务 (\(matchingServices.count))") {
                        ForEach(matchingServices) { svc in
                            Button {
                                selectService(svc)
                            } label: {
                                Text("\(svc.fullName)  (\(svc.methods.count) 个方法)")
                            }
                        }
                    }
                    Divider()
                }

                // 2. 全部已解析的 Proto 服务
                if !allServices.isEmpty {
                    Section("全部 Proto 服务 (\(allServices.count))") {
                        ForEach(allServices) { svc in
                            Button {
                                selectService(svc)
                            } label: {
                                Text("\(svc.fullName)  (\(svc.methods.count) 个方法)")
                            }
                        }
                    }
                }

                // 3. 历史/工作区自定义服务
                let custom = historyServices.filter { h in
                    !allServices.contains(where: { $0.fullName == h || $0.name == h })
                }
                if !custom.isEmpty {
                    Divider()
                    Section("工作区历史服务") {
                        ForEach(custom, id: \.self) { s in
                            Button(s) {
                                serviceName = s
                            }
                        }
                    }
                }

                if allServices.isEmpty && custom.isEmpty {
                    Text("暂无可用服务 (可在左侧导入 Proto)").disabled(true)
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择或浏览可用 gRPC 服务")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func selectService(_ svc: ProtoServiceDescriptor) {
        serviceName = svc.fullName
        if let onSelectService = onSelectService {
            onSelectService(svc)
        } else {
            if !svc.methods.contains(where: { $0.name == methodName }) {
                if svc.methods.count == 1, let single = svc.methods.first {
                    methodName = single.name
                } else {
                    methodName = ""
                }
            }
        }
    }
}

/// Bruno 风格 gRPC 方法智能补全与专属下拉选单输入框 (严格根据所选服务过滤)
public struct MethodAutocompleteField: View {
    public var serviceName: String
    @Binding public var methodName: String
    public var allServices: [ProtoServiceDescriptor]
    public var onSelectMethod: ((ProtoMethodDescriptor) -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        serviceName: String,
        methodName: Binding<String>,
        allServices: [ProtoServiceDescriptor],
        onSelectMethod: ((ProtoMethodDescriptor) -> Void)? = nil
    ) {
        self.serviceName = serviceName
        self._methodName = methodName
        self.allServices = allServices
        self.onSelectMethod = onSelectMethod
    }

    /// 当前选中的对应服务描述符
    private var currentService: ProtoServiceDescriptor? {
        let trimmed = serviceName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return allServices.first(where: {
            $0.fullName.lowercased() == trimmed.lowercased() ||
            $0.name.lowercased() == trimmed.lowercased()
        })
    }

    /// 严格归属于当前服务的专属方法候选列表
    private var availableMethods: [ProtoMethodDescriptor] {
        if let svc = currentService {
            return svc.methods
        }
        return []
    }

    /// 输入文本过滤后的方法
    private var matchingMethods: [ProtoMethodDescriptor] {
        let q = methodName.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return availableMethods }
        return availableMethods.filter {
            $0.name.lowercased().contains(q) ||
            $0.fullName.lowercased().contains(q)
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "function")
                .font(.system(size: 9))
                .foregroundColor(.green.opacity(0.85))

            Text("方法:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            TextField(serviceName.isEmpty ? "请先选择服务" : "SayHello", text: $methodName)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !methodName.isEmpty {
                Button(action: {
                    methodName = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("清空方法")
            }

            // 下拉选单 (Menu) - 严格根据当前服务确定
            Menu {
                if let svc = currentService {
                    // 1. 过滤匹配的方法
                    if !methodName.isEmpty && !matchingMethods.isEmpty {
                        Section("匹配方法 (\(matchingMethods.count))") {
                            ForEach(matchingMethods) { m in
                                Button {
                                    selectMethod(m)
                                } label: {
                                    Text("\(m.name)  [\(m.callType.shortTag)]")
                                }
                            }
                        }
                        Divider()
                    }

                    // 2. 当前服务的所有方法
                    Section("「\(svc.name)」的方法列表 (\(svc.methods.count))") {
                        if svc.methods.isEmpty {
                            Text("当前服务未定义任何 RPC 方法").disabled(true)
                        } else {
                            ForEach(svc.methods) { m in
                                Button {
                                    selectMethod(m)
                                } label: {
                                    Text("\(m.name)  [\(m.callType.shortTag)] - \(m.callType.displayName)")
                                }
                            }
                        }
                    }
                } else if serviceName.isEmpty {
                    Section("提示") {
                        Text("⚠️ 请先在左侧输入或选择服务").disabled(true)
                    }
                    Divider()
                    // 跨所有服务快速直选方法
                    Section("从所有服务中快速选取方法") {
                        ForEach(allServices) { svc in
                            Menu("\(svc.fullName) (\(svc.methods.count))") {
                                ForEach(svc.methods) { m in
                                    Button("\(m.name)  [\(m.callType.shortTag)]") {
                                        selectMethod(m)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section("服务: \(serviceName)") {
                        Text("未在 Proto 仓库中找到该服务的定义").disabled(true)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择属于当前服务的方法")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func selectMethod(_ m: ProtoMethodDescriptor) {
        methodName = m.name
        onSelectMethod?(m)
    }
}
