import Foundation
import SwiftUI
import Combine

/// 全局应用状态中枢 (遵循 MVVM 模式，负责各视图间数据协同与响应式更新)
public final class AppState: ObservableObject {
    @Published public var workspace: WorkspaceModel
    @Published public var openTabIds: [UUID] = []
    @Published public var activeTabId: UUID?

    @Published public var responses: [UUID: RPCResponse] = [:] // RequestID -> Response
    @Published public var activeStreamEvents: [StreamEvent] = []
    @Published public var isExecuting: Bool = false
    @Published public var executionTask: Task<Void, Never>?

    @Published public var history: [RPCResponse] = []
    @Published public var searchQuery: String = ""

    // Bruno 风格工作流控制
    @Published public var dirtyTabIds: Set<UUID> = []
    @Published public var layoutMode: SplitLayoutMode = .horizontal
    @Published public var isQuickEnvPopoverPresented: Bool = false
    @Published public var isQuickOpenPresented: Bool = false

    // 模态弹窗控制
    @Published public var isEnvironmentModalPresented: Bool = false
    @Published public var isProtoExplorerPresented: Bool = false
    @Published public var editingCollectionTarget: CollectionSettingsTarget? = nil
    @Published public var editingFolderTarget: FolderSettingsTarget? = nil
    @Published public var activeRunnerConfig: CollectionRunConfig? = nil
    @Published public var responseSnapshots: [UUID: RPCResponse] = [:]

    // 展开/折叠状态追踪 (Collection 与 Folder)
    @Published public var expandedCollectionIds: Set<UUID> = []
    @Published public var expandedFolderIds: Set<UUID> = []

    private let storage: StorageManager

    public init(storage: StorageManager = .shared) {
        self.storage = storage
        let loadedWorkspace = storage.loadWorkspace()
        self.workspace = loadedWorkspace
        self.history = storage.loadHistory()

        // 默认展开所有集合与文件夹
        self.expandedCollectionIds = Set(loadedWorkspace.collections.map { $0.id })
        self.expandedFolderIds = Set(loadedWorkspace.collections.flatMap { $0.folders.map { $0.id } })

        // 默认打开首个集合的首个请求
        if let firstReq = loadedWorkspace.collections.first?.requests.first {
            self.openTabIds = [firstReq.id]
            self.activeTabId = firstReq.id
        }
    }

    // MARK: - 计算属性

    public var activeEnvironment: EnvironmentModel? {
        guard let id = workspace.activeEnvironmentId else { return nil }
        return workspace.environments.first { $0.id == id }
    }

    public var activeRequest: RequestModel? {
        guard let id = activeTabId else { return nil }
        for col in workspace.collections {
            if let req = col.requests.first(where: { $0.id == id }) {
                return req
            }
        }
        return nil
    }

    public var activeResponse: RPCResponse? {
        guard let id = activeTabId else { return nil }
        return responses[id]
    }

    // MARK: - 快速直达 (Quick Open) 请求索引与面包屑
    public struct RequestPathItem: Identifiable, Equatable {
        public var id: UUID { request.id }
        public let request: RequestModel
        public let collectionName: String
        public let folderName: String?

        public init(request: RequestModel, collectionName: String, folderName: String?) {
            self.request = request
            self.collectionName = collectionName
            self.folderName = folderName
        }
    }

    public func allRequestsWithBreadcrumbs() -> [RequestPathItem] {
        var items: [RequestPathItem] = []
        for col in workspace.collections {
            for req in col.requests {
                let folder = col.folders.first(where: { $0.id == req.folderId })
                items.append(RequestPathItem(
                    request: req,
                    collectionName: col.name,
                    folderName: folder?.name
                ))
            }
        }
        return items
    }

    // MARK: - 标签页 (Tabs) 控制

    public func openTab(for request: RequestModel) {
        if !openTabIds.contains(request.id) {
            openTabIds.append(request.id)
        }
        activeTabId = request.id
    }

    public func closeTab(id: UUID) {
        guard let index = openTabIds.firstIndex(of: id) else { return }
        openTabIds.remove(at: index)

        if activeTabId == id {
            if !openTabIds.isEmpty {
                let newIndex = min(index, openTabIds.count - 1)
                activeTabId = openTabIds[newIndex]
            } else {
                activeTabId = nil
            }
        }
    }

