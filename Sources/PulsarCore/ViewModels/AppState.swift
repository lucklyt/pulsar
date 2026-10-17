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

    // 模态弹窗控制
    @Published public var isEnvironmentModalPresented: Bool = false
    @Published public var isProtoExplorerPresented: Bool = false

    // 展开/折叠状态追踪 (Collection 与 Folder)
    @Published public var expandedCollectionIds: Set<UUID> = []
    @Published public var expandedFolderIds: Set<UUID> = []

    private let storage = StorageManager.shared

    public init() {
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

    // MARK: - 执行调用

    @MainActor
    public func executeCurrentRequest() {
        guard let req = activeRequest, !isExecuting else { return }

        isExecuting = true
        activeStreamEvents = []

        executionTask = Task { [weak self] in
            guard let self = self else { return }
            let resp = await GRPCClientEngine.shared.execute(
                request: req,
                activeEnvironment: self.activeEnvironment,
                globalVariables: self.workspace.globalVariables,
                onStreamEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.activeStreamEvents.append(event)
                    }
                }
            )

            await MainActor.run {
                self.responses[req.id] = resp
                self.history.insert(resp, at: 0)
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
}

public enum SplitLayoutMode: String, Codable, CaseIterable {
    case horizontal = "左右并排"
    case vertical = "上下并排"
}
