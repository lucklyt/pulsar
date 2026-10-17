import Foundation

/// 存储管理器：负责将工作空间、集合、环境和历史记录持久化为结构化 JSON 文件
public final class StorageManager {
    public static let shared = StorageManager()

    private let fileManager = FileManager.default
    private let appSupportDir: URL

    public init() {
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pulsarDir = baseDir.appendingPathComponent("Pulsar", isDirectory: true)
        let oldDir = baseDir.appendingPathComponent("WombatNative", isDirectory: true)

        // 如果存在旧版 WombatNative 目录且新目录不存在，则优雅迁移
        if fileManager.fileExists(atPath: oldDir.path) && !fileManager.fileExists(atPath: pulsarDir.path) {
            try? fileManager.copyItem(at: oldDir, to: pulsarDir)
        } else {
            try? fileManager.createDirectory(at: pulsarDir, withIntermediateDirectories: true)
        }
        self.appSupportDir = pulsarDir
    }

    private var workspaceFile: URL {
        appSupportDir.appendingPathComponent("workspace.json")
    }

    private var historyFile: URL {
        appSupportDir.appendingPathComponent("history.json")
    }

    // MARK: - Workspace 保存与加载

    public func saveWorkspace(_ workspace: WorkspaceModel) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)
        try data.write(to: workspaceFile, options: .atomic)
    }

    public func loadWorkspace() -> WorkspaceModel {
        guard fileManager.fileExists(atPath: workspaceFile.path),
              let data = try? Data(contentsOf: workspaceFile),
              var model = try? JSONDecoder().decode(WorkspaceModel.self, from: data) else {
            // 首次启动，生成具有丰富演示用例与环境配置的初始工作空间
            let initial = createDefaultWorkspace()
            try? saveWorkspace(initial)
            return initial
        }

        // 如果现有工作空间尚未包含任何文件夹，自动提供一个流式接口示例文件夹以供体验折叠
        if let firstColIndex = model.collections.firstIndex(where: { $0.folders.isEmpty && $0.requests.count >= 2 }) {
            let colId = model.collections[firstColIndex].id
            let folderId = UUID()
            var folder = FolderModel(id: folderId, name: "Streaming APIs (流式接口)", collectionId: colId)

            for i in 0..<model.collections[firstColIndex].requests.count {
                if model.collections[firstColIndex].requests[i].callType != .unary {
                    model.collections[firstColIndex].requests[i].folderId = folderId
                    folder.requestIds.append(model.collections[firstColIndex].requests[i].id)
                }
            }
            if !folder.requestIds.isEmpty {
                model.collections[firstColIndex].folders.append(folder)
                try? saveWorkspace(model)
            }
        }

        return model
    }

    // MARK: - History 保存与加载

    public func saveHistory(_ responses: [RPCResponse]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(responses) {
            try? data.write(to: historyFile, options: .atomic)
        }
    }

    public func loadHistory() -> [RPCResponse] {
        guard fileManager.fileExists(atPath: historyFile.path),
              let data = try? Data(contentsOf: historyFile),
              let list = try? JSONDecoder().decode([RPCResponse].self, from: data) else {
            return []
        }
        return list
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
            name: "SayHello (一问一答)",
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
            name: "ListFeatures (服务端流)",
            address: "{{grpc_host}}:{{grpc_port}}",
            serviceName: "routeguide.RouteGuide",
            methodName: "ListFeatures",
            callType: .serverStreaming,
            payload: "{\n  \"lo\": {\"latitude\": 400000000, \"longitude\": -750000000},\n  \"hi\": {\"latitude\": 420000000, \"longitude\": -730000000}\n}"
        )

        let reqBidiStream = RequestModel(
            name: "RouteChat (全双工双向流)",
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