    // MARK: - 集合与文件夹展开/折叠状态

    public func isCollectionExpanded(_ id: UUID) -> Bool {
        expandedCollectionIds.contains(id)
    }

    public func toggleCollectionExpanded(_ id: UUID) {
        if expandedCollectionIds.contains(id) {
            expandedCollectionIds.remove(id)
        } else {
            expandedCollectionIds.insert(id)
        }
    }

    public func isFolderExpanded(_ id: UUID) -> Bool {
        expandedFolderIds.contains(id)
    }

    public func toggleFolderExpanded(_ id: UUID) {
        if expandedFolderIds.contains(id) {
            expandedFolderIds.remove(id)
        } else {
            expandedFolderIds.insert(id)
        }
    }

    // MARK: - 请求增删改

    public func updateActiveRequest(_ mutated: RequestModel) {
        for cIndex in 0..<workspace.collections.count {
            if let rIndex = workspace.collections[cIndex].requests.firstIndex(where: { $0.id == mutated.id }) {
                workspace.collections[cIndex].requests[rIndex] = mutated
                saveState()
                return
            }
        }
    }

    public func createNewRequest(in collectionId: UUID? = nil, folderId: UUID? = nil) {
        let targetColId = collectionId ?? workspace.collections.first?.id
        guard let colIndex = workspace.collections.firstIndex(where: { $0.id == targetColId }) else { return }

        var newReq = RequestModel(name: "New gRPC Request", collectionId: targetColId, folderId: folderId)
        newReq.address = workspace.collections[colIndex].defaultAddress
        workspace.collections[colIndex].requests.append(newReq)

        if let fid = folderId, let fIndex = workspace.collections[colIndex].folders.firstIndex(where: { $0.id == fid }) {
            if !workspace.collections[colIndex].folders[fIndex].requestIds.contains(newReq.id) {
                workspace.collections[colIndex].folders[fIndex].requestIds.append(newReq.id)
            }
            expandedFolderIds.insert(fid)
        }
        if let cid = targetColId {
            expandedCollectionIds.insert(cid)
        }

        openTab(for: newReq)
        saveState()
    }

    public func createFolder(in collectionId: UUID, name: String = "新建文件夹") {
        guard let colIndex = workspace.collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let folder = FolderModel(name: name, collectionId: collectionId)
        workspace.collections[colIndex].folders.append(folder)
        expandedCollectionIds.insert(collectionId)
        expandedFolderIds.insert(folder.id)
        saveState()
    }

    public func renameFolder(id: UUID, newName: String) {
        for cIndex in 0..<workspace.collections.count {
            if let fIndex = workspace.collections[cIndex].folders.firstIndex(where: { $0.id == id }) {
                workspace.collections[cIndex].folders[fIndex].name = newName
                saveState()
                return
            }
        }
    }

    public func deleteFolder(id: UUID) {
        for cIndex in 0..<workspace.collections.count {
            if let fIndex = workspace.collections[cIndex].folders.firstIndex(where: { $0.id == id }) {
                let folder = workspace.collections[cIndex].folders[fIndex]
                for reqId in folder.requestIds {
                    closeTab(id: reqId)
                }
                workspace.collections[cIndex].requests.removeAll { $0.folderId == id }
                workspace.collections[cIndex].folders.remove(at: fIndex)
                expandedFolderIds.remove(id)
                saveState()
                return
            }
        }
    }

    public func createNewCollection(name: String = "New Collection") {
        let col = CollectionModel(name: name)
        workspace.collections.append(col)
        expandedCollectionIds.insert(col.id)
        saveState()
    }

    public func renameCollection(id: UUID, newName: String) {
        if let index = workspace.collections.firstIndex(where: { $0.id == id }) {
            workspace.collections[index].name = newName
            saveState()
        }
    }

    public func deleteCollection(id: UUID) {
        if let index = workspace.collections.firstIndex(where: { $0.id == id }) {
            let col = workspace.collections[index]
            for req in col.requests {
                closeTab(id: req.id)
            }
            workspace.collections.remove(at: index)
            expandedCollectionIds.remove(id)
            saveState()
        }
    }

