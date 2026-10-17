import SwiftUI

/// Bruno 风格的多标签页栏 (TabBar)：支持活动高亮、未保存脏标记 (•)、关闭与快捷新建
public struct TabBarView: View {
    @ObservedObject var appState: AppState

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(appState.openTabIds, id: \.self) { id in
                    if let req = findRequest(by: id) {
                        TabItemView(
                            title: req.name,
                            callType: req.callType,
                            isActive: appState.activeTabId == id,
                            isDirty: appState.dirtyTabIds.contains(id),
                            onSelect: {
                                appState.activeTabId = id
                            },
                            onClose: {
                                appState.closeTab(id: id)
                            }
                        )
                    }
                }

                // 新建标签按钮
                Button(action: {
                    appState.createNewRequest()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 26)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("新建标签页 (⌘T)")
                .padding(.leading, 4)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 3)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func findRequest(by id: UUID) -> RequestModel? {
        for col in appState.workspace.collections {
            if let req = col.requests.first(where: { $0.id == id }) {
                return req
            }
        }
        return nil
    }
}

struct TabItemView: View {
    let title: String
    let callType: GRPCCallType
    let isActive: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // 方法标识短徽标
            Text(callType.shortTag)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(tagColor)

            Text(title)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 160)

            // 脏状态指示点 (Bruno 风格)
            if isDirty && !isHovered {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

            // 关闭按钮 (悬浮时显示)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isHovered || isActive ? .secondary : .clear)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(NSColor.controlBackgroundColor) : (isHovered ? Color.gray.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.gray.opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .overlay(
            // Bruno 顶部微高亮边线
            VStack {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .cornerRadius(1)
                }
                Spacer()
            }
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }

    private var tagColor: Color {
        switch callType {
        case .unary: return .blue
        case .serverStreaming: return .purple
        case .clientStreaming: return .orange
        case .bidiStreaming: return .green
        }
    }
}
