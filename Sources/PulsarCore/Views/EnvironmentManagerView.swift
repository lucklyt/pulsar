import SwiftUI

/// 环境变量与多环境管理弹窗 (类似 Postman Environment Manager)
public struct EnvironmentManagerView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEnvId: UUID?
    @State private var revealedSecrets: Set<UUID> = []

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                Text("环境与变量管理 (Environments)")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button("完成") {
                    appState.saveState()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 双栏内容：左侧环境列表，右侧变量表格
            HSplitView {
                // 左侧环境选择栏
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("环境分组")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: addNewEnvironment) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    List(selection: $selectedEnvId) {
                        ForEach(appState.workspace.environments) { env in
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.accentColor)
                                Text(env.name)
                                    .font(.system(size: 12))
                                Spacer()
                                if appState.workspace.activeEnvironmentId == env.id {
                                    Text("已激活")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                            .tag(env.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 180, maxWidth: 220)

                // 右侧变量编辑区
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedId = selectedEnvId,
                       let envIndex = appState.workspace.environments.firstIndex(where: { $0.id == selectedId }) {
                        let envBinding = $appState.workspace.environments[envIndex]

                        HStack {
                            TextField("环境名称", text: envBinding.name)
                                .font(.system(size: 14, weight: .semibold))
                                .textFieldStyle(.roundedBorder)

                            Spacer()

                            Button(action: {
                                appState.switchEnvironment(id: selectedId)
                            }) {
                                Text(appState.workspace.activeEnvironmentId == selectedId ? "已激活" : "设为当前环境")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.workspace.activeEnvironmentId == selectedId)

                            Button(action: {
                                envBinding.variables.wrappedValue.append(VariableItem(key: "", value: ""))
                            }) {
                                Label("添加变量", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }

                        // 变量列表
                        List {
                            ForEach(envBinding.variables) { $variable in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: $variable.isEnabled)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()

                                    TextField("变量名 (如 grpc_host)", text: $variable.key)
                                        .font(.system(size: 12, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 140)

                                    if variable.isSecret && !revealedSecrets.contains(variable.id) {
                                        SecureField("敏感值 (如 token)", text: $variable.value)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textFieldStyle(.roundedBorder)
                                    } else {
                                        TextField("变量值", text: $variable.value)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    // Secret 切换眼睛按钮
                                    Button(action: {
                                        variable.isSecret.toggle()
                                        if !variable.isSecret {
                                            revealedSecrets.remove(variable.id)
                                        }
                                    }) {
                                        Image(systemName: variable.isSecret ? "lock.fill" : "lock.open")
                                            .foregroundColor(variable.isSecret ? .orange : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("标记为敏感变量 (Secret)")

                                    if variable.isSecret {
                                        Button(action: {
                                            if revealedSecrets.contains(variable.id) {
                                                revealedSecrets.remove(variable.id)
                                            } else {
                                                revealedSecrets.insert(variable.id)
                                            }
                                        }) {
                                            Image(systemName: revealedSecrets.contains(variable.id) ? "eye.slash" : "eye")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("显示/隐藏明文")
                                    }

                                    Button(action: {
                                        envBinding.variables.wrappedValue.removeAll { $0.id == variable.id }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .listStyle(.plain)

                    } else {
                        VStack {
                            Spacer()
                            Text("请在左侧选择一个环境，或点击加号新建环境")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
                .frame(minWidth: 420)
            }
        }
        .frame(width: 720, height: 480)
        .onAppear {
            selectedEnvId = appState.workspace.activeEnvironmentId ?? appState.workspace.environments.first?.id
        }
    }

    private func addNewEnvironment() {
        let newEnv = EnvironmentModel(
            name: "新建环境",
            variables: [
                VariableItem(key: "grpc_host", value: "127.0.0.1"),
                VariableItem(key: "grpc_port", value: "50051")
            ]
        )
        appState.workspace.environments.append(newEnv)
        selectedEnvId = newEnv.id
        appState.saveState()
    }
}