    public func createRequestFromProtoMethod(_ method: ProtoMethodDescriptor) {
        let targetColId = workspace.collections.first?.id
        guard let colIndex = workspace.collections.firstIndex(where: { $0.id == targetColId }) else { return }

        var req = RequestModel(
            name: "\(method.name)",
            collectionId: targetColId,
            address: workspace.collections[colIndex].defaultAddress,
            serviceName: method.serviceName,
            methodName: method.name,
            callType: method.callType
        )

        if let inputMsg = ProtoRepository.shared.findMessage(by: method.inputMessage.name) {
            req.payload = MockJSONGenerator.shared.generateMockJSON(for: inputMsg)
        }

        ProtoRepository.shared.applyExtensions(to: &req, method: method)

        workspace.collections[colIndex].requests.append(req)
        openTab(for: req)
        saveState()
    }

    public func deleteRequest(id: UUID) {
        closeTab(id: id)
        for cIndex in 0..<workspace.collections.count {
            workspace.collections[cIndex].requests.removeAll { $0.id == id }
        }
        saveState()
    }

    public func switchEnvironment(id: UUID?) {
        workspace.activeEnvironmentId = id
        saveState()
    }

    // MARK: - 层级配置与继承解析 (Hierarchical Inheritance Resolution)

    public struct InheritedHeaderItem: Identifiable, Equatable {
        public var id: UUID { header.id }
        public var header: MetadataHeader
        public var source: String

        public init(header: MetadataHeader, source: String) {
            self.header = header
            self.source = source
        }
    }

    public struct EffectiveRequestConfig {
        public var effectiveRequest: RequestModel
        public var effectiveAuth: AuthConfig
        public var authSource: String
        public var inheritedMetadata: [InheritedHeaderItem]
        public var effectiveSecurity: TLSConfig
        public var securitySource: String
        public var effectiveTimeout: Double
    }

    public func parentCollection(for requestId: UUID) -> CollectionModel? {
        for col in workspace.collections {
            if col.requests.contains(where: { $0.id == requestId }) {
                return col
            }
        }
        return nil
    }

    public func parentFolder(for requestId: UUID) -> FolderModel? {
        guard let col = parentCollection(for: requestId) else { return nil }
        guard let req = col.requests.first(where: { $0.id == requestId }),
              let folderId = req.folderId else { return nil }
        return col.folders.first(where: { $0.id == folderId })
    }

    public func resolveEffectiveConfig(for request: RequestModel) -> EffectiveRequestConfig {
        let parentCol = parentCollection(for: request.id)
        let parentFold = parentFolder(for: request.id)

        // 1. Auth 逐级继承: Request -> Folder -> Collection -> None
        let effectiveAuth: AuthConfig
        let authSource: String
        if request.auth.type != .inherit {
            effectiveAuth = request.auth
            authSource = "请求独立配置"
        } else if let fold = parentFold, fold.auth.type != .inherit {
            effectiveAuth = fold.auth
            authSource = "继承自文件夹 [\(fold.name)]"
        } else if let col = parentCol, col.auth.type != .inherit && col.auth.type != .none {
            effectiveAuth = col.auth
            authSource = "继承自集合 [\(col.name)]"
        } else {
            effectiveAuth = AuthConfig(type: .none)
            authSource = "无认证 (未配置)"
        }

        // 2. Metadata 逐级合并: Collection -> Folder -> Request (子级同名键覆盖父级)
        var mergedHeadersMap: [String: MetadataHeader] = [:]
        var inheritedList: [InheritedHeaderItem] = []

        if let col = parentCol {
            for h in col.sharedMetadata where h.isEnabled && !h.key.trimmingCharacters(in: .whitespaces).isEmpty {
                mergedHeadersMap[h.key.lowercased()] = h
                inheritedList.append(InheritedHeaderItem(header: h, source: "集合: \(col.name)"))
            }
        }

        if let fold = parentFold {
            for h in fold.sharedMetadata where h.isEnabled && !h.key.trimmingCharacters(in: .whitespaces).isEmpty {
                mergedHeadersMap[h.key.lowercased()] = h
                inheritedList.append(InheritedHeaderItem(header: h, source: "文件夹: \(fold.name)"))
            }
        }

        for h in request.metadata where !h.key.trimmingCharacters(in: .whitespaces).isEmpty {
            mergedHeadersMap[h.key.lowercased()] = h
        }

        let effectiveMetadata = Array(mergedHeadersMap.values)

        // 3. Security / TLS 继承: Request -> Collection
        let effectiveSecurity: TLSConfig
        let securitySource: String
        if request.tls.mode != .inherit {
            effectiveSecurity = request.tls
            securitySource = "请求独立配置"
        } else if let col = parentCol {
            effectiveSecurity = col.security
            securitySource = "继承自集合 [\(col.name)]"
        } else {
            effectiveSecurity = TLSConfig(mode: .plaintext)
            securitySource = "默认明文"
        }

        // 4. 超时继承
        let effectiveTimeout: Double = (request.timeoutSeconds > 0) ? request.timeoutSeconds : (parentCol?.timeoutSeconds ?? 30.0)

        var finalReq = request
        finalReq.auth = effectiveAuth
        finalReq.metadata = effectiveMetadata
        finalReq.tls = effectiveSecurity
        finalReq.timeoutSeconds = effectiveTimeout

        return EffectiveRequestConfig(
            effectiveRequest: finalReq,
            effectiveAuth: effectiveAuth,
            authSource: authSource,
            inheritedMetadata: inheritedList,
            effectiveSecurity: effectiveSecurity,
            securitySource: securitySource,
            effectiveTimeout: effectiveTimeout
        )
    }

