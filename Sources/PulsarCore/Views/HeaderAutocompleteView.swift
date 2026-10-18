import SwiftUI

/// Bruno 风格 Header Key 智能补全输入框 (含分类标准库与文档提示)
public struct HeaderKeyAutocompleteField: View {
    @Binding var key: String
    var onSelectDefinition: ((HeaderDefinition) -> Void)? = nil

    @State private var isMenuPresented: Bool = false

    public init(key: Binding<String>, onSelectDefinition: ((HeaderDefinition) -> Void)? = nil) {
        self._key = key
        self.onSelectDefinition = onSelectDefinition
    }

    public var body: some View {
        HStack(spacing: 2) {
            TextField("header-name", text: $key)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)

            // 智能补全预置头下拉选单
            Menu {
                // 如果当前已有输入，优先显示匹配过滤项
                let matching = HeaderCatalog.search(query: key)
                if !matching.isEmpty && !key.isEmpty {
                    Section("匹配候选 (\(matching.count) 项)") {
                        ForEach(matching.prefix(8)) { def in
                            Button {
                                selectDefinition(def)
                            } label: {
                                Text("\(def.name) - \(def.description)")
                            }
                        }
                    }
                    Divider()
                }

                // 按分类展示完整知识库
                let categories = ["gRPC 协议", "链路追踪", "认证鉴权", "通用传输", "业务路由"]
                ForEach(categories, id: \.self) { cat in
                    Section(cat) {
                        ForEach(HeaderCatalog.sharedHeaders.filter { $0.category == cat }) { def in
                            Button {
                                selectDefinition(def)
                            } label: {
                                HStack {
                                    Text(def.name)
                                    Text("(\(def.description))")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor.opacity(0.8))
                    .padding(2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择标准 Header 或 gRPC 专用协议头")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func selectDefinition(_ def: HeaderDefinition) {
        key = def.name
        onSelectDefinition?(def)
    }
}

/// Bruno 风格 Header Value 智能预置与变量插入输入框
public struct HeaderValueAutocompleteField: View {
    @Binding var value: String
    var headerKey: String
    @ObservedObject var appState: AppState

    public init(value: Binding<String>, headerKey: String, appState: AppState) {
        self._value = value
        self.headerKey = headerKey
        self.appState = appState
    }

    private var currentDef: HeaderDefinition? {
        let clean = headerKey.trimmingCharacters(in: .whitespaces).lowercased()
        return HeaderCatalog.sharedHeaders.first { $0.name.lowercased() == clean }
    }

    public var body: some View {
        HStack(spacing: 2) {
            TextField("header value", text: $value)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)

            // 预置值与变量快捷菜单
            Menu {
                // 1. 对应当前 Header 的官方常用预设值
                if let def = currentDef, !def.presetValues.isEmpty {
                    Section("常用推荐值") {
                        ForEach(def.presetValues, id: \.self) { preset in
                            Button(preset) {
                                value = preset
                            }
                        }
                    }
                    Divider()
                }

                // 2. 当前环境变量
                if let env = appState.activeEnvironment, !env.variables.isEmpty {
                    Section("环境变量 (\(env.name))") {
                        ForEach(env.variables.filter { $0.isEnabled }) { v in
                            Button("{{\(v.key)}} (\(v.isSecret ? "******" : v.value))") {
                                insertSnippet("{{\(v.key)}}")
                            }
                        }
                    }
                    Divider()
                }

                // 3. 全局变量
                if !appState.workspace.globalVariables.isEmpty {
                    Section("全局变量") {
                        ForEach(appState.workspace.globalVariables.filter { $0.isEnabled }) { v in
                            Button("{{\(v.key)}}") {
                                insertSnippet("{{\(v.key)}}")
                            }
                        }
                    }
                    Divider()
                }

                // 4. 动态内置变量
                Section("动态内置变量") {
                    ForEach(EnvironmentEngine.shared.availableBuiltins, id: \.key) { b in
                        Button("{{\(b.key)}} - \(b.desc)") {
                            insertSnippet("{{\(b.key)}}")
                        }
                    }
                }
            } label: {
                Image(systemName: "curlybraces")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("插入环境变量或常用预置值")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(5)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func insertSnippet(_ snippet: String) {
        if value.isEmpty {
            value = snippet
        } else {
            value += snippet
        }
    }
}
