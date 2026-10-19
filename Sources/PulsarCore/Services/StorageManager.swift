import Foundation

/// 存储管理器：负责将工作空间、集合、环境和历史记录持久化为结构化 JSON 文件
public final class StorageManager {
    public static let shared = StorageManager()

    private let fileManager = FileManager.default
    public let appSupportDir: URL
    public let userHomeDir: URL

    public init(appSupportDir: URL? = nil) {
        let home = fileManager.homeDirectoryForCurrentUser
        self.userHomeDir = home.appendingPathComponent(".pulsar", isDirectory: true)

        if let dir = appSupportDir {
            self.appSupportDir = dir
        } else {
            let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.appSupportDir = baseDir.appendingPathComponent("Pulsar", isDirectory: true)
        }

        try? fileManager.createDirectory(at: self.appSupportDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: self.userHomeDir, withIntermediateDirectories: true)
    }

    public var workspaceFile: URL {
        appSupportDir.appendingPathComponent("workspace.json")
    }

    public var backupWorkspaceFile: URL {
        appSupportDir.appendingPathComponent("workspace.backup.json")
    }

    public var userHomeWorkspaceFile: URL {
        userHomeDir.appendingPathComponent("workspace.json")
    }

    public var historyFile: URL {
        appSupportDir.appendingPathComponent("history.json")
    }

    public var userHomeHistoryFile: URL {
        userHomeDir.appendingPathComponent("history.json")
    }

    public var protoConfigFile: URL {
        appSupportDir.appendingPathComponent("proto_imports.json")
    }

    public var userHomeProtoConfigFile: URL {
        userHomeDir.appendingPathComponent("proto_imports.json")
    }

    // MARK: - Workspace 保存与加载 (三级防丢持久化保护体系)

