import Foundation

/// 本地 Proto 仓库与扩展插件管理中心 (支持多级目录 Import Path 搜索与引用解析)
public final class ProtoRepository: ObservableObject {
    public static let shared = ProtoRepository()

    /// 配置的所有 Proto 包含搜索路径 (等同于 protoc 的 -I / --proto_path 参数)
    @Published public var importPaths: [ProtoImportPath] = []

    /// 已加载的本地 .proto 文件列表
    @Published public var loadedFiles: [LocalProtoFile] = []

    /// 扩展插件钩子规则
    @Published public var extensionPlugins: [ProtoExtensionPlugin] = []

    /// 独立导入的文件绝对路径集合
    @Published public var standaloneFiles: [String] = []

    private let parser = LocalProtoParser.shared
    private let fileManager = FileManager.default

    public init() {
        self.extensionPlugins = createDefaultExtensionPlugins()
        loadSampleProtoFiles()
        loadPersistedConfig()
    }

    // MARK: - 持久化存储与恢复

    public func saveConfig() {
        let config = ProtoRepositoryConfig(importPaths: self.importPaths, standaloneFiles: self.standaloneFiles)
        StorageManager.shared.saveProtoConfig(config)
    }

    public func loadPersistedConfig() {
        let config = StorageManager.shared.loadProtoConfig()
        var hasChanges = false
        for item in config.importPaths {
            if !importPaths.contains(where: { $0.path == item.path }) {
                importPaths.append(item)
                if item.isEnabled && fileManager.fileExists(atPath: item.path) {
                    scanDirectory(item.path)
                }
                hasChanges = true
            }
        }
        for file in config.standaloneFiles {
            if !self.standaloneFiles.contains(file) {
                self.standaloneFiles.append(file)
                if fileManager.fileExists(atPath: file), let parsed = try? parser.parseFile(at: file) {
                    loadedFiles.removeAll { $0.filePath == file }
                    loadedFiles.append(parsed)
                    hasChanges = true
                }
            }
        }
        if hasChanges {
            resolveAllImports()
        }
    }

    // MARK: - Import Paths (包含搜索路径管理 -I)

    /// 添加一个 Import Path 搜索目录 (对应 protoc -I)
    public func addImportPath(path: String) {
        let clean = (path as NSString).standardizingPath
        guard !importPaths.contains(where: { $0.path == clean }) else { return }

        let item = ProtoImportPath(path: clean, isEnabled: true)
        importPaths.append(item)

        // 递归扫描并载入该 Import Path 下的所有 proto 文件
        scanDirectory(clean)
        resolveAllImports()
        saveConfig()
    }

    /// 移除 Import Path
    public func removeImportPath(id: UUID) {
        if let item = importPaths.first(where: { $0.id == id }) {
            importPaths.removeAll { $0.id == id }
            loadedFiles.removeAll { $0.filePath.hasPrefix(item.path) }
            resolveAllImports()
            saveConfig()
        }
    }

    /// 启用/停用特定 Import Path
    public func toggleImportPath(id: UUID) {
        if let index = importPaths.firstIndex(where: { $0.id == id }) {
            importPaths[index].isEnabled.toggle()
            resolveAllImports()
            saveConfig()
        }
    }

    // MARK: - 目录与文件导入

    /// 添加本地 Proto 根目录并递归扫描导入 (自动作为 Import Path 加入)
    public func addProtoDirectory(path: String) {
        addImportPath(path: path)
    }

    /// 移除已加载的根目录
    public func removeProtoDirectory(path: String) {
        let clean = (path as NSString).standardizingPath
        importPaths.removeAll { $0.path == clean }
        loadedFiles.removeAll { $0.filePath.hasPrefix(clean) }
        resolveAllImports()
        saveConfig()
    }

    /// 添加单个 .proto 文件
    public func addProtoFile(path: String) {
        do {
            var file = try parser.parseFile(at: path)

            // 如果该文件所在父级目录尚未在 Import Path 中，自动推导建议包含目录
            let parentDir = (path as NSString).deletingLastPathComponent
            if !importPaths.contains(where: { $0.path == parentDir }) {
                importPaths.append(ProtoImportPath(path: parentDir, isEnabled: true))
            }

            if !standaloneFiles.contains(path) {
                standaloneFiles.append(path)
            }

            file.resolvedImports = resolveImports(for: file)
            loadedFiles.removeAll { $0.filePath == path }
            loadedFiles.append(file)
            resolveAllImports()
            saveConfig()
        } catch {
            print("Failed to parse proto at \(path): \(error)")
        }
    }


    /// 重新扫描所有已配置的 Proto 根目录并重新解析全部 Import 引用
    public func reloadAll() {
        var currentFiles: [LocalProtoFile] = []
        for rootItem in importPaths where rootItem.isEnabled {
            let root = rootItem.path
            if let enumerator = fileManager.enumerator(atPath: root) {
                for case let relPath as String in enumerator {
                    if relPath.hasSuffix(".proto") {
                        let fullPath = (root as NSString).appendingPathComponent(relPath)
                        if let file = try? parser.parseFile(at: fullPath) {
                            currentFiles.append(file)
                        }
                    }
                }
            }
        }
        self.loadedFiles = currentFiles
        resolveAllImports()
    }

