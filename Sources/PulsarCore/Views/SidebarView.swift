import SwiftUI

/// Bruno 风格左侧主导航边栏：多集合树形目录、实时检索过滤器、Proto 快速通道与调用历史
public struct SidebarView: View {
    @ObservedObject var appState: AppState

    @State private var isCreatingFolder = false
    @State private var targetCollectionId: UUID? = nil
    @State private var newFolderName: String = "新建文件夹"

    @State private var isRenamingFolder = false
    @State private var targetFolderId: UUID? = nil
    @State private var renameFolderName: String = ""

    @State private var isCreatingCollection = false
    @State private var newCollectionName: String = "新建集合"

    @State private var isRenamingCollection = false
    @State private var renameCollectionName: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Bruno 风格搜索过滤条
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))

                TextField("检索接口或方法 (Filter...)", text: $appState.searchQuery)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)

                if !appState.searchQuery.isEmpty {
                    Button(action: { appState.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.isQuickOpenPresented = true
                    }
                }) {
                    Text("⌘P")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("打开全局快速跳转面板 (⌘P)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                // MARK: - 1. 集合与用例树 (支持多级文件夹折叠与增删)
                Section(header: collectionsHeader) {
                    ForEach(appState.workspace.collections) { collection in
                        let rootRequests = appState.filteredRequests(in: collection, folderId: nil)
                        let folders = collection.folders

                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { appState.isCollectionExpanded(collection.id) },
                                set: { _ in appState.toggleCollectionExpanded(collection.id) }
                            )
                        ) {
                            // 1. 集合内的文件夹列表 (可独立折叠/展开)
                            ForEach(folders) { folder in
                                let folderRequests = appState.filteredRequests(in: collection, folderId: folder.id)

                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { appState.isFolderExpanded(folder.id) },
                                        set: { _ in appState.toggleFolderExpanded(folder.id) }
                                    )
                                ) {
                                    if folderRequests.isEmpty {
                                        Text("空文件夹 (点击 + 添加请求)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 4)
                                            .padding(.leading, 12)
                                    } else {
                                        ForEach(folderRequests) { request in
                                            RequestRowView(
                                                request: request,
                                                isSelected: appState.activeTabId == request.id,
                                                isDirty: appState.dirtyTabIds.contains(request.id),
                                                onSelect: { appState.openTab(for: request) },
                                                onDuplicate: { appState.duplicateRequest(id: request.id) },
                                                onDelete: { appState.deleteRequest(id: request.id) }
                                            )
                                            .padding(.leading, 10)
                                        }
                                    }
                                } label: {
                                    FolderRowHeaderView(
                                        folder: folder,
                                        requestCount: folderRequests.count,
                                        onNewRequest: {
                                            appState.createNewRequest(in: collection.id, folderId: folder.id)
                                        },
                                        onRename: {
                                            targetFolderId = folder.id
                                            renameFolderName = folder.name
                                            isRenamingFolder = true
                                        },
                                        onOpenSettings: {
                                            appState.editingFolderTarget = FolderSettingsTarget(collectionId: collection.id, folderId: folder.id)
                                        },
                                        onRunFolder: {
                                            appState.activeRunnerConfig = CollectionRunConfig(
                                                collectionId: collection.id,
                                                folderId: folder.id,
                                                collectionName: collection.name,
                                                folderName: folder.name,
                                                environmentId: appState.workspace.activeEnvironmentId
                                            )
                                        },
                                        onDelete: {
                                            appState.deleteFolder(id: folder.id)
                                        }
                                    )
                                }
                            }

                            // 2. 根目录下的独立请求 (不属于任何文件夹)
                            if rootRequests.isEmpty && folders.isEmpty && !appState.searchQuery.isEmpty {
                                Text("无匹配请求")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(rootRequests) { request in
                                    RequestRowView(
                                        request: request,
                                        isSelected: appState.activeTabId == request.id,
                                        isDirty: appState.dirtyTabIds.contains(request.id),
                                        onSelect: { appState.openTab(for: request) },
                                        onDuplicate: { appState.duplicateRequest(id: request.id) },
                                        onDelete: { appState.deleteRequest(id: request.id) }
                                    )
                                }
                            }
                        } label: {
                            CollectionRowHeaderView(
                                collection: collection,
                                totalCount: collection.requests.count,
                                onNewRequest: {
                                    appState.createNewRequest(in: collection.id)
                                },
                                onNewFolder: {
                                    targetCollectionId = collection.id
                                    newFolderName = "新建文件夹"
                                    isCreatingFolder = true
                                },
                                onRename: {
                                    targetCollectionId = collection.id
                                    renameCollectionName = collection.name
                                    isRenamingCollection = true
                                },
                                onOpenSettings: {
                                    appState.editingCollectionTarget = CollectionSettingsTarget(collectionId: collection.id)
                                },
                                onExportToDirectory: {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.canCreateDirectories = true
                                    panel.prompt = "导出到此目录"
                                    panel.message = "选择用于保存集合 Git 目录结构的父目录"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        appState.exportCollectionToDirectory(collectionId: collection.id, targetDir: url)
                                    }
                                },
                                onRunCollection: {
                                    appState.activeRunnerConfig = CollectionRunConfig(
                                        collectionId: collection.id,
                                        folderId: nil,
                                        collectionName: collection.name,
                                        folderName: nil,
                                        environmentId: appState.workspace.activeEnvironmentId
                                    )
                                },
                                onDelete: {
                                    appState.deleteCollection(id: collection.id)
                                }
                            )
                        }
                    }
                }

                // MARK: - 2. 本地 Proto 仓库与扩展中心
                Section(header: protoHeader) {
                    Button(action: {
                        appState.isProtoExplorerPresented = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.gearshape.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 13))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Proto 仓库与 Import 路径")
                                    .font(.system(size: 12, weight: .medium))
                                Text("\(ProtoRepository.shared.loadedFiles.count) 个文件 • \(ProtoRepository.shared.importPaths.count) 个包含路径")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - 3. 调用历史
                if !appState.history.isEmpty {
                    Section(header: Text("历史调用 (RECENT CALLS)")) {
                        ForEach(appState.history.prefix(5)) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(item.isSuccess ? Color.green : Color.red)
                                    .frame(width: 7, height: 7)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.statusName)
                                        .font(.system(size: 11, weight: .medium))
                                    Text(String(format: "%.1f ms • %d B", item.durationMs, item.responseSize))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Pulsar")
        // 新建/重命名 弹窗
        .alert("新建文件夹", isPresented: $isCreatingFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                if let colId = targetCollectionId, !newFolderName.isEmpty {
                    appState.createFolder(in: colId, name: newFolderName)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请输入要在集合内创建的文件夹名称")
        }
        .alert("重命名文件夹", isPresented: $isRenamingFolder) {
            TextField("新名称", text: $renameFolderName)
            Button("确定") {
                if let fid = targetFolderId, !renameFolderName.isEmpty {
                    appState.renameFolder(id: fid, newName: renameFolderName)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("新建集合", isPresented: $isCreatingCollection) {
            TextField("集合名称", text: $newCollectionName)
            Button("创建") {
                if !newCollectionName.isEmpty {
                    appState.createNewCollection(name: newCollectionName)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名集合", isPresented: $isRenamingCollection) {
            TextField("集合名称", text: $renameCollectionName)
            Button("确定") {
                if let cid = targetCollectionId, !renameCollectionName.isEmpty {
                    appState.renameCollection(id: cid, newName: renameCollectionName)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $appState.editingCollectionTarget) { target in
            CollectionSettingsView(appState: appState, collectionId: target.collectionId)
                .frame(minWidth: 700, minHeight: 480)
        }
        .sheet(item: $appState.editingFolderTarget) { target in
            FolderSettingsView(appState: appState, collectionId: target.collectionId, folderId: target.folderId)
                .frame(minWidth: 620, minHeight: 420)
        }
    }

    private var collectionsHeader: some View {
        HStack {
            Text("请求集合")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()

            Menu {
                Button(action: {
                    newCollectionName = "新建集合"
                    isCreatingCollection = true
                }) {
                    Label("新建集合", systemImage: "folder.badge.plus")
                }
                Button(action: {
                    appState.createNewRequest()
                }) {
                    Label("新建请求", systemImage: "doc.badge.plus")
                }
                Divider()
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "导入"
                    panel.message = "选择包含 collection.json 的 Git 集合目录"
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.importCollectionFromDirectory(from: url)
                    }
                }) {
                    Label("从 Git 目录导入集合...", systemImage: "folder.badge.gearshape")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("新建集合或请求")
        }
    }

    private var protoHeader: some View {
        HStack {
            Text("PROTO 协议与扩展")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: {
                appState.isProtoExplorerPresented = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("管理本地 Proto 仓库与 Import Path (-I)")
        }
    }
}

/// Collection 栏行标头：支持 + 展开菜单（新建请求 / 新建文件夹）与上下文菜单
struct CollectionRowHeaderView: View {
    let collection: CollectionModel
    let totalCount: Int
    let onNewRequest: () -> Void
    let onNewFolder: () -> Void
    let onRename: () -> Void
    let onOpenSettings: () -> Void
    let onExportToDirectory: () -> Void
    let onRunCollection: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 12))

            Text(collection.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer()

            // 点击 + 弹出菜单：明确提供“新建请求”与“新建文件夹”两种选择
            Menu {
                Button(action: onNewRequest) {
                    Label("新建请求", systemImage: "doc.badge.plus")
                }
                Button(action: onNewFolder) {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
                Divider()
                Button(action: onRunCollection) {
                    Label("运行集合 (Run Collection...)", systemImage: "play.circle")
                }
                Divider()
                Button(action: onOpenSettings) {
                    Label("集合设置 (Settings)", systemImage: "gearshape")
                }
                Button(action: onExportToDirectory) {
                    Label("导出为 Git 目录...", systemImage: "arrow.up.bin")
                }
                Button(action: onRename) {
                    Label("重命名集合", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("删除集合", systemImage: "trash")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("新建请求或文件夹")

            Text("\(totalCount)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .contextMenu {
            Button(action: onNewRequest) {
                Label("新建请求", systemImage: "doc.badge.plus")
            }
            Button(action: onNewFolder) {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
            Divider()
            Button(action: onRunCollection) {
                Label("运行集合 (Run Collection...)", systemImage: "play.circle")
            }
            Divider()
            Button(action: onOpenSettings) {
                Label("集合设置 (Settings)", systemImage: "gearshape")
            }
            Button(action: onExportToDirectory) {
                Label("导出为 Git 目录...", systemImage: "arrow.up.bin")
            }
            Button(action: onRename) {
                Label("重命名集合", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除集合", systemImage: "trash")
            }
        }
    }
}

/// Folder 栏行标头：展示文件夹图标、数量、在文件夹内新建请求与右键菜单
struct FolderRowHeaderView: View {
    let folder: FolderModel
    let requestCount: Int
    let onNewRequest: () -> Void
    let onRename: () -> Void
    let onOpenSettings: () -> Void
    let onRunFolder: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
                .font(.system(size: 11))

            Text(folder.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            // 点击 + 直接在此文件夹内新建请求
            Button(action: onNewRequest) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("在此文件夹下新建请求")

            Text("\(requestCount)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .contextMenu {
            Button(action: onNewRequest) {
                Label("在此文件夹下新建请求", systemImage: "doc.badge.plus")
            }
            Divider()
            Button(action: onRunFolder) {
                Label("运行此文件夹 (Run Folder...)", systemImage: "play.circle")
            }
            Divider()
            Button(action: onOpenSettings) {
                Label("文件夹设置 (Settings)", systemImage: "gearshape")
            }
            Button(action: onRename) {
                Label("重命名文件夹", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除文件夹", systemImage: "trash")
            }
        }
    }
}

/// Bruno 风格请求项列表行 (带脏标记与清晰标签)
struct RequestRowView: View {
    let request: RequestModel
    let isSelected: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Method 徽标胶囊 (类似 Bruno 的 GET/POST 彩色标识)
                Text(request.callType.shortTag)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(callTypeColor)
                    .frame(width: 22, height: 16)
                    .background(callTypeColor.opacity(0.12))
                    .cornerRadius(3)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(request.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)

                        if isDirty {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                                .help("有未保存的修改 (⌘S 保存)")
                        }
                    }

                    if !request.methodName.isEmpty {
                        Text(request.methodName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("复制此请求 (Duplicate)", action: onDuplicate)
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除请求", systemImage: "trash")
            }
        }
    }

    private var callTypeColor: Color {
        switch request.callType {
        case .unary: return .blue
        case .serverStreaming: return .purple
        case .clientStreaming: return .orange
        case .bidiStreaming: return .green
        }
    }
}
