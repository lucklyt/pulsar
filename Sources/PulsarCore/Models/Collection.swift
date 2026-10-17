import Foundation

/// 集合内的文件夹
public struct FolderModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var collectionId: UUID
    public var requestIds: [UUID]

    public init(id: UUID = UUID(), name: String, collectionId: UUID, requestIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.requestIds = requestIds
    }
}

/// 请求集合（如 OrderService 接口集、UserAccount 接口集）
public struct CollectionModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var folders: [FolderModel]
    public var requests: [RequestModel]
    public var variables: [VariableItem]
    public var defaultAddress: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        folders: [FolderModel] = [],
        requests: [RequestModel] = [],
        variables: [VariableItem] = [],
        defaultAddress: String = "{{grpc_host}}:{{grpc_port}}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.folders = folders
        self.requests = requests
        self.variables = variables
        self.defaultAddress = defaultAddress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 工作空间模型（组织环境、集合与全局偏好）
public struct WorkspaceModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var collections: [CollectionModel]
    public var environments: [EnvironmentModel]
    public var activeEnvironmentId: UUID?
    public var globalVariables: [VariableItem]

    public init(
        id: UUID = UUID(),
        name: String = "Default Workspace",
        collections: [CollectionModel] = [],
        environments: [EnvironmentModel] = [],
        activeEnvironmentId: UUID? = nil,
        globalVariables: [VariableItem] = []
    ) {
        self.id = id
        self.name = name
        self.collections = collections
        self.environments = environments
        self.activeEnvironmentId = activeEnvironmentId
        self.globalVariables = globalVariables
    }
}
