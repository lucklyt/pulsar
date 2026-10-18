import Foundation

/// 集合内的文件夹 (支持共享 Headers、Auth 与专用变量)
public struct FolderModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var collectionId: UUID
    public var requestIds: [UUID]
    public var sharedMetadata: [MetadataHeader]
    public var auth: AuthConfig

    public init(
        id: UUID = UUID(),
        name: String,
        collectionId: UUID,
        requestIds: [UUID] = [],
        sharedMetadata: [MetadataHeader] = [],
        auth: AuthConfig = AuthConfig(type: .inherit)
    ) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.requestIds = requestIds
        self.sharedMetadata = sharedMetadata
        self.auth = auth
    }

    enum CodingKeys: String, CodingKey {
        case id, name, collectionId, requestIds, sharedMetadata, auth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "新建文件夹"
        self.collectionId = try container.decodeIfPresent(UUID.self, forKey: .collectionId) ?? UUID()
        self.requestIds = try container.decodeIfPresent([UUID].self, forKey: .requestIds) ?? []
        self.sharedMetadata = try container.decodeIfPresent([MetadataHeader].self, forKey: .sharedMetadata) ?? []
        self.auth = try container.decodeIfPresent(AuthConfig.self, forKey: .auth) ?? AuthConfig(type: .inherit)
    }
}

/// 请求集合（如 OrderService 接口集、UserAccount 接口集，支持集合级共享 Headers、Auth、默认 TLS 与超时）
public struct CollectionModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var folders: [FolderModel]
    public var requests: [RequestModel]
    public var variables: [VariableItem]
    public var defaultAddress: String
    public var sharedMetadata: [MetadataHeader]
    public var auth: AuthConfig
    public var security: TLSConfig
    public var timeoutSeconds: Double
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
        sharedMetadata: [MetadataHeader] = [],
        auth: AuthConfig = AuthConfig(type: .none),
        security: TLSConfig = TLSConfig(mode: .plaintext),
        timeoutSeconds: Double = 30.0,
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
        self.sharedMetadata = sharedMetadata
        self.auth = auth
        self.security = security
        self.timeoutSeconds = timeoutSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, notes, folders, requests, variables, defaultAddress
        case sharedMetadata, auth, security, timeoutSeconds, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "新建集合"
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.folders = try container.decodeIfPresent([FolderModel].self, forKey: .folders) ?? []
        self.requests = try container.decodeIfPresent([RequestModel].self, forKey: .requests) ?? []
        self.variables = try container.decodeIfPresent([VariableItem].self, forKey: .variables) ?? []
        self.defaultAddress = try container.decodeIfPresent(String.self, forKey: .defaultAddress) ?? "{{grpc_host}}:{{grpc_port}}"
        self.sharedMetadata = try container.decodeIfPresent([MetadataHeader].self, forKey: .sharedMetadata) ?? []
        self.auth = try container.decodeIfPresent(AuthConfig.self, forKey: .auth) ?? AuthConfig(type: .none)
        self.security = try container.decodeIfPresent(TLSConfig.self, forKey: .security) ?? TLSConfig(mode: .plaintext)
        self.timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 30.0
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
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
