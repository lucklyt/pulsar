import SwiftUI
import AppKit

/// 本地 Proto 文件浏览器、多级目录 Import Path 搜索路径设置与扩展插件交互面板
public struct ProtoExplorerView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var repo = ProtoRepository.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ExplorerTab = .files
    @State private var selectedMethodFullName: String?
    @State private var selectedFileId: UUID?

    enum ExplorerTab: String, CaseIterable, Identifiable {
        case files = "Proto 文件与服务"
        case importPaths = "Import 包含路径 (-I)"
        case extensions = "Proto 扩展规则"

        var id: String { rawValue }
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. 顶部全局控制条 (标题、Tab切换、完成关闭按钮)
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.gearshape.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 16))
                    Text("本地 Proto 仓库与 Import 路径")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                // 主功能切换器
                Picker("", selection: $selectedTab) {
                    ForEach(ExplorerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Spacer()

                // 显式“完成/关闭”按钮 (彻底解决无法关掉弹窗的问题)
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .help("关闭 Proto 仓库配置窗口 (Return / Esc)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 2. 主体内容区 (按 Tab 分页)
            switch selectedTab {
            case .files:
                filesAndServicesView
            case .importPaths:
                importPathsManagementView
            case .extensions:
                extensionRulesView
            }
        }
        .frame(minWidth: 900, minHeight: 580)
    }

    // MARK: - Tab 1: Proto 文件与服务浏览器

    private var filesAndServicesView: some View {
        VStack(spacing: 0) {
            // 工具栏小按键
            HStack(spacing: 8) {
                Button(action: selectProtoDirectory) {
                    Label("导入目录", systemImage: "folder.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("选择本地 Proto 根目录并递归扫描")

                Button(action: selectProtoFile) {
                    Label("导入单个文件", systemImage: "doc.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Spacer()

                if repo.importPaths.isEmpty {
                    Text("⚠️ 提示: 尚未配置 Import Path，多级目录 import 依赖可能无法定位。")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)

                    Button("去配置 Import Path") {
                        selectedTab = .importPaths
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.link)
                }

                Button(action: { repo.reloadAll() }) {
                    Label("重新加载", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))

            Divider()

            // 双栏分流：左侧服务树，右侧详情
            HSplitView {
                // 左侧树形目录
                List {
                    ForEach(repo.loadedFiles) { file in
                        Section(header: protoFileHeader(file)) {
                            ForEach(file.services) { service in
                                DisclosureGroup(isExpanded: .constant(true)) {
                                    ForEach(service.methods) { method in
                                        MethodRowItem(
                                            method: method,
                                            isSelected: selectedMethodFullName == method.fullName,
                                            onSelect: {
                                                selectedMethodFullName = method.fullName
                                                selectedFileId = file.id
                                            }
                                        )
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "server.rack")
                                            .foregroundColor(.accentColor)
                                        Text(service.name)
                                            .font(.system(size: 12, weight: .semibold))
                                        Spacer()
                                        Text("\(service.methods.count)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 260, maxWidth: 360)

                // 右侧方法详情与调试联动
                if let methodFullName = selectedMethodFullName,
                   let method = repo.findMethod(by: methodFullName) {
                    MethodDetailView(method: method, onTest: {
                        testMethodInNewTab(method: method)
                    })
                } else if let fileId = selectedFileId,
                          let file = repo.loadedFiles.first(where: { $0.id == fileId }) {
                    ProtoFileRawPreviewView(file: file, onAddImportPath: {
                        selectedTab = .importPaths
                    })
                } else {
                    emptySelectionView
                }
            }
        }
    }

    private func protoFileHeader(_ file: LocalProtoFile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.blue)
            Text(file.fileName)
                .font(.system(size: 11, weight: .bold))
            Spacer()

            // 检查是否有未解析成功的 import
            let unresolvedCount = file.resolvedImports.filter { !$0.isResolved }.count
            if unresolvedCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
                    .help("\(unresolvedCount) 个 import 引用未在当前 Import Paths 中定位")
            }

            if !file.extensionDefs.isEmpty {
                Text("EXT(\(file.extensionDefs.count))")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(3)
            }
        }
    }

    // MARK: - Tab 2: Import Paths 包含路径管理 (-I)

    private var importPathsManagementView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 说明与原理 Banner
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("为什么需要设置 Import Paths（包含路径 -I）？")
                        .font(.system(size: 13, weight: .bold))
                }

                Text("在微服务架构的多级目录下，.proto 文件常通过相对路径互相引用（如 import \"common/v1/types.proto\";）。解析器必须知道项目的根搜索路径，才能准确找到目标文件，等同于 protoc 的 -I / --proto_path 参数。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)

            // 操作栏
            HStack {
                Text("已配置的 Import 搜索根路径 (按优先级检索):")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button(action: selectImportDirectory) {
                    Label("添加 Import Path 目录", systemImage: "folder.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
            }

            // Import Paths 列表
            if repo.importPaths.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("暂未配置任何 Import 包含路径")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("点击上方“添加 Import Path 目录”选择你的工程 proto 根目录（如 ./proto）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(repo.importPaths) { item in
                        HStack(spacing: 10) {
                            Button(action: {
                                repo.toggleImportPath(id: item.id)
                            }) {
                                Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(item.isEnabled ? .green : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.path)
                                    .font(.system(size: 12, design: .monospaced))

                                let count = repo.loadedFiles.filter { $0.filePath.hasPrefix(item.path) }.count
                                Text("已发现并加载 \(count) 个 .proto 文件")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                repo.removeImportPath(id: item.id)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
    }

    // MARK: - Tab 3: 扩展规则管理

    private var extensionRulesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Proto 选项与扩展注解触发规则 (Proto Extension Rules)")
                .font(.system(size: 13, weight: .bold))

            List {
                ForEach($repo.extensionPlugins) { $plugin in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("", isOn: $plugin.isEnabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                            Text(plugin.name)
                                .font(.system(size: 13, weight: .semibold))

                            Spacer()

                            Text("匹配注解: \(plugin.targetOptionName)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("动作: \(plugin.actionType.rawValue)")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)

                            if !plugin.injectHeaderKey.isEmpty {
                                Text("• 注入 \(plugin.injectHeaderKey): \(plugin.injectHeaderValue)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(plugin.notes)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
        .padding(16)
    }

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "point.topleft.filled.down.to.point.bottomright.curvepath")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("选择左侧 RPC 方法查看详情与 Proto 扩展")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 文件与目录选择交互

    private func selectImportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "设为 Import Path"
        panel.message = "选择包含多级 .proto 文件的根目录 (例如项目 ./proto 目录)"
        if panel.runModal() == .OK, let url = panel.url {
            repo.addImportPath(path: url.path)
        }
    }

    private func selectProtoDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导入 Proto 目录"
        if panel.runModal() == .OK, let url = panel.url {
            repo.addProtoDirectory(path: url.path)
        }
    }

    private func selectProtoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        panel.prompt = "导入 .proto 文件"
        if panel.runModal() == .OK {
            for url in panel.urls {
                repo.addProtoFile(path: url.path)
            }
        }
    }

    private func testMethodInNewTab(method: ProtoMethodDescriptor) {
        var req = RequestModel(
            name: "\(method.name)",
            serviceName: method.serviceName,
            methodName: method.name,
            callType: method.callType
        )

        if let inputMsg = repo.findMessage(by: method.inputMessage.name) {
            req.payload = MockJSONGenerator.shared.generateMockJSON(for: inputMsg)
        }

        repo.applyExtensions(to: &req, method: method)

        if let targetCol = appState.workspace.collections.first {
            req.collectionId = targetCol.id
            if let index = appState.workspace.collections.firstIndex(where: { $0.id == targetCol.id }) {
                appState.workspace.collections[index].requests.append(req)
            }
        }

        appState.openTab(for: req)
        dismiss() // 开启新调试标签后自动关闭弹窗
    }
}

/// 单个 Proto 文件源码及依赖解析状态预览
struct ProtoFileRawPreviewView: View {
    let file: LocalProtoFile
    let onAddImportPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 文件头信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.fileName)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(file.filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // 依赖引用解析状态卡片
                if !file.resolvedImports.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Import 依赖引用定位状态:")
                            .font(.system(size: 11, weight: .semibold))

                        ForEach(file.resolvedImports) { imp in
                            HStack(spacing: 6) {
                                Image(systemName: imp.isResolved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(imp.isResolved ? .green : .orange)
                                    .font(.system(size: 10))

                                Text(imp.rawImport)
                                    .font(.system(size: 11, design: .monospaced))

                                Spacer()

                                if let res = imp.resolvedPath {
                                    Text(res)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Button("去配置包含路径 (-I)") {
                                        onAddImportPath()
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding(12)

            Divider()

            // 源码滚动区域
            ScrollView {
                Text(file.rawContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
}

/// 方法列表单行项目
struct MethodRowItem: View {
    let method: ProtoMethodDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(method.callType.shortTag)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(callTypeColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(callTypeColor.opacity(0.12))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(method.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    if let http = method.httpOption {
                        Text("HTTP: \(http.value)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if method.isAuthRequired {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .help("包含 Auth 权限注解")
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private var callTypeColor: Color {
        switch method.callType {
        case .unary: return .blue
        case .serverStreaming: return .purple
        case .clientStreaming: return .orange
        case .bidiStreaming: return .green
        }
    }
}

/// 方法详细信息与 Proto 扩展注解面板
struct MethodDetailView: View {
    let method: ProtoMethodDescriptor
    let onTest: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 标题与一键调试按钮
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.name)
                            .font(.system(size: 16, weight: .bold))
                        Text(method.serviceName)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: onTest) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text("在新标签页调试此方法")
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                // RPC 签名卡片
                VStack(alignment: .leading, spacing: 6) {
                    Text("RPC 签名 (Signature):")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("rpc \(method.name) (\(method.clientStreaming ? "stream " : "")\(method.inputMessage.name)) returns (\(method.serverStreaming ? "stream " : "")\(method.outputMessage.name));")
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                // 扩展注解与 Options 表格
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Proto 扩展注解与选项 (Options / Extensions):")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("检测到 \(method.options.count) 项")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if method.options.isEmpty {
                        Text("此方法未声明任何自定义扩展注解或 Option。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(method.options) { opt in
                                HStack(alignment: .top, spacing: 8) {
                                    if opt.isExtension {
                                        Text("EXTENSION")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.12))
                                            .cornerRadius(3)
                                    } else {
                                        Text("OPTION")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(3)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(opt.name)
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        Text(opt.value)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }

                // 输入消息结构预览
                VStack(alignment: .leading, spacing: 6) {
                    Text("输入参数结构 (\(method.inputMessage.name)):")
                        .font(.system(size: 12, weight: .semibold))

                    if let inputDesc = ProtoRepository.shared.findMessage(by: method.inputMessage.name) {
                        let sampleJSON = MockJSONGenerator.shared.generateMockJSON(for: inputDesc)
                        Text(sampleJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    } else {
                        Text("message \(method.inputMessage.name) 未在已加载文件中声明，点击在新标签调试可手动输入。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }
}
