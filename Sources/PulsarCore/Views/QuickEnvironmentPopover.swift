import SwiftUI

/// Bruno 标志性功能：快捷环境变量速览浮层 (Quick Environment Preview Popover)
/// 类似 Bruno 的 Quick Eye，多层级展示当前环境变量、全局变量与内置动态变量，支持即时搜索与一键复制插值
public struct QuickEnvironmentPopover: View {
    @ObservedObject var appState: AppState
    @State private var filterQuery: String = ""
    @State private var revealedSecrets: Set<UUID> = []
    @State private var copiedVarKey: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶栏：环境标识与环境管理入口
            HStack(spacing: 6) {
                if let env = appState.activeEnvironment {
                    Circle()
                        .fill(Color(hex: env.colorHex))
                        .frame(width: 8, height: 8)
                    Text(env.name)
                        .font(.system(size: 13, weight: .bold))

                    if env.isProduction {
                        Text("PROD")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(3)
                    }
                } else {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text("未选择环境 (No Active Env)")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                Button("管理全部环境") {
                    appState.isQuickEnvPopoverPresented = false
                    appState.isEnvironmentModalPresented = true
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }

            // 实时搜索过滤框
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                TextField("过滤变量名称 (如 host / token)...", text: $filterQuery)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                if !filterQuery.isEmpty {
                    Button(action: { filterQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(5)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. 当前环境中的变量
                    if let env = appState.activeEnvironment {
                        let filteredEnvVars = env.variables.filter { v in
                            filterQuery.isEmpty || v.key.localizedCaseInsensitiveContains(filterQuery) || v.value.localizedCaseInsensitiveContains(filterQuery)
                        }

                        if !filteredEnvVars.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("当前环境: \(env.name) (\(filteredEnvVars.count))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                ForEach(filteredEnvVars) { variable in
                                    variableRow(
                                        key: variable.key,
                                        value: variable.value,
                                        isSecret: variable.isSecret,
                                        isEnabled: variable.isEnabled,
                                        id: variable.id
                                    )
                                }
                            }
                        } else if !env.variables.isEmpty {
                            Text("无匹配当前环境变量")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // 2. 全局变量 (Global Variables)
                    let filteredGlobals = appState.workspace.globalVariables.filter { v in
                        filterQuery.isEmpty || v.key.localizedCaseInsensitiveContains(filterQuery) || v.value.localizedCaseInsensitiveContains(filterQuery)
                    }
                    if !filteredGlobals.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("全局变量 (\(filteredGlobals.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            ForEach(filteredGlobals) { variable in
                                variableRow(
                                    key: variable.key,
                                    value: variable.value,
                                    isSecret: variable.isSecret,
                                    isEnabled: variable.isEnabled,
                                    id: variable.id
                                )
                            }
                        }
                    }

                    // 3. 动态内置函数清单
                    let builtins = EnvironmentEngine.shared.availableBuiltins.filter { b in
                        filterQuery.isEmpty || b.key.localizedCaseInsensitiveContains(filterQuery) || b.desc.localizedCaseInsensitiveContains(filterQuery)
                    }
                    if !builtins.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("动态内置变量 (\(builtins.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            ForEach(builtins, id: \.key) { b in
                                HStack(spacing: 6) {
                                    Text(b.key)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.purple)
                                        .frame(width: 110, alignment: .leading)

                                    Text(b.desc)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Button(action: {
                                        copyToClipboard("{{\(b.key)}}")
                                    }) {
                                        Image(systemName: copiedVarKey == b.key ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 9))
                                            .foregroundColor(copiedVarKey == b.key ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("复制 {{\(b.key)}}")
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(12)
        .frame(width: 380)
    }

    private func variableRow(
        key: String,
        value: String,
        isSecret: Bool,
        isEnabled: Bool,
        id: UUID
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isEnabled ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)

            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)

            if isSecret && !revealedSecrets.contains(id) {
                Text("••••••••")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text(value.isEmpty ? "(空值)" : value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(value.isEmpty ? .secondary.opacity(0.6) : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSecret {
                Button(action: {
                    if revealedSecrets.contains(id) {
                        revealedSecrets.remove(id)
                    } else {
                        revealedSecrets.insert(id)
                    }
                }) {
                    Image(systemName: revealedSecrets.contains(id) ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("显示/隐藏密码")
            }

            Button(action: {
                copyToClipboard("{{\(key)}}")
            }) {
                Image(systemName: copiedVarKey == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundColor(copiedVarKey == key ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("复制 {{\(key)}}")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        let key = text.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
        copiedVarKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedVarKey == key {
                copiedVarKey = nil
            }
        }
    }
}
