import SwiftUI

/// 变量补全项元数据
public struct VariableSuggestion: Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let value: String
    public let source: String // "ENV", "GLOBAL", "BUILTIN"
    public let description: String?

    public init(key: String, value: String, source: String, description: String? = nil) {
        self.key = key
        self.value = value
        self.source = source
        self.description = description
    }
}

/// 识别文本中处于输入状态的未闭合 `{{`
public struct OpenVariableTrigger: Equatable {
    public let query: String
    public let range: Range<String.Index>

    public init(query: String, range: Range<String.Index>) {
        self.query = query
        self.range = range
    }
}

/// 检测字符串末尾或光标处是否存在未闭合的 `{{`
public func detectOpenVariableTrigger(in text: String) -> OpenVariableTrigger? {
    guard let lastOpen = text.range(of: "{{", options: .backwards) else {
        return nil
    }
    let afterOpen = text[lastOpen.upperBound...]
    if afterOpen.contains("}}") {
        return nil
    }
    if afterOpen.contains("\n") {
        guard let lastLine = text.components(separatedBy: .newlines).last,
              let lineRange = lastLine.range(of: "{{", options: .backwards),
              !lastLine[lineRange.upperBound...].contains("}}") else {
            return nil
        }
        let q = String(lastLine[lineRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let fullRange = text.range(of: "{{" + q, options: .backwards) {
            return OpenVariableTrigger(query: q, range: fullRange)
        }
        return nil
    }

    let query = String(afterOpen).trimmingCharacters(in: .whitespaces)
    let triggerRange = lastOpen.lowerBound..<text.endIndex
    return OpenVariableTrigger(query: query, range: triggerRange)
}

/// 将未闭合的 `{{query` 自动补全为 `{{key}}`
public func completeVariable(in text: inout String, with key: String) {
    if let trigger = detectOpenVariableTrigger(in: text) {
        text.replaceSubrange(trigger.range, with: "{{\(key)}}")
    } else {
        text += "{{\(key)}}"
    }
}

/// 根据输入查询获取所有可用的变量补全候选项
public func getVariableSuggestions(query: String, appState: AppState) -> [VariableSuggestion] {
    let cleanQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
    var list: [VariableSuggestion] = []

    // 1. 活动环境变量 (高优先级)
    if let env = appState.activeEnvironment {
        for v in env.variables where v.isEnabled && !v.key.isEmpty {
            if cleanQuery.isEmpty || v.key.lowercased().contains(cleanQuery) {
                list.append(VariableSuggestion(
                    key: v.key,
                    value: v.isSecret ? "••••••" : v.value,
                    source: "ENV",
                    description: v.isSecret ? "环境机密变量" : v.value
                ))
            }
        }
    }

    // 2. 工作区全局变量
    for v in appState.workspace.globalVariables where v.isEnabled && !v.key.isEmpty {
        if cleanQuery.isEmpty || v.key.lowercased().contains(cleanQuery) {
            if !list.contains(where: { $0.key == v.key }) {
                list.append(VariableSuggestion(
                    key: v.key,
                    value: v.isSecret ? "••••••" : v.value,
                    source: "GLOBAL",
                    description: v.isSecret ? "全局变量" : v.value
                ))
            }
        }
    }

    // 3. 动态内置函数 ($uuid, $timestamp, 等)
    for b in EnvironmentEngine.shared.availableBuiltins {
        let rawKey = b.key
        if cleanQuery.isEmpty || rawKey.lowercased().contains(cleanQuery) || b.desc.lowercased().contains(cleanQuery) {
            list.append(VariableSuggestion(
                key: rawKey,
                value: "",
                source: "BUILTIN",
                description: b.desc
            ))
        }
    }

    return list
}

/// Bruno 风格自适应变量补全横向推荐栏 (用于 URL 地址栏下方或 JSON 载荷编辑框上方)
public struct VariableSuggestionBarView: View {
    public let query: String
    @Binding public var text: String
    @ObservedObject public var appState: AppState
    public var onSelected: (() -> Void)? = nil

    public init(query: String, text: Binding<String>, appState: AppState, onSelected: (() -> Void)? = nil) {
        self.query = query
        self._text = text
        self.appState = appState
        self.onSelected = onSelected
    }

    private var suggestions: [VariableSuggestion] {
        getVariableSuggestions(query: query, appState: appState)
    }

    public var body: some View {
        if !suggestions.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.purple)
                    Text("变量补全:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions.prefix(8)) { sug in
                            Button(action: {
                                completeVariable(in: &text, with: sug.key)
                                onSelected?()
                            }) {
                                HStack(spacing: 4) {
                                    Text("{{\(sug.key)}}")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.purple)

                                    if !sug.value.isEmpty {
                                        Text("=\(sug.value)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Text(sug.source)
                                        .font(.system(size: 8, weight: .heavy))
                                        .foregroundColor(sourceColor(sug.source))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(sourceColor(sug.source).opacity(0.12))
                                        .cornerRadius(2)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.purple.opacity(0.08))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.purple.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "ENV": return .green
        case "GLOBAL": return .blue
        default: return .purple
        }
    }
}

/// 支持在键入 `{{` 时自动弹窗补全提示与选择的通用输入框
public struct VariableAutocompleteTextField: View {
    public let placeholder: String
    @Binding public var text: String
    @ObservedObject public var appState: AppState
    public var font: Font
    public var onCommit: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var isDismissed: Bool = false

    public init(
        _ placeholder: String,
        text: Binding<String>,
        appState: AppState,
        font: Font = .system(size: 11, design: .monospaced),
        onCommit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.appState = appState
        self.font = font
        self.onCommit = onCommit
    }

    private var openTrigger: OpenVariableTrigger? {
        detectOpenVariableTrigger(in: text)
    }

    private var suggestions: [VariableSuggestion] {
        guard let trigger = openTrigger else { return [] }
        return getVariableSuggestions(query: trigger.query, appState: appState)
    }

    public var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: Binding(
                get: { text },
                set: {
                    text = $0
                    isDismissed = false
                }
            ), onCommit: {
                onCommit?()
            })
            .font(font)
            .textFieldStyle(.plain)
            .focused($isFocused)

            // 快捷变量选择菜单 (随时可通过点击图标选择)
            Menu {
                if let env = appState.activeEnvironment, !env.variables.isEmpty {
                    Section("环境变量 (\(env.name))") {
                        ForEach(env.variables.filter { $0.isEnabled }) { v in
                            Button("{{\(v.key)}} (\(v.isSecret ? "******" : v.value))") {
                                insertVariable(v.key)
                            }
                        }
                    }
                    Divider()
                }

                if !appState.workspace.globalVariables.isEmpty {
                    Section("全局变量") {
                        ForEach(appState.workspace.globalVariables.filter { $0.isEnabled }) { v in
                            Button("{{\(v.key)}} (\(v.isSecret ? "******" : v.value))") {
                                insertVariable(v.key)
                            }
                        }
                    }
                    Divider()
                }

                Section("动态内置变量") {
                    ForEach(EnvironmentEngine.shared.availableBuiltins, id: \.key) { b in
                        Button("{{\(b.key)}} - \(b.desc)") {
                            insertVariable(b.key)
                        }
                    }
                }
            } label: {
                Image(systemName: "curlybraces")
                    .font(.system(size: 9))
                    .foregroundColor(openTrigger != nil ? .purple : .secondary)
                    .padding(2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("插入环境变量或动态表达式")
        }
        // 浮层自动补全下拉框 (输入 {{ 时自动弹出)
        .overlay(alignment: .topLeading) {
            if isFocused && openTrigger != nil && !isDismissed && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.purple)
                        Text("点击补全变量 (共 \(suggestions.count) 项):")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { isDismissed = true }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                    Divider()

                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(suggestions.prefix(8)) { sug in
                                Button(action: {
                                    completeVariable(in: &text, with: sug.key)
                                    isDismissed = true
                                }) {
                                    HStack(spacing: 6) {
                                        Text("{{\(sug.key)}}")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.purple)

                                        if !sug.value.isEmpty {
                                            Text("= \(sug.value)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        } else if let desc = sug.description {
                                            Text("(\(desc))")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text(sug.source)
                                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(sourceColor(sug.source).opacity(0.12))
                                            .foregroundColor(sourceColor(sug.source))
                                            .cornerRadius(3)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .frame(width: 320)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                )
                .offset(y: 26)
                .zIndex(1000)
            }
        }
    }

    private func insertVariable(_ key: String) {
        completeVariable(in: &text, with: key)
        isDismissed = true
    }

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "ENV": return .green
        case "GLOBAL": return .blue
        default: return .purple
        }
    }
}