    public func saveWorkspace(_ workspace: WorkspaceModel) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)

        // 1. 写入主要应用支持目录 (~/Library/Application Support/Pulsar/workspace.json)
        try data.write(to: workspaceFile, options: .atomic)

        // 2. 自动保存本地备份文件 (workspace.backup.json)
        try? data.write(to: backupWorkspaceFile, options: .atomic)

        // 3. 自动同步镜像到用户主目录 ~/.pulsar/workspace.json (双重保障，重新安装/清理缓存防丢失)
        try? fileManager.createDirectory(at: userHomeDir, withIntermediateDirectories: true)
        try? data.write(to: userHomeWorkspaceFile, options: .atomic)
    }

    public func loadWorkspace() -> WorkspaceModel {
        let decoder = JSONDecoder()

        // 1. 优先尝试从主工作区文件加载
        if fileManager.fileExists(atPath: workspaceFile.path),
           let data = try? Data(contentsOf: workspaceFile) {
            do {
                let model = try decoder.decode(WorkspaceModel.self, from: data)
                // 成功解析后同步到备份和用户主目录
                try? data.write(to: backupWorkspaceFile, options: .atomic)
                try? data.write(to: userHomeWorkspaceFile, options: .atomic)
                return model
            } catch {
                print("⚠️ [Pulsar Storage] workspace.json 解析警告: \(error)")
                // 安全备份损坏文件，绝不直接覆盖丢弃
                let timestamp = Int(Date().timeIntervalSince1970)
                let corruptedUrl = appSupportDir.appendingPathComponent("workspace.corrupted-\(timestamp).json")
                try? fileManager.copyItem(at: workspaceFile, to: corruptedUrl)
            }
        }

        // 2. 主文件如果解析异常或不存在，尝试从本地备份 (workspace.backup.json) 恢复
        if fileManager.fileExists(atPath: backupWorkspaceFile.path),
           let data = try? Data(contentsOf: backupWorkspaceFile),
           let backupModel = try? decoder.decode(WorkspaceModel.self, from: data) {
            print("✅ [Pulsar Storage] 已自动从本地备份 workspace.backup.json 恢复工作区配置！")
            try? saveWorkspace(backupModel)
            return backupModel
        }

        // 3. 尝试从用户主目录 ~/.pulsar/workspace.json 镜像恢复 (针对删除应用/重新安装场景)
        if fileManager.fileExists(atPath: userHomeWorkspaceFile.path),
           let data = try? Data(contentsOf: userHomeWorkspaceFile),
           let homeModel = try? decoder.decode(WorkspaceModel.self, from: data) {
            print("✅ [Pulsar Storage] 已自动从 ~/.pulsar/workspace.json 恢复原有配置！")
            try? saveWorkspace(homeModel)
            return homeModel
        }

        // 4. 仅在确实没有任何旧配置的全新安装时，才生成预置演示数据
        let initial = createDefaultWorkspace()
        try? saveWorkspace(initial)
        return initial
    }

    // MARK: - History 保存与加载

    public func saveHistory(_ responses: [RPCResponse]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(responses) {
            try? data.write(to: historyFile, options: .atomic)
            try? data.write(to: userHomeHistoryFile, options: .atomic)
        }
    }

    public func loadHistory() -> [RPCResponse] {
        let decoder = JSONDecoder()
        if fileManager.fileExists(atPath: historyFile.path),
           let data = try? Data(contentsOf: historyFile),
           let list = try? decoder.decode([RPCResponse].self, from: data) {
            return list
        }
        if fileManager.fileExists(atPath: userHomeHistoryFile.path),
           let data = try? Data(contentsOf: userHomeHistoryFile),
           let list = try? decoder.decode([RPCResponse].self, from: data) {
            return list
        }
        return []
    }

    // MARK: - Proto 仓库配置保存与加载 (支持目录与独立文件跨安装持久化)

    public func saveProtoConfig(_ config: ProtoRepositoryConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(config) {
            try? data.write(to: protoConfigFile, options: .atomic)
            try? data.write(to: userHomeProtoConfigFile, options: .atomic)
        }
    }

    public func loadProtoConfig() -> ProtoRepositoryConfig {
        let decoder = JSONDecoder()
        if fileManager.fileExists(atPath: protoConfigFile.path),
           let data = try? Data(contentsOf: protoConfigFile),
           let config = try? decoder.decode(ProtoRepositoryConfig.self, from: data) {
            return config
        }
        if fileManager.fileExists(atPath: userHomeProtoConfigFile.path),
           let data = try? Data(contentsOf: userHomeProtoConfigFile),
           let config = try? decoder.decode(ProtoRepositoryConfig.self, from: data) {
            return config
        }
        // 向后兼容旧格式 [ProtoImportPath]
        if fileManager.fileExists(atPath: protoConfigFile.path),
           let data = try? Data(contentsOf: protoConfigFile),
           let paths = try? decoder.decode([ProtoImportPath].self, from: data) {
            return ProtoRepositoryConfig(importPaths: paths)
        }
        return ProtoRepositoryConfig()
    }

    // MARK: - 预置默认演示数据

    public func createDefaultWorkspace() -> WorkspaceModel {
        // 1. 预置多环境配置
        let localEnv = EnvironmentModel(
            name: "Local Development",
            isDefault: true,
            variables: [
                VariableItem(key: "grpc_host", value: "127.0.0.1", notes: "本地 gRPC 宿主"),
                VariableItem(key: "grpc_port", value: "50051", notes: "标准 gRPC 端口"),
                VariableItem(key: "jwt_token", value: "dev-mock-bearer-token-xyz", isSecret: true, notes: "开发测试 JWT"),
                VariableItem(key: "user_id", value: "usr_{{$randomInt(1000, 9999)}}", notes: "用户标识")
            ]
        )

        let stagingEnv = EnvironmentModel(
            name: "Staging Cluster",
            isDefault: false,
            variables: [
                VariableItem(key: "grpc_host", value: "grpc-staging.internal.net"),
                VariableItem(key: "grpc_port", value: "443"),
                VariableItem(key: "jwt_token", value: "staging-secret-token", isSecret: true),
                VariableItem(key: "user_id", value: "usr_staging_001")
            ]
        )

        let prodEnv = EnvironmentModel(
            name: "Production (Protected)",
            isDefault: false,
            variables: [
                VariableItem(key: "grpc_host", value: "grpc.production.company.com"),
                VariableItem(key: "grpc_port", value: "443"),
                VariableItem(key: "jwt_token", value: "prod-high-privilege-token", isSecret: true),
                VariableItem(key: "user_id", value: "usr_prod_admin")
            ]
        )

        // 2. 预置示例请求
        let reqUnary = RequestModel(
            name: "SayHello (Unary)",
            address: "{{grpc_host}}:{{grpc_port}}",
            serviceName: "helloworld.Greeter",
            methodName: "SayHello",
            callType: .unary,
            payload: "{\n  \"name\": \"Pulsar Native User ({{user_id}})\",\n  \"trace_id\": \"{{$uuid}}\"\n}",
            metadata: [
                MetadataHeader(key: "x-client-platform", value: "macOS-Pulsar-Native", isEnabled: true),
                MetadataHeader(key: "x-trace-id", value: "{{$uuid}}", isEnabled: true)
            ],
            auth: AuthConfig(type: .bearer, bearerToken: "{{jwt_token}}")
        )

        let reqServerStream = RequestModel(
            name: "ListFeatures (Server Streaming)",
            address: "{{grpc_host}}:{{grpc_port}}",
            serviceName: "routeguide.RouteGuide",
            methodName: "ListFeatures",
            callType: .serverStreaming,
            payload: "{\n  \"lo\": {\"latitude\": 400000000, \"longitude\": -750000000},\n  \"hi\": {\"latitude\": 420000000, \"longitude\": -730000000}\n}"
        )

        let reqBidiStream = RequestModel(
            name: "RouteChat (Bidi Streaming)",
            address: "{{grpc_host}}:{{grpc_port}}",
            serviceName: "routeguide.RouteGuide",
            methodName: "RouteChat",
            callType: .bidiStreaming,
            payload: "{\n  \"location\": {\"latitude\": 407838351, \"longitude\": -739653527},\n  \"message\": \"Hello from Pulsar Native at {{$timestamp}}!\"\n}"
        )

        let reqNacos = RequestModel(
            name: "Nacos 微服务注册中心示例",
            address: "nacos://127.0.0.1:8848/public/order-service?groupName=DEFAULT_GROUP",
            serviceName: "orders.OrderService",
            methodName: "GetOrderDetails",
            callType: .unary,
            payload: "{\n  \"order_id\": \"ord_{{$randomInt(10000, 99999)}}\"\n}",
            discovery: ServiceDiscoveryConfig(
                scheme: .nacos,
                nacosClusters: "127.0.0.1:8848",
                nacosNamespace: "public",
                nacosServiceName: "order-service"
            )
        )

        let demoCollection = CollectionModel(
            name: "gRPC 官方用例与微服务示例",
            notes: "包含经典 Unary, Server Streaming, Bidi Streaming 以及 Nacos 微服务注册中心的测试用例。",
            requests: [reqUnary, reqServerStream, reqBidiStream, reqNacos]
        )

        return WorkspaceModel(
            name: "Pulsar 核心工作空间",
            collections: [demoCollection],
            environments: [localEnv, stagingEnv, prodEnv],
            activeEnvironmentId: localEnv.id,
            globalVariables: [
                VariableItem(key: "app_version", value: "2.0.0-native", notes: "Pulsar 原生版本")
            ]
        )
    }
}