    private func scanDirectory(_ dir: String) {
        guard let enumerator = fileManager.enumerator(atPath: dir) else { return }
        for case let relPath as String in enumerator {
            if relPath.hasSuffix(".proto") {
                let fullPath = (dir as NSString).appendingPathComponent(relPath)
                if let file = try? parser.parseFile(at: fullPath) {
                    loadedFiles.removeAll { $0.filePath == fullPath }
                    loadedFiles.append(file)
                }
            }
        }
    }

    // MARK: - 跨文件 Import 引用与多级目录定位

    /// 解析指定文件中的所有 import 语句在多级 Import Paths 中的确切物理位置
    public func resolveImports(for file: LocalProtoFile) -> [ResolvedImport] {
        var results: [ResolvedImport] = []
        for rawImport in file.imports {
            let (resolvedPath, ok) = resolveSingleImport(rawImport: rawImport, fromFilePath: file.filePath)
            results.append(ResolvedImport(rawImport: rawImport, resolvedPath: resolvedPath, isResolved: ok))

            // 如果成功定位到尚未加载的本地物理文件，自动解析并加载进内存
            if let realPath = resolvedPath,
               !realPath.starts(with: "builtin://"),
               !loadedFiles.contains(where: { $0.filePath == realPath }) {
                if let importedFile = try? parser.parseFile(at: realPath) {
                    loadedFiles.append(importedFile)
                }
            }
        }
        return results
    }

    /// 重新解析全部加载文件的 Import 状态
    public func resolveAllImports() {
        for i in 0..<loadedFiles.count {
            loadedFiles[i].resolvedImports = resolveImports(for: loadedFiles[i])
        }
    }

    /// 依据多级目录搜索规范定位 import 文件：
    /// 1. 首先尝试当前文件所在目录: relative(fileDir, importPath)
    /// 2. 依次遍历每个启用的 Import Path (-I): root + "/" + importPath
    /// 3. 匹配 Google Well-Known Types (如 google/protobuf/timestamp.proto, google/api/annotations.proto)
    public func resolveSingleImport(rawImport: String, fromFilePath: String) -> (path: String?, isResolved: Bool) {
        // 1. 尝试当前文件同级目录
        if !fromFilePath.isEmpty && !fromFilePath.starts(with: "/bundled") {
            let parentDir = (fromFilePath as NSString).deletingLastPathComponent
            let candidate = (parentDir as NSString).appendingPathComponent(rawImport)
            if fileManager.fileExists(atPath: candidate) {
                return (candidate, true)
            }
        }

        // 2. 依次在各 Import Path (-I) 下检索
        for importPath in importPaths where importPath.isEnabled {
            let candidate = (importPath.path as NSString).appendingPathComponent(rawImport)
            if fileManager.fileExists(atPath: candidate) {
                return (candidate, true)
            }
        }

        // 3. 检查内置 Google 官方协议库
        if isGoogleWellKnown(rawImport) {
            return ("builtin://\(rawImport)", true)
        }

        return (nil, false)
    }

    private func isGoogleWellKnown(_ raw: String) -> Bool {
        raw.starts(with: "google/protobuf/") ||
        raw.starts(with: "google/api/") ||
        raw.starts(with: "google/rpc/")
    }

    // MARK: - 查询与跨文件类型反解

    public var allServices: [ProtoServiceDescriptor] {
        loadedFiles.flatMap { $0.services }
    }

    public func findMethod(by fullName: String) -> ProtoMethodDescriptor? {
        for file in loadedFiles {
            for svc in file.services {
                if let m = svc.methods.first(where: { $0.fullName == fullName }) {
                    return m
                }
            }
        }
        return nil
    }

    /// 跨文件解析 Message 结构 (支持短名 User、包全名 ecommerce.orders.User、以及跨 import 嵌套引用)
    public func findMessage(by name: String, preferringFile: LocalProtoFile? = nil) -> ProtoMessageDescriptor? {
        // 1. 首选当前文件内部声明
        if let file = preferringFile {
            if let msg = file.messages.first(where: { $0.name == name || $0.fullName == name }) {
                return msg
            }
        }

        // 2. 在当前文件直接引用的已解析 import 文件中查找
        if let file = preferringFile {
            for imp in file.resolvedImports where imp.isResolved {
                if let realPath = imp.resolvedPath,
                   let importedFile = loadedFiles.first(where: { $0.filePath == realPath }) {
                    if let msg = importedFile.messages.first(where: { $0.name == name || $0.fullName == name || $0.fullName.hasSuffix(".\(name)") }) {
                        return msg
                    }
                }
            }
        }

        // 3. 全局搜索
        for file in loadedFiles {
            if let msg = file.messages.first(where: { $0.name == name || $0.fullName == name || $0.fullName.hasSuffix(".\(name)") }) {
                return msg
            }
        }
        return nil
    }

