import SwiftUI

/// Bruno 标志性功能：快捷环境变量速览浮层 (Quick Environment Preview Popover)
public struct QuickEnvironmentPopover: View {
    @ObservedObject var appState: AppState
    @State private var revealedSecrets: Set<UUID> = []

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏
            HStack {
                Image(systemName: "globe.asia.australia.fill")
                    .foregroundColor(.accentColor)
                Text(appState.activeEnvironment?.name ?? "未选择环境 (No Active Env)")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button("管理全部环境") {
                    appState.isQuickEnvPopoverPresented = false
                    appState.isEnvironmentModalPresented = true
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }

            Divider()

            if let env = appState.activeEnvironment, !env.variables.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(env.variables) { variable in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(variable.isEnabled ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: 6, height: 6)

                                Text(variable.key)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(width: 110, alignment: .leading)

                                if variable.isSecret && !revealedSecrets.contains(variable.id) {
                                    Text("••••••••")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(variable.value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if variable.isSecret {
                                    Button(action: {
                                        if revealedSecrets.contains(variable.id) {
                                            revealedSecrets.remove(variable.id)
                                        } else {
                                            revealedSecrets.insert(variable.id)
                                        }
                                    }) {
                                        Image(systemName: revealedSecrets.contains(variable.id) ? "eye.slash" : "eye")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 240)
            } else {
                VStack(spacing: 6) {
                    Text("当前环境暂无有效变量")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("可通过全局设置或环境管理面板添加 {{variable}}")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}
