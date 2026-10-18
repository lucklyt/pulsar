import Foundation

/// gRPC 4 种方法调用类型
public enum GRPCCallType: String, Codable, CaseIterable, Identifiable {
    case unary = "UNARY"
    case serverStreaming = "SERVER_STREAMING"
    case clientStreaming = "CLIENT_STREAMING"
    case bidiStreaming = "BIDI_STREAMING"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unary: return "Unary (一问一答)"
        case .serverStreaming: return "Server Stream (服务端流)"
        case .clientStreaming: return "Client Stream (客户端流)"
        case .bidiStreaming: return "Bidirectional (双向流)"
        }
    }

    public var shortTag: String {
        switch self {
        case .unary: return "UN"
        case .serverStreaming: return "SS"
        case .clientStreaming: return "CS"
        case .bidiStreaming: return "BD"
        }
    }
}

/// Metadata 请求头键值对
public struct MetadataHeader: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), key: String, value: String, isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}

/// 身份验证配置
public struct AuthConfig: Codable, Equatable, Hashable {
    public enum AuthType: String, Codable, CaseIterable {
        case inherit = "继承上级 (Inherit)"
        case none = "无认证 (None)"
        case bearer = "Bearer Token"
        case apiKey = "API Key (Metadata)"
        case basic = "Basic Auth"
    }

    public var type: AuthType
    public var bearerToken: String
    public var apiKeyName: String
    public var apiKeyValue: String
    public var username: String
    public var password: String

    public init(
        type: AuthType = .inherit,
        bearerToken: String = "",
        apiKeyName: String = "x-api-key",
        apiKeyValue: String = "",
        username: String = "",
        password: String = ""
    ) {
        self.type = type
        self.bearerToken = bearerToken
        self.apiKeyName = apiKeyName
        self.apiKeyValue = apiKeyValue
        self.username = username
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case type, bearerToken, apiKeyName, apiKeyValue, username, password
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(AuthType.self, forKey: .type) ?? .inherit
        self.bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        self.apiKeyName = try container.decodeIfPresent(String.self, forKey: .apiKeyName) ?? "x-api-key"
        self.apiKeyValue = try container.decodeIfPresent(String.self, forKey: .apiKeyValue) ?? ""
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
    }
}

/// TLS / mTLS 安全配置
public struct TLSConfig: Codable, Equatable, Hashable {
    public enum Mode: String, Codable, CaseIterable {
        case inherit = "继承集合默认 (Inherit)"
        case plaintext = "明文传输 (Plaintext)"
        case tlsSystem = "标准 TLS (System CA)"
        case tlsCustomCA = "自定义根证书 (Custom CA)"
        case mtls = "双向认证 (mTLS)"
    }

    public var mode: Mode
    public var rootCAPath: String
    public var clientCertPath: String
    public var clientKeyPath: String
    public var serverNameOverride: String
    public var insecureSkipVerify: Bool

    public init(
        mode: Mode = .inherit,
        rootCAPath: String = "",
        clientCertPath: String = "",
        clientKeyPath: String = "",
        serverNameOverride: String = "",
        insecureSkipVerify: Bool = false
    ) {
        self.mode = mode
        self.rootCAPath = rootCAPath
        self.clientCertPath = clientCertPath
        self.clientKeyPath = clientKeyPath
        self.serverNameOverride = serverNameOverride
        self.insecureSkipVerify = insecureSkipVerify
    }

    enum CodingKeys: String, CodingKey {
        case mode, rootCAPath, clientCertPath, clientKeyPath, serverNameOverride, insecureSkipVerify
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .inherit
        self.rootCAPath = try container.decodeIfPresent(String.self, forKey: .rootCAPath) ?? ""
        self.clientCertPath = try container.decodeIfPresent(String.self, forKey: .clientCertPath) ?? ""
        self.clientKeyPath = try container.decodeIfPresent(String.self, forKey: .clientKeyPath) ?? ""
        self.serverNameOverride = try container.decodeIfPresent(String.self, forKey: .serverNameOverride) ?? ""
        self.insecureSkipVerify = try container.decodeIfPresent(Bool.self, forKey: .insecureSkipVerify) ?? false
    }
}

/// 服务发现配置 (Direct / Nacos / Reflection)
public struct ServiceDiscoveryConfig: Codable, Equatable, Hashable {
    public enum ProtocolScheme: String, Codable, CaseIterable {
        case direct = "Direct Dial"
        case nacos = "Nacos Discovery"
    }

    public var scheme: ProtocolScheme
    public var nacosClusters: String // eg: "127.0.0.1:8848"
    public var nacosNamespace: String
    public var nacosServiceName: String
    public var nacosGroupName: String
    public var nacosUsername: String
    public var nacosPassword: String

    public init(
        scheme: ProtocolScheme = .direct,
        nacosClusters: String = "127.0.0.1:8848",
        nacosNamespace: String = "public",
        nacosServiceName: String = "",
        nacosGroupName: String = "DEFAULT_GROUP",
        nacosUsername: String = "",
        nacosPassword: String = ""
    ) {
        self.scheme = scheme
        self.nacosClusters = nacosClusters
        self.nacosNamespace = nacosNamespace
        self.nacosServiceName = nacosServiceName
        self.nacosGroupName = nacosGroupName
        self.nacosUsername = nacosUsername
        self.nacosPassword = nacosPassword
    }
}

/// 单个 gRPC 请求模型
public struct RequestModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var collectionId: UUID?
    public var folderId: UUID?

    public var address: String // 支持 {{host}}:{{port}}
    public var serviceName: String
    public var methodName: String
    public var callType: GRPCCallType

    public var payload: String // JSON 载荷
    public var metadata: [MetadataHeader]
    public var auth: AuthConfig
    public var tls: TLSConfig
    public var discovery: ServiceDiscoveryConfig

    public var timeoutSeconds: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Request",
        collectionId: UUID? = nil,
        folderId: UUID? = nil,
        address: String = "127.0.0.1:50051",
        serviceName: String = "",
        methodName: String = "",
        callType: GRPCCallType = .unary,
        payload: String = "{\n  \n}",
        metadata: [MetadataHeader] = [],
        auth: AuthConfig = AuthConfig(),
        tls: TLSConfig = TLSConfig(),
        discovery: ServiceDiscoveryConfig = ServiceDiscoveryConfig(),
        timeoutSeconds: Double = 15.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.collectionId = collectionId
        self.folderId = folderId
        self.address = address
        self.serviceName = serviceName
        self.methodName = methodName
        self.callType = callType
        self.payload = payload
        self.metadata = metadata
        self.auth = auth
        self.tls = tls
        self.discovery = discovery
        self.timeoutSeconds = timeoutSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
