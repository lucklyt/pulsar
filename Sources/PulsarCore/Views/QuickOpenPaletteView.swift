import SwiftUI

/// Bruno 风格全局快速直达浮层 (⌘P Quick Open / Command Palette)
public struct QuickOpenPaletteView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0

    public init(appState: AppState, isPresented: Binding<Bool>) {
        self.appState = appState
        self._isPresented = isPresented
    }

    private var allItems: [AppState.RequestPathItem] {
        appState.allRequestsWithBreadcrumbs()
    }

    private var filteredItems: [AppState.RequestPathItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allItems }
        return allItems.filter { item in
            item.request.name.lowercased().contains(q) ||
            item.request.methodName.lowercased().contains(q) ||
            item.request.serviceName.lowercased().contains(q) ||
            item.request.address.lowercased().contains(q) ||
            item.collectionName.lowercased().contains(q) ||
            (item.folderName?.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        ZStack {
            // 半透明暗色背景，点击遮罩退出
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Spotlight 居中悬浮卡片
            VStack(spacing: 0) {
                // 1. 顶部搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.accentColor)

                    TextField("跳转到请求、服务或方法... (按 ↑↓ 选择，↵ 打开，Esc 退出)", text: $searchText)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            selectCurrentItem()
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            selectedIndex = 0
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("⌘P")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.18))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // 2. 匹配结果列表
                if filteredItems.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 36)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("未找到与「\(searchText)」匹配的请求")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer().frame(height: 36)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    let isSelected = index == safeSelectedIndex

                                    Button(action: {
                                        openRequest(item.request)
                                    }) {
                                        HStack(spacing: 10) {
                                            // CallType 彩色胶囊
                                            Text(item.request.callType.shortTag)
                                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                                .foregroundColor(callTypeColor(item.request.callType))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(callTypeColor(item.request.callType).opacity(0.14))
                                                .cornerRadius(3)

                                            // 请求名称与服务路径
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(item.request.name)
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundColor(isSelected ? .white : .primary)

                                                    if !item.request.serviceName.isEmpty || !item.request.methodName.isEmpty {
                                                        Text("•")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                                                        Text("\(item.request.serviceName)/\(item.request.methodName)")
                                                            .font(.system(size: 11, design: .monospaced))
                                                            .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                                                            .lineLimit(1)
                                                    }
                                                }

                                                // 路径面包屑: Collection > Folder
                                                HStack(spacing: 4) {
                                                    Text(item.collectionName)
                                                    if let folder = item.folderName {
                                                        Text(">")
                                                        Text(folder)
                                                    }
                                                    Text("•")
                                                    Text(item.request.address)
                                                        .lineLimit(1)
                                                }
                                                .font(.system(size: 10))
                                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                                            }

                                            Spacer()

                                            // 是否已在当前标签页打开指示
                                            if appState.openTabIds.contains(item.request.id) {
                                                Text("已打开")
                                                    .font(.system(size: 9, weight: .medium))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(isSelected ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.12))
                                                    .foregroundColor(isSelected ? .white : .accentColor)
                                                    .cornerRadius(4)
                                            }

                                            Image(systemName: "return")
                                                .font(.system(size: 9))
                                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.4))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? Color.accentColor : Color.clear)
                                        .cornerRadius(6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: searchText) {
                            selectedIndex = 0
                        }
                    }
                }

                Divider()

                // 3. 底部快捷键操作说明条
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Text("↑↓")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(3)
                        Text("导航")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text("↵")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(3)
                        Text("打开请求")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text("Esc")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(3)
                        Text("关闭")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("共 \(filteredItems.count) 个可用接口")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            .frame(width: 580)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 10)
        }
    }

    private var safeSelectedIndex: Int {
        guard !filteredItems.isEmpty else { return 0 }
        return min(max(0, selectedIndex), filteredItems.count - 1)
    }

    private func selectCurrentItem() {
        guard !filteredItems.isEmpty else { return }
        let item = filteredItems[safeSelectedIndex]
        openRequest(item.request)
    }

    private func openRequest(_ request: RequestModel) {
        appState.openTab(for: request)
        isPresented = false
    }

    private func callTypeColor(_ type: GRPCCallType) -> Color {
        switch type {
        case .unary: return .blue
        case .serverStreaming: return .purple
        case .clientStreaming: return .orange
        case .bidiStreaming: return .green
        }
    }
}