    public func updateCollection(_ collection: CollectionModel) {
        if let idx = workspace.collections.firstIndex(where: { $0.id == collection.id }) {
            workspace.collections[idx] = collection
            saveState()
        }
    }

    public func updateFolder(in collectionId: UUID, folder: FolderModel) {
        if let cIdx = workspace.collections.firstIndex(where: { $0.id == collectionId }),
           let fIdx = workspace.collections[cIdx].folders.firstIndex(where: { $0.id == folder.id }) {
            workspace.collections[cIdx].folders[fIdx] = folder
            saveState()
        }
    }

    // MARK: - 执行调用

    @MainActor
    public func executeCurrentRequest() {
        guard let req = activeRequest, !isExecuting else { return }

        let effectiveConfig = resolveEffectiveConfig(for: req)

        isExecuting = true
        activeStreamEvents = []

        executionTask = Task { [weak self] in
            guard let self = self else { return }
            let resp = await GRPCClientEngine.shared.execute(
                request: effectiveConfig.effectiveRequest,
                activeEnvironment: self.activeEnvironment,
                globalVariables: self.workspace.globalVariables,
                onStreamEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.activeStreamEvents.append(event)
                    }
                }
            )

            await MainActor.run {
                var finalResp = resp

                // 1. 执行声明式断言校验 (Bruno Assertions)
                let assertionResults = AssertionEngine.shared.evaluateAssertions(
                    rules: req.assertions,
                    response: resp
                )
                finalResp.assertionResults = assertionResults

                // 2. 提取响应字段到环境变量 (Post-Response Vars)
                let extracted = AssertionEngine.shared.extractVariables(
                    rules: req.responseVars,
                    response: resp
                )
                finalResp.extractedVariables = extracted

                // 如果提取到了变量，自动同步更新到当前活动环境并持久化
                if !extracted.isEmpty, let envId = self.workspace.activeEnvironmentId,
                   let envIdx = self.workspace.environments.firstIndex(where: { $0.id == envId }) {
                    for (k, v) in extracted {
                        if let vIdx = self.workspace.environments[envIdx].variables.firstIndex(where: { $0.key == k }) {
                            self.workspace.environments[envIdx].variables[vIdx].value = v
                        } else {
                            self.workspace.environments[envIdx].variables.append(
                                VariableItem(key: k, value: v, notes: "由请求 [\(req.name)] 自动提取")
                            )
                        }
                    }
                    self.saveState()
                }

                self.responses[req.id] = finalResp
                self.history.insert(finalResp, at: 0)
                if self.history.count > 100 {
                    self.history.removeLast()
                }
                self.storage.saveHistory(self.history)
                self.isExecuting = false
                self.executionTask = nil
            }
        }
    }

    public func cancelExecution() {
        executionTask?.cancel()
        executionTask = nil
        isExecuting = false
    }

    public func saveState() {
        try? storage.saveWorkspace(workspace)
    }

    // MARK: - 响应快照管理 (Response Snapshots)

    public func saveResponseSnapshot(for requestId: UUID, response: RPCResponse) {
        responseSnapshots[requestId] = response
    }

    public func clearResponseSnapshot(for requestId: UUID) {
        responseSnapshots.removeValue(forKey: requestId)
    }

    // MARK: - Bruno 风格操作辅助

    public func markDirty(id: UUID) {
        dirtyTabIds.insert(id)
    }

    public func saveActiveRequest() {
        guard let id = activeTabId else { return }
        dirtyTabIds.remove(id)
        saveState()
    }

    public func duplicateRequest(id: UUID) {
        for cIndex in 0..<workspace.collections.count {
            if let original = workspace.collections[cIndex].requests.first(where: { $0.id == id }) {
                var copy = original
                copy.id = UUID()
                copy.name = "\(original.name) (Copy)"
                workspace.collections[cIndex].requests.append(copy)
                openTab(for: copy)
                saveState()
                return
            }
        }
    }

    public func filteredRequests(in collection: CollectionModel, folderId: UUID? = nil) -> [RequestModel] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let scopedList: [RequestModel]
        if let fid = folderId {
            scopedList = collection.requests.filter { $0.folderId == fid }
        } else {
            // 根级别请求：folderId 为 nil，或者指向已不存在的文件夹
            let allFolderIds = Set(collection.folders.map { $0.id })
            scopedList = collection.requests.filter { req in
                guard let fid = req.folderId else { return true }
                return !allFolderIds.contains(fid)
            }
        }

        guard !q.isEmpty else { return scopedList }
        return scopedList.filter { req in
            req.name.lowercased().contains(q) ||
            req.methodName.lowercased().contains(q) ||
            req.serviceName.lowercased().contains(q) ||
            req.address.lowercased().contains(q)
        }
    }

    public func filteredRequests(in collection: CollectionModel) -> [RequestModel] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return collection.requests }
        return collection.requests.filter { req in
            req.name.lowercased().contains(q) ||
            req.methodName.lowercased().contains(q) ||
            req.serviceName.lowercased().contains(q) ||
            req.address.lowercased().contains(q)
        }
    }

    // MARK: - Git 友好型多文件目录同步与导入导出

    public func exportCollectionToDirectory(collectionId: UUID, targetDir: URL) {
        guard let col = workspace.collections.first(where: { $0.id == collectionId }) else { return }
        do {
            try CollectionDirectorySyncService.shared.exportCollection(
                col,
                environments: workspace.environments,
                to: targetDir
            )
        } catch {
            print("Failed to export collection: \(error)")
        }
    }

    public func importCollectionFromDirectory(from dir: URL) {
        do {
            let (importedCol, importedEnvs) = try CollectionDirectorySyncService.shared.importCollection(from: dir)
            workspace.collections.append(importedCol)
            expandedCollectionIds.insert(importedCol.id)

            // 合并新导入的环境变量
            for env in importedEnvs {
                if !workspace.environments.contains(where: { $0.name == env.name }) {
                    workspace.environments.append(env)
                }
            }
            saveState()
        } catch {
            print("Failed to import collection: \(error)")
        }
    }
}

public enum SplitLayoutMode: String, Codable, CaseIterable {
    case horizontal = "左右并排"
    case vertical = "上下并排"
}

public struct CollectionSettingsTarget: Identifiable, Equatable {
    public var id: UUID { collectionId }
    public let collectionId: UUID

    public init(collectionId: UUID) {
        self.collectionId = collectionId
    }
}

public struct FolderSettingsTarget: Identifiable, Equatable {
    public var id: UUID { folderId }
    public let collectionId: UUID
    public let folderId: UUID

    public init(collectionId: UUID, folderId: UUID) {
        self.collectionId = collectionId
        self.folderId = folderId
    }
}