    // MARK: - 扩展插件 (Proto Extension Plugins) 处理

    /// 针对特定方法执行扩展插件钩子，自动补全请求头、认证或 Mock 载荷
    public func applyExtensions(to request: inout RequestModel, method: ProtoMethodDescriptor) {
        for plugin in extensionPlugins where plugin.isEnabled {
            if let opt = method.options.first(where: { $0.name.contains(plugin.targetOptionName) }) {
                switch plugin.actionType {
                case .injectHeader:
                    if !plugin.injectHeaderKey.isEmpty {
                        let headerKey = plugin.injectHeaderKey
                        let headerVal = plugin.injectHeaderValue.isEmpty ? opt.value : plugin.injectHeaderValue
                        if !request.metadata.contains(where: { $0.key.lowercased() == headerKey.lowercased() }) {
                            request.metadata.append(MetadataHeader(key: headerKey, value: headerVal))
                        }
                    }
                case .requireAuth:
                    if request.auth.type == .none || request.auth.type == .inherit {
                        request.auth.type = .bearer
                        request.auth.bearerToken = "{{jwt_token}}"
                    }
                case .showBadge, .formatPrompt:
                    break
                }
            }
        }
    }

    // MARK: - 默认扩展插件与演示 Proto

    private func createDefaultExtensionPlugins() -> [ProtoExtensionPlugin] {
        [
            ProtoExtensionPlugin(
                name: "Google HTTP Transcoding (gRPC-Gateway)",
                isEnabled: true,
                targetOptionName: "google.api.http",
                actionType: .showBadge,
                notes: "自动识别 (google.api.http) 选项并展示 RESTful 映射路径"
            ),
            ProtoExtensionPlugin(
                name: "Auth Guard (require_auth 自动注入)",
                isEnabled: true,
                targetOptionName: "require_auth",
                actionType: .requireAuth,
                notes: "如果 RPC 注解包含 require_auth = true，自动激活 Bearer 凭据"
            ),
            ProtoExtensionPlugin(
                name: "Custom Trace Header 注入",
                isEnabled: true,
                targetOptionName: "trace",
                actionType: .injectHeader,
                injectHeaderKey: "x-proto-trace-id",
                injectHeaderValue: "{{$uuid}}",
                notes: "如果方法包含 (trace) 选项，自动注入分布式链路 Trace ID"
            )
        ]
    }

    private func loadSampleProtoFiles() {
        let sampleGreeterProto = """
        syntax = "proto3";

        package helloworld;

        option go_package = "google.golang.org/grpc/examples/helloworld/helloworld";
        option java_package = "io.grpc.examples.helloworld";

        // Extend 扩展定义：支持为方法添加自定义权限与安全等级
        extend google.protobuf.MethodOptions {
            bool require_auth = 50001;
            string custom_route = 50002;
        }

        service Greeter {
            rpc SayHello (HelloRequest) returns (HelloReply) {
                option (require_auth) = true;
                option (custom_route) = "/v1/greeter/say_hello";
            }
            rpc SayHelloStream (HelloRequest) returns (stream HelloReply);
        }

        message HelloRequest {
            string name = 1;
            string client_id = 2;
        }

        message HelloReply {
            string message = 1;
            int64 timestamp = 2;
        }
        """

        let sampleOrderProto = """
        syntax = "proto3";

        package ecommerce.orders;

        import "google/api/annotations.proto";

        service OrderService {
            rpc CreateOrder (CreateOrderRequest) returns (OrderResponse) {
                option (google.api.http) = {
                    post: "/v1/orders"
                    body: "*"
                };
                option (require_auth) = true;
            }

            rpc WatchOrders (stream OrderFilter) returns (stream OrderEvent);
        }

        message CreateOrderRequest {
            string user_id = 1;
            repeated OrderItem items = 2;
            double total_amount = 3;
        }

        message OrderItem {
            string product_id = 1;
            int32 quantity = 2;
            double unit_price = 3;
        }

        message OrderResponse {
            string order_id = 1;
            string status = 2;
            int64 created_at = 3;
        }

        message OrderFilter {
            string user_id = 1;
        }

        message OrderEvent {
            string order_id = 1;
            string event_type = 2;
        }
        """

        var greeterFile = parser.parseString(sampleGreeterProto, filePath: "/bundled/helloworld.proto", fileName: "helloworld.proto")
        var orderFile = parser.parseString(sampleOrderProto, filePath: "/bundled/orders.proto", fileName: "orders.proto")

        greeterFile.resolvedImports = resolveImports(for: greeterFile)
        orderFile.resolvedImports = resolveImports(for: orderFile)

        self.loadedFiles = [greeterFile, orderFile]
    }
}
