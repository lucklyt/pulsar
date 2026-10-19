import XCTest
@testable import PulsarCore

final class PulsarTests: XCTestCase {

    // MARK: - 1. EnvironmentEngine 测试

    func testVariableInterpolation() {
        let env = EnvironmentModel(
            name: "TestEnv",
            variables: [
                VariableItem(key: "host", value: "10.0.0.1"),
                VariableItem(key: "port", value: "9090"),
                VariableItem(key: "token", value: "secret123", isSecret: true)
            ]
        )

        let engine = EnvironmentEngine.shared
        let template = "{{host}}:{{port}}/rpc"
        let resolved = engine.resolve(template: template, environment: env)

        XCTAssertEqual(resolved, "10.0.0.1:9090/rpc")
    }

    func testDynamicBuiltinVariables() {
        let engine = EnvironmentEngine.shared

        let uuidTemplate = "req_{{$uuid}}"
        let resolvedUUID = engine.resolve(template: uuidTemplate)
        XCTAssertTrue(resolvedUUID.starts(with: "req_"))
        XCTAssertEqual(resolvedUUID.count, 4 + 36)

        let tsTemplate = "{{$timestamp}}"
        let resolvedTS = engine.resolve(template: tsTemplate)
        XCTAssertNotNil(Int(resolvedTS))

        let randTemplate = "{{$randomInt(100, 200)}}"
        let resolvedRand = engine.resolve(template: randTemplate)
        if let val = Int(resolvedRand) {
            XCTAssertTrue(val >= 100 && val <= 200)
        } else {
            XCTFail("Failed to generate random int")
        }
    }

    func testVariableExtraction() {
        let engine = EnvironmentEngine.shared
        let template = "nacos://{{nacos_host}}:{{nacos_port}}/{{namespace}}/{{service}}"
        let extracted = engine.extractReferencedVariables(from: template)

        XCTAssertEqual(extracted, ["nacos_host", "nacos_port", "namespace", "service"])
    }

    // MARK: - 2. GrpcurlExporter 测试

    func testGrpcurlExport() {
        let req = RequestModel(
            name: "Test SayHello",
            address: "127.0.0.1:50051",
            serviceName: "helloworld.Greeter",
            methodName: "SayHello",
            callType: .unary,
            payload: "{\"name\": \"Alice\"}",
            metadata: [MetadataHeader(key: "x-req-id", value: "12345")],
            auth: AuthConfig(type: .bearer, bearerToken: "test-token")
        )

        let cmd = GrpcurlExporter.shared.export(
            request: req,
            resolvedAddress: req.address,
            resolvedPayload: req.payload
        )

        XCTAssertTrue(cmd.contains("grpcurl"))
        XCTAssertTrue(cmd.contains("-plaintext"))
        XCTAssertTrue(cmd.contains("127.0.0.1:50051"))
        XCTAssertTrue(cmd.contains("helloworld.Greeter/SayHello"))
        XCTAssertTrue(cmd.contains("authorization: Bearer test-token"))
    }

    // MARK: - 3. MockJSONGenerator 测试

    func testMockJSONGenerator() {
        let desc = ProtoMessageDescriptor(
            name: "User",
            fullName: "demo.User",
            fields: [
                ProtoFieldDescriptor(name: "id", number: 1, kind: .string),
                ProtoFieldDescriptor(name: "age", number: 2, kind: .int32),
                ProtoFieldDescriptor(name: "active", number: 3, kind: .bool)
            ]
        )

        let json = MockJSONGenerator.shared.generateMockJSON(for: desc)
        XCTAssertTrue(json.contains("\"active\" : true") || json.contains("\"active\": true"))
        XCTAssertTrue(json.contains("\"age\" : 0") || json.contains("\"age\": 0"))
        XCTAssertTrue(json.contains("\"id\" : \"sample_id\"") || json.contains("\"id\": \"sample_id\""))
    }

    // MARK: - 5. LocalProtoParser 与 Proto 扩展测试

    func testLocalProtoParser() {
        let protoText = """
        syntax = "proto3";
        package my.billing;

        import "google/api/annotations.proto";

        extend google.protobuf.MethodOptions {
            bool require_auth = 50001;
        }

        service BillingService {
            // Charge credit card
            rpc Charge (ChargeRequest) returns (ChargeResponse) {
                option (google.api.http) = {
                    post: "/v1/charges"
                };
                option (require_auth) = true;
            }
        }

        message ChargeRequest {
            string customer_id = 1 [(validate.rules).string.min_len = 1];
            int64 amount = 2;
        }

        message ChargeResponse {
            string charge_id = 1;
            bool success = 2;
        }
        """

        let file = LocalProtoParser.shared.parseString(protoText, fileName: "billing.proto")
        XCTAssertEqual(file.packageName, "my.billing")
        XCTAssertEqual(file.syntax, "proto3")
        XCTAssertEqual(file.imports, ["google/api/annotations.proto"])

        // 验证 extend 扩展定义
        XCTAssertEqual(file.extensionDefs.count, 1)
        XCTAssertEqual(file.extensionDefs.first?.fieldName, "require_auth")
        XCTAssertEqual(file.extensionDefs.first?.fieldNumber, 50001)

        // 验证 service 与 rpc 扩展选项
        XCTAssertEqual(file.services.count, 1)
        let svc = file.services.first!
        XCTAssertEqual(svc.name, "BillingService")
        XCTAssertEqual(svc.methods.count, 1)

        let method = svc.methods.first!
        XCTAssertEqual(method.name, "Charge")
        XCTAssertEqual(method.options.count, 2)
        XCTAssertNotNil(method.httpOption)
        XCTAssertTrue(method.isAuthRequired)

        // 验证 message 与字段 options
        XCTAssertEqual(file.messages.count, 2)
        let chargeReq = file.messages.first { $0.name == "ChargeRequest" }
        XCTAssertNotNil(chargeReq)
        let custIdField = chargeReq?.fields.first { $0.name == "customer_id" }
        XCTAssertNotNil(custIdField)
        XCTAssertFalse(custIdField!.options.isEmpty)
    }

    func testProtoExtensionPluginApplication() {
        let method = ProtoMethodDescriptor(
            name: "SecureMethod",
            fullName: "demo.Service/SecureMethod",
            serviceName: "demo.Service",
            inputMessage: ProtoMessageDescriptor(name: "Req", fullName: "Req"),
            outputMessage: ProtoMessageDescriptor(name: "Resp", fullName: "Resp"),
            options: [
                ProtoOption(name: "(require_auth)", value: "true", isExtension: true),
                ProtoOption(name: "(trace)", value: "true", isExtension: true)
            ]
        )

        var req = RequestModel(name: "Test Secure")
        XCTAssertEqual(req.auth.type, .inherit)

        ProtoRepository.shared.applyExtensions(to: &req, method: method)

        // 验证扩展插件是否按注解自动生效
        XCTAssertEqual(req.auth.type, .bearer)
        XCTAssertTrue(req.metadata.contains(where: { $0.key == "x-proto-trace-id" }))
    }

    // MARK: - 6. 多级目录 Import Paths (-I) 依赖定位测试

    func testMultiLevelImportPathResolution() throws {
        let fileManager = FileManager.default
        let baseDir = "/tmp/test_pulsar_import_\(UUID().uuidString.prefix(8))"
        let protoRootDir = "\(baseDir)/proto"
        let commonDir = "\(protoRootDir)/common/v1"
        let orderDir = "\(protoRootDir)/order/v1"

        try fileManager.createDirectory(atPath: commonDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: orderDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(atPath: baseDir)
        }

        // 创建被引用的公共 Proto: common/v1/types.proto
        let commonProto = """
        syntax = "proto3";
        package common.v1;

        message Pagination {
            int32 page = 1;
            int32 page_size = 2;
        }
        """
        try commonProto.write(toFile: "\(commonDir)/types.proto", atomically: true, encoding: .utf8)

        // 创建依赖方 Proto: order/v1/order.proto (包含多级相对引用 import "common/v1/types.proto")
        let orderProto = """
        syntax = "proto3";
        package order.v1;

        import "common/v1/types.proto";

        service OrderService {
            rpc ListOrders (ListOrdersRequest) returns (ListOrdersResponse);
        }

        message ListOrdersRequest {
            string customer_id = 1;
            common.v1.Pagination pagination = 2;
        }

        message ListOrdersResponse {
            int32 total = 1;
        }
        """
        let orderFilePath = "\(orderDir)/order.proto"
        try orderProto.write(toFile: orderFilePath, atomically: true, encoding: .utf8)

        let repo = ProtoRepository()

        // 1. 未配置 Import Path 时，单独解析 order.proto，由于其同级目录下没有 common/v1/types.proto，无法基于当前文件目录解析
        let unlinkedFile = LocalProtoParser.shared.parseString(orderProto, filePath: orderFilePath, fileName: "order.proto")
        let unresolvedImports = repo.resolveImports(for: unlinkedFile)
        XCTAssertFalse(unresolvedImports.first?.isResolved ?? true, "未配置 Import Path 前不应被解析")

        // 2. 添加 Import Path: protoRootDir (-I /tmp/.../proto)
        repo.addImportPath(path: protoRootDir)
        XCTAssertTrue(repo.importPaths.contains(where: { $0.path == protoRootDir }))

        // 3. 再次解析 order.proto，应当成功定位到 common/v1/types.proto 的实际物理路径
        let resolvedFile = repo.resolveImports(for: unlinkedFile)
        XCTAssertTrue(resolvedFile.first?.isResolved ?? false, "配置 Import Path 后应成功定位多级目录下的依赖")
        XCTAssertEqual(resolvedFile.first?.resolvedPath, "\(commonDir)/types.proto")

        // 4. 验证跨文件 Message 反解
        let foundMsg = repo.findMessage(by: "Pagination")
        XCTAssertNotNil(foundMsg, "应跨 Import 文件查找到 Pagination 结构体")
        XCTAssertEqual(foundMsg?.name, "Pagination")
    }

    // MARK: - 7. Bruno 风格层级继承与合并测试 (Hierarchical Configuration & Inheritance)

    func testHierarchicalInheritanceResolution() {
        let appState = AppState()

        let colId = UUID()
        let foldId = UUID()
        let reqId = UUID()

        var collection = CollectionModel(id: colId, name: "Core Services")
        collection.sharedMetadata = [
            MetadataHeader(key: "x-collection-id", value: "col-123"),
            MetadataHeader(key: "x-app-env", value: "global-default")
        ]
        collection.auth = AuthConfig(type: .bearer, bearerToken: "collection-level-jwt")
        collection.security = TLSConfig(mode: .tlsSystem)
        collection.timeoutSeconds = 45.0

        var folder = FolderModel(id: foldId, name: "User Module", collectionId: colId)
        folder.sharedMetadata = [
            MetadataHeader(key: "x-folder-id", value: "fold-456"),
            MetadataHeader(key: "x-app-env", value: "folder-override") // 覆盖集合同名 Header
        ]
        folder.auth = AuthConfig(type: .apiKey, apiKeyName: "x-api-key", apiKeyValue: "folder-secret-key")

        var request = RequestModel(
            id: reqId,
            name: "GetUserProfile",
            collectionId: colId,
            folderId: foldId
        )
        request.auth = AuthConfig(type: .inherit) // 声明继承
        request.tls = TLSConfig(mode: .inherit)
        request.metadata = [
            MetadataHeader(key: "x-request-id", value: "req-789"),
            MetadataHeader(key: "x-app-env", value: "request-override") // 最终覆盖
        ]

        collection.folders = [folder]
        collection.requests = [request]
        appState.workspace.collections = [collection]

        let effective = appState.resolveEffectiveConfig(for: request)

        // 验证 Auth 继承: Request 继承自 Folder
        XCTAssertEqual(effective.effectiveAuth.type, .apiKey)
        XCTAssertEqual(effective.effectiveAuth.apiKeyValue, "folder-secret-key")
        XCTAssertTrue(effective.authSource.contains("User Module"))

        // 验证 TLS 继承: Request 继承自 Collection
        XCTAssertEqual(effective.effectiveRequest.tls.mode, .tlsSystem)
        XCTAssertTrue(effective.securitySource.contains("Core Services"))

        // 验证 Metadata 继承与逐级覆盖: x-app-env 应取 request-override
        let effectiveHeaders = effective.effectiveRequest.metadata
        let envHeader = effectiveHeaders.first { $0.key.lowercased() == "x-app-env" }
        XCTAssertEqual(envHeader?.value, "request-override")

        // 验证集合与文件夹的专属 Header 是否均合并入请求头
        XCTAssertTrue(effectiveHeaders.contains { $0.key == "x-collection-id" && $0.value == "col-123" })
        XCTAssertTrue(effectiveHeaders.contains { $0.key == "x-folder-id" && $0.value == "fold-456" })
        XCTAssertTrue(effectiveHeaders.contains { $0.key == "x-request-id" && $0.value == "req-789" })
    }

    // MARK: - 8. Bruno 风格 Git 友好型目录导出与导入测试

    func testCollectionDirectoryExportAndImport() throws {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pulsar_test_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        var collection = CollectionModel(name: "Payment Gateway")
        collection.sharedMetadata = [MetadataHeader(key: "x-merchant-id", value: "m_999")]
        collection.auth = AuthConfig(type: .bearer, bearerToken: "test_token_xyz")

        let folder = FolderModel(name: "Refunds", collectionId: collection.id)
        let req1 = RequestModel(name: "InitiateRefund", collectionId: collection.id, folderId: folder.id)
        let req2 = RequestModel(name: "QueryStatus", collectionId: collection.id, folderId: nil)

        collection.folders = [folder]
        collection.requests = [req1, req2]

        let env = EnvironmentModel(name: "Sandbox", variables: [VariableItem(key: "api_url", value: "https://sandbox.api")])

        // 1. 导出为目录结构
        let exportedDir = try CollectionDirectorySyncService.shared.exportCollection(
            collection,
            environments: [env],
            to: tempDir
        )

        XCTAssertTrue(fileManager.fileExists(atPath: exportedDir.appendingPathComponent("collection.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: exportedDir.appendingPathComponent("Refunds/folder.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: exportedDir.appendingPathComponent("Refunds/InitiateRefund.grpc.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: exportedDir.appendingPathComponent("QueryStatus.grpc.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: exportedDir.appendingPathComponent("environments/Sandbox.json").path))

        // 2. 从目录结构反向导入
        let (importedCol, importedEnvs) = try CollectionDirectorySyncService.shared.importCollection(from: exportedDir)

        XCTAssertEqual(importedCol.name, "Payment Gateway")
        XCTAssertEqual(importedCol.sharedMetadata.first?.key, "x-merchant-id")
        XCTAssertEqual(importedCol.auth.bearerToken, "test_token_xyz")
        XCTAssertEqual(importedCol.folders.count, 1)
        XCTAssertEqual(importedCol.folders.first?.name, "Refunds")
        XCTAssertEqual(importedCol.requests.count, 2)
        XCTAssertEqual(importedEnvs.first?.name, "Sandbox")
    }

    // MARK: - 9. 变量诊断引擎未解析变量侦测测试

    func testUnresolvedVariablesDetection() {
        let env = EnvironmentModel(
            name: "Dev",
            variables: [
                VariableItem(key: "valid_host", value: "10.0.0.1"),
                VariableItem(key: "valid_token", value: "abc")
            ]
        )

        let payload = """
        {
          "host": "{{valid_host}}",
          "missing": "{{unresolved_account_id}}",
          "uuid": "{{$uuid}}",
          "another_missing": "{{not_found_var}}"
        }
        """

        let missingVars = EnvironmentEngine.shared.findUnresolvedVariables(
            in: payload,
            environment: env,
            globalVariables: []
        )

        XCTAssertEqual(Set(missingVars), Set(["unresolved_account_id", "not_found_var"]))
    }

    // MARK: - 10. GRPCClientEngine 调用引擎全流程测试 (Unary, Streaming, Nacos)

    func testGRPCClientEngineUnaryExecution() async {
        let engine = GRPCClientEngine.shared
        let env = EnvironmentModel(
            name: "DevEnv",
            variables: [
                VariableItem(key: "host", value: "127.0.0.1"),
                VariableItem(key: "port", value: "50051"),
                VariableItem(key: "username", value: "Alice"),
                VariableItem(key: "jwt", value: "secret-token-123", isSecret: true)
            ]
        )

        let req = RequestModel(
            name: "Greeter SayHello",
            address: "{{host}}:{{port}}",
            serviceName: "helloworld.Greeter",
            methodName: "SayHello",
            callType: .unary,
            payload: "{\"name\": \"{{username}}\"}",
            metadata: [MetadataHeader(key: "x-client", value: "PulsarTest")],
            auth: AuthConfig(type: .bearer, bearerToken: "{{jwt}}")
        )

        let response = await engine.execute(
            request: req,
            activeEnvironment: env,
            globalVariables: []
        )

        XCTAssertEqual(response.statusCode, 0)
        XCTAssertEqual(response.statusName, "OK")
        XCTAssertTrue(response.responsePayload.contains("Hello from gRPC server"))
        XCTAssertTrue(response.responsePayload.contains("127.0.0.1:50051"))
        XCTAssertNotNil(response.stats)
        XCTAssertTrue((response.durationMs) > 0)
        XCTAssertEqual(response.initialMetadata["content-type"], "application/grpc+proto")
    }

    func testGRPCClientEngineStreamingExecution() async {
        let engine = GRPCClientEngine.shared

        // 1. 服务端流 (Server Streaming)
        let srvStreamReq = RequestModel(
            name: "ListFeatures",
            address: "127.0.0.1:50051",
            serviceName: "routeguide.RouteGuide",
            methodName: "ListFeatures",
            callType: .serverStreaming,
            payload: "{\"area\": \"box\"}"
        )

        var capturedServerEvents: [StreamEvent] = []
        let srvResponse = await engine.execute(
            request: srvStreamReq,
            activeEnvironment: nil,
            globalVariables: [],
            onStreamEvent: { event in
                capturedServerEvents.append(event)
            }
        )

        XCTAssertEqual(srvResponse.statusCode, 0)
        XCTAssertEqual(capturedServerEvents.count, 4) // 1 outbound + 3 inbound
        XCTAssertEqual(capturedServerEvents.first?.direction, .outbound)
        XCTAssertEqual(capturedServerEvents.filter { $0.direction == .inbound }.count, 3)
        XCTAssertEqual(srvResponse.streamEvents.count, 4)

        // 2. 客户端流 (Client Streaming)
        let cliStreamReq = RequestModel(
            name: "RecordRoute",
            address: "127.0.0.1:50051",
            serviceName: "routeguide.RouteGuide",
            methodName: "RecordRoute",
            callType: .clientStreaming,
            payload: "{\"point\": 1}"
        )

        var capturedClientEvents: [StreamEvent] = []
        let cliResponse = await engine.execute(
            request: cliStreamReq,
            activeEnvironment: nil,
            globalVariables: [],
            onStreamEvent: { event in
                capturedClientEvents.append(event)
            }
        )

        XCTAssertEqual(cliResponse.statusCode, 0)
        XCTAssertEqual(capturedClientEvents.count, 3) // chunk + half-close + aggregate response
        XCTAssertTrue(capturedClientEvents.contains { $0.isHalfClose })
        XCTAssertTrue(capturedClientEvents.contains { $0.direction == .inbound })

        // 3. 双向流 (Bidirectional Streaming)
        let bidiReq = RequestModel(
            name: "RouteChat",
            address: "127.0.0.1:50051",
            serviceName: "routeguide.RouteGuide",
            methodName: "RouteChat",
            callType: .bidiStreaming,
            payload: "{\"message\": \"ping\"}"
        )

        var capturedBidiEvents: [StreamEvent] = []
        let bidiResponse = await engine.execute(
            request: bidiReq,
            activeEnvironment: nil,
            globalVariables: [],
            onStreamEvent: { event in
                capturedBidiEvents.append(event)
            }
        )

        XCTAssertEqual(bidiResponse.statusCode, 0)
        XCTAssertEqual(capturedBidiEvents.count, 2) // 1 outbound + 1 inbound echo
        XCTAssertEqual(capturedBidiEvents[0].direction, .outbound)
        XCTAssertEqual(capturedBidiEvents[1].direction, .inbound)
    }

    func testGRPCClientEngineNacosErrorHandling() async {
        let engine = GRPCClientEngine.shared
        let req = RequestModel(
            name: "Unreachable Nacos Call",
            address: "nacos://invalid_address_without_slash",
            serviceName: "order.OrderService",
            methodName: "GetOrder",
            callType: .unary
        )

        let response = await engine.execute(
            request: req,
            activeEnvironment: nil,
            globalVariables: []
        )

        XCTAssertEqual(response.statusCode, 14) // UNAVAILABLE
        XCTAssertEqual(response.statusName, "UNAVAILABLE")
        XCTAssertNotNil(response.errorMessage)
        XCTAssertTrue(response.responsePayload.contains("Failed to resolve Nacos service"))
    }

    // MARK: - 11. NacosResolver 服务发现解析器测试

    func testNacosDirectAddressPassthrough() async throws {
        let directAddress = "127.0.0.1:50051"
        let resolved = try await NacosResolver.shared.resolve(address: directAddress)
        XCTAssertEqual(resolved, directAddress)
    }

    func testNacosInvalidAddressHandling() async {
        do {
            _ = try await NacosResolver.shared.resolve(address: "nacos://cluster_without_slash")
            XCTFail("Should throw error when format is invalid")
        } catch {
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.domain, "NacosResolver")
            XCTAssertEqual(nsErr.code, 400)
        }
    }

    func testNacosMockHTTPResolution() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockNacosURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let mockJSON = """
        {
            "hosts": [
                {
                    "ip": "10.0.10.99",
                    "port": 9099,
                    "healthy": true,
                    "enabled": true,
                    "weight": 1.0
                }
            ]
        }
        """
        MockNacosURLProtocol.mockData = mockJSON.data(using: .utf8)
        MockNacosURLProtocol.mockStatusCode = 200

        let resolver = NacosResolver(session: mockSession)
        let resolved = try await resolver.resolve(address: "nacos://127.0.0.1:8848/public/payment-service?groupName=PAY_GROUP")

        XCTAssertEqual(resolved, "10.0.10.99:9099")
    }

    // MARK: - 12. StorageManager 隔离持久化与向前兼容测试

    func testStorageManagerWorkspacePersistence() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("storage_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = StorageManager(appSupportDir: tempDir)

        var col = CollectionModel(name: "Order Processing")
        col.sharedMetadata = [MetadataHeader(key: "x-version", value: "v2")]
        let folder = FolderModel(name: "Checkout", collectionId: col.id)
        let req = RequestModel(name: "PayOrder", collectionId: col.id, folderId: folder.id)
        col.folders = [folder]
        col.requests = [req]

        let env = EnvironmentModel(
            name: "Production (Protected)",
            isDefault: false,
            colorHex: "#FF453A",
            isProduction: true,
            variables: [VariableItem(key: "env", value: "prod")]
        )

        let workspace = WorkspaceModel(
            name: "My Workspace",
            collections: [col],
            environments: [env],
            activeEnvironmentId: env.id,
            globalVariables: [VariableItem(key: "platform", value: "macOS")]
        )

        try storage.saveWorkspace(workspace)

        // 重新从磁盘读取加载
        let reloaded = storage.loadWorkspace()
        XCTAssertEqual(reloaded.collections.count, 1)
        XCTAssertEqual(reloaded.collections.first?.name, "Order Processing")
        XCTAssertEqual(reloaded.collections.first?.sharedMetadata.first?.key, "x-version")
        XCTAssertEqual(reloaded.environments.count, 1)
        XCTAssertEqual(reloaded.environments.first?.colorHex, "#FF453A")
        XCTAssertTrue(reloaded.environments.first?.isProduction ?? false)
        XCTAssertEqual(reloaded.globalVariables.first?.key, "platform")
    }

    func testStorageManagerHistoryPersistence() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("storage_hist_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = StorageManager(appSupportDir: tempDir)
        let response = RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: 12.5,
            responseSize: 1024,
            responsePayload: "{\"status\": \"persisted\"}"
        )

        storage.saveHistory([response])
        let reloaded = storage.loadHistory()

        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.statusCode, 0)
        XCTAssertEqual(reloaded.first?.responsePayload, "{\"status\": \"persisted\"}")
        XCTAssertEqual(reloaded.first?.durationMs, 12.5)
    }

    func testStorageManagerBackwardCompatibility() throws {
        // 验证旧版本缺少 colorHex, isProduction, sharedMetadata, auth 等新字段时的向前兼容性
        let legacyEnvironmentJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Production Cluster",
            "isDefault": false,
            "variables": []
        }
        """

        let envDecoder = JSONDecoder()
        let env = try envDecoder.decode(EnvironmentModel.self, from: legacyEnvironmentJSON.data(using: .utf8)!)

        XCTAssertEqual(env.name, "Production Cluster")
        // 应自动智能推断为生产环境并赋予专属高警示红色
        XCTAssertTrue(env.isProduction)
        XCTAssertEqual(env.colorHex, "#FF453A")

        let legacyFolderJSON = """
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "name": "Legacy Folder",
            "collectionId": "11111111-2222-3333-4444-555555555555",
            "requestIds": []
        }
        """

        let folder = try JSONDecoder().decode(FolderModel.self, from: legacyFolderJSON.data(using: .utf8)!)
        XCTAssertEqual(folder.name, "Legacy Folder")
        XCTAssertEqual(folder.auth.type, .inherit)
        XCTAssertTrue(folder.sharedMetadata.isEmpty)
    }

    // MARK: - 13. AppState 状态中枢业务与生命周期操作测试

    @MainActor
    func testAppStateTabAndCRUDLifecycle() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("appstate_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = StorageManager(appSupportDir: tempDir)
        let appState = AppState(storage: storage)

        // 1. 创建集合与文件夹
        appState.createNewCollection(name: "Commerce")
        guard let col = appState.workspace.collections.first(where: { $0.name == "Commerce" }) else {
            XCTFail("Failed to create collection")
            return
        }

        appState.createFolder(in: col.id, name: "Inventory")
        let folder = appState.workspace.collections.first(where: { $0.id == col.id })?.folders.first
        XCTAssertNotNil(folder)

        // 2. 创建请求
        appState.createNewRequest(in: col.id, folderId: folder?.id)
        let createdReq = appState.workspace.collections.first(where: { $0.id == col.id })?.requests.first
        XCTAssertNotNil(createdReq)
        XCTAssertEqual(appState.openTabIds.last, createdReq?.id)
        XCTAssertEqual(appState.activeTabId, createdReq?.id)

        // 3. 复制请求 (Duplicate)
        if let reqId = createdReq?.id {
            appState.duplicateRequest(id: reqId)
            let colAfterDup = appState.workspace.collections.first(where: { $0.id == col.id })
            XCTAssertEqual(colAfterDup?.requests.count, 2)
            XCTAssertTrue(colAfterDup?.requests.last?.name.contains("(Copy)") ?? false)
            XCTAssertEqual(appState.activeTabId, colAfterDup?.requests.last?.id)
        }

        // 4. Dirty 状态追踪与保存
        if let activeId = appState.activeTabId {
            appState.markDirty(id: activeId)
            XCTAssertTrue(appState.dirtyTabIds.contains(activeId))

            appState.saveActiveRequest()
            XCTAssertFalse(appState.dirtyTabIds.contains(activeId))
        }

        // 5. 搜索过滤 (Search Query Filter)
        appState.searchQuery = "Inventory"
        let filtered1 = appState.filteredRequests(in: appState.workspace.collections.first(where: { $0.id == col.id })!)
        // 请求名称为 "New gRPC Request"，不包含 "Inventory"
        XCTAssertTrue(filtered1.isEmpty)

        appState.searchQuery = "New gRPC"
        let filtered2 = appState.filteredRequests(in: appState.workspace.collections.first(where: { $0.id == col.id })!)
        XCTAssertFalse(filtered2.isEmpty)
        appState.searchQuery = ""

        // 6. 标签页关闭与删除
        if let dupReq = appState.workspace.collections.first(where: { $0.id == col.id })?.requests.last {
            appState.closeTab(id: dupReq.id)
            XCTAssertFalse(appState.openTabIds.contains(dupReq.id))
            XCTAssertNotEqual(appState.activeTabId, dupReq.id)

            appState.deleteRequest(id: dupReq.id)
            let remainingCount = appState.workspace.collections.first(where: { $0.id == col.id })?.requests.count
            XCTAssertEqual(remainingCount, 1)
        }

        // 7. 级联删除文件夹
        if let f = folder {
            appState.deleteFolder(id: f.id)
            let colAfterFolderDelete = appState.workspace.collections.first(where: { $0.id == col.id })
            XCTAssertTrue(colAfterFolderDelete?.folders.isEmpty ?? false)
            XCTAssertTrue(colAfterFolderDelete?.requests.isEmpty ?? false)
        }
    }

    // MARK: - 14. AuthConfig 与 TLSConfig 编解码及安全模式测试

    func testAuthConfigAndTLSConfigSerialization() throws {
        // 测试所有 5 种 Auth 模式的序列化与反序列化
        let authList: [AuthConfig] = [
            AuthConfig(type: .inherit),
            AuthConfig(type: .none),
            AuthConfig(type: .bearer, bearerToken: "jwt_abc_123"),
            AuthConfig(type: .apiKey, apiKeyName: "X-Auth-Key", apiKeyValue: "secret-key"),
            AuthConfig(type: .basic, username: "admin", password: "pwd")
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for auth in authList {
            let data = try encoder.encode(auth)
            let decoded = try decoder.decode(AuthConfig.self, from: data)
            XCTAssertEqual(auth, decoded)
        }

        // 测试所有 5 种 TLS 模式的序列化与反序列化
        let tlsList: [TLSConfig] = [
            TLSConfig(mode: .inherit),
            TLSConfig(mode: .plaintext),
            TLSConfig(mode: .tlsSystem),
            TLSConfig(mode: .tlsCustomCA, rootCAPath: "/etc/ssl/ca.crt", insecureSkipVerify: true),
            TLSConfig(mode: .mtls, clientCertPath: "/etc/ssl/client.crt", clientKeyPath: "/etc/ssl/client.key")
        ]

        for tls in tlsList {
            let data = try encoder.encode(tls)
            let decoded = try decoder.decode(TLSConfig.self, from: data)
            XCTAssertEqual(tls, decoded)
        }
    }

    // MARK: - 15. EnvironmentModel 变量提取与生产保护属性测试

    func testActiveVariableDictionary() {
        let env = EnvironmentModel(
            name: "Staging",
            variables: [
                VariableItem(key: "host", value: "192.168.1.1", isEnabled: true),
                VariableItem(key: "disabled_var", value: "xyz", isEnabled: false),
                VariableItem(key: "  trimmed_key  ", value: "value123", isEnabled: true),
                VariableItem(key: "", value: "empty_key", isEnabled: true)
            ]
        )

        let dict = env.activeVariableDictionary
        XCTAssertEqual(dict["host"], "192.168.1.1")
        XCTAssertEqual(dict["trimmed_key"], "value123")
        XCTAssertNil(dict["disabled_var"])
        XCTAssertNil(dict[""])
    }

    // MARK: - 16. Bruno 风格 Header Bulk Edit 与 HeaderCatalog 智能知识库测试

    func testHeaderBulkConverter() {
        let rawBulkText = """
        authorization: Bearer test_token_xyz
        content-type: application/grpc+proto
        # x-trace-id: trace_disabled_123
        // x-debug-flag: false
        grpc-timeout: 2S
        custom-header: value:with:multiple:colons
        """

        let parsed = HeaderBulkConverter.fromBulkText(rawBulkText)
        XCTAssertEqual(parsed.count, 6)

        // 1. 验证常规启用 Header
        let auth = parsed.first { $0.key == "authorization" }
        XCTAssertNotNil(auth)
        XCTAssertEqual(auth?.value, "Bearer test_token_xyz")
        XCTAssertTrue(auth?.isEnabled ?? false)

        // 2. 验证注释禁用 Header (# 与 //)
        let trace = parsed.first { $0.key == "x-trace-id" }
        XCTAssertNotNil(trace)
        XCTAssertEqual(trace?.value, "trace_disabled_123")
        XCTAssertFalse(trace?.isEnabled ?? true)

        let debug = parsed.first { $0.key == "x-debug-flag" }
        XCTAssertNotNil(debug)
        XCTAssertEqual(debug?.value, "false")
        XCTAssertFalse(debug?.isEnabled ?? true)

        // 3. 验证值中包含多个冒号的情况
        let multiColons = parsed.first { $0.key == "custom-header" }
        XCTAssertEqual(multiColons?.value, "value:with:multiple:colons")

        // 4. 验证反向转换回纯文本
        let backToText = HeaderBulkConverter.toBulkText(headers: parsed)
        XCTAssertTrue(backToText.contains("authorization: Bearer test_token_xyz"))
        XCTAssertTrue(backToText.contains("# x-trace-id: trace_disabled_123"))
        XCTAssertTrue(backToText.contains("grpc-timeout: 2S"))
    }

    func testHeaderCatalog() {
        // 1. 全量知识库条目检验
        XCTAssertFalse(HeaderCatalog.sharedHeaders.isEmpty)
        XCTAssertTrue(HeaderCatalog.sharedHeaders.contains { $0.name == "grpc-timeout" })
        XCTAssertTrue(HeaderCatalog.sharedHeaders.contains { $0.name == "traceparent" })
        XCTAssertTrue(HeaderCatalog.sharedHeaders.contains { $0.name == "authorization" })

        // 2. 模糊查询匹配检验
        let grpcMatches = HeaderCatalog.search(query: "grpc")
        XCTAssertTrue(grpcMatches.contains { $0.name == "grpc-timeout" })
        XCTAssertTrue(grpcMatches.contains { $0.name == "grpc-encoding" })

        let traceMatches = HeaderCatalog.search(query: "trace")
        XCTAssertTrue(traceMatches.contains { $0.name == "traceparent" })
        XCTAssertTrue(traceMatches.contains { $0.name == "grpc-trace-bin" })

        // 3. 推荐预置值完整性检验
        let authDef = HeaderCatalog.sharedHeaders.first { $0.name == "authorization" }
        XCTAssertTrue(authDef?.presetValues.contains("Bearer {{jwt_token}}") ?? false)

        let timeoutDef = HeaderCatalog.sharedHeaders.first { $0.name == "grpc-timeout" }
        XCTAssertTrue(timeoutDef?.presetValues.contains("1S") ?? false)
    }

    // MARK: - 17. Cmd+P 全局快速直达 (Quick Open) 请求与路径映射测试

    @MainActor
    func testQuickOpenBreadcrumbs() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quick_open_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = StorageManager(appSupportDir: tempDir)
        let appState = AppState(storage: storage)

        appState.createNewCollection(name: "Billing")
        guard let col = appState.workspace.collections.first(where: { $0.name == "Billing" }) else {
            XCTFail("Failed to create Billing collection")
            return
        }

        appState.createFolder(in: col.id, name: "Invoices")
        let folder = appState.workspace.collections.first(where: { $0.id == col.id })?.folders.first

        appState.createNewRequest(in: col.id, folderId: folder?.id)

        let breadcrumbs = appState.allRequestsWithBreadcrumbs()
        XCTAssertFalse(breadcrumbs.isEmpty)

        let found = breadcrumbs.first { $0.collectionName == "Billing" }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.folderName, "Invoices")
        XCTAssertEqual(found?.request.name, "New gRPC Request")
    }

    // MARK: - 18. Bruno 风格声明式免代码断言引擎 (Declarative Assertions) 测试

    func testAssertionEngineStatusAndJSONPath() {
        let jsonPayload = """
        {
            "code": 200,
            "token": "jwt_token_secret_xyz",
            "user": {
                "id": 10086,
                "name": "Alice Cooper",
                "roles": ["admin", "developer"]
            },
            "active": true
        }
        """

        let response = RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: 42.5,
            responseSize: jsonPayload.utf8.count,
            responsePayload: jsonPayload,
            initialMetadata: ["x-trace-id": "trace_999", "content-type": "application/grpc+proto"]
        )

        let rules: [AssertionRule] = [
            AssertionRule(expression: "res.status", op: .equals, expectedValue: "0"),
            AssertionRule(expression: "res.statusName", op: .equals, expectedValue: "OK"),
            AssertionRule(expression: "res.responseTime", op: .lessThan, expectedValue: "200"),
            AssertionRule(expression: "res.body.code", op: .equals, expectedValue: "200"),
            AssertionRule(expression: "res.body.token", op: .isDefined),
            AssertionRule(expression: "res.body.user.id", op: .greaterThan, expectedValue: "1000"),
            AssertionRule(expression: "res.body.user.name", op: .contains, expectedValue: "Alice"),
            AssertionRule(expression: "res.body.user.roles.length", op: .equals, expectedValue: "2"),
            AssertionRule(expression: "res.body.user.roles.0", op: .equals, expectedValue: "admin"),
            AssertionRule(expression: "res.body.non_existent", op: .isNullOrEmpty),
            AssertionRule(expression: "res.headers.x-trace-id", op: .equals, expectedValue: "trace_999")
        ]

        let results = AssertionEngine.shared.evaluateAssertions(rules: rules, response: response)

        XCTAssertEqual(results.count, 11)
        for r in results {
            XCTAssertTrue(r.passed, "断言失败: \(r.expression) \(r.op.rawValue) \(r.expectedValue)，实际为: \(r.actualValue)")
        }
    }

    // MARK: - 19. Bruno 风格响应字段提取 (Post-Response Vars) 接口串联测试

    func testResponseVarExtractionAndChaining() {
        let jsonPayload = """
        {
            "token": "token_abc_123",
            "account": {
                "id": "acc_777"
            }
        }
        """

        let response = RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: 30.0,
            responsePayload: jsonPayload,
            initialMetadata: ["x-req-id": "req_uuid_001"]
        )

        let varRules: [ResponseVarRule] = [
            ResponseVarRule(targetVariable: "auth_token", sourcePath: "res.body.token"),
            ResponseVarRule(targetVariable: "user_account_id", sourcePath: "res.body.account.id"),
            ResponseVarRule(targetVariable: "gateway_trace", sourcePath: "res.headers.x-req-id"),
            ResponseVarRule(targetVariable: "disabled_var", sourcePath: "res.body.token", isEnabled: false)
        ]

        let extracted = AssertionEngine.shared.extractVariables(rules: varRules, response: response)

        XCTAssertEqual(extracted.count, 3)
        XCTAssertEqual(extracted["auth_token"], "token_abc_123")
        XCTAssertEqual(extracted["user_account_id"], "acc_777")
        XCTAssertEqual(extracted["gateway_trace"], "req_uuid_001")
        XCTAssertNil(extracted["disabled_var"])
    }

    // MARK: - 20. Request Markdown 文档持久化与向后兼容测试

    func testRequestDocsFieldPersistenceAndCompatibility() throws {
        let reqWithDocs = RequestModel(
            name: "GetUserProfile",
            serviceName: "user.UserService",
            methodName: "GetProfile",
            docs: "# 获取用户信息\n返回用户的姓名与权限列表。"
        )

        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(reqWithDocs)

        let decoder = JSONDecoder()
        let decodedReq = try decoder.decode(RequestModel.self, from: encodedData)
        XCTAssertEqual(decodedReq.docs, "# 获取用户信息\n返回用户的姓名与权限列表。")

        // 模拟没有 docs 字段的旧版本 JSON
        let legacyJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Legacy Request",
            "address": "127.0.0.1:50051",
            "serviceName": "legacy.Service",
            "methodName": "DoLegacy",
            "callType": "UNARY",
            "payload": "{}"
        }
        """.data(using: .utf8)!

        let legacyDecoded = try decoder.decode(RequestModel.self, from: legacyJSON)
        XCTAssertEqual(legacyDecoded.name, "Legacy Request")
        XCTAssertEqual(legacyDecoded.docs, "", "旧版本 JSON 没有 docs 字段时应平滑回退为空字符串")
    }

    // MARK: - 21. CodeSnippetEngine 客户端代码生成器测试 (Go, Python, TypeScript, Swift, cURL)

    func testCodeSnippetEngineGeneration() {
        let engine = CodeSnippetEngine.shared
        let req = RequestModel(
            name: "OrderCreate",
            serviceName: "order.OrderService",
            methodName: "CreateOrder",
            callType: .unary,
            payload: "{\"userId\": 1001, \"item\": \"MacBook\"}",
            metadata: [
                MetadataHeader(key: "x-tenant-id", value: "tenant_99"),
                MetadataHeader(key: "x-disabled-h", value: "none", isEnabled: false)
            ],
            auth: AuthConfig(type: .bearer, bearerToken: "jwt_token_xyz")
        )

        // 1. Go
        let goCode = engine.generateSnippet(
            language: .golang,
            request: req,
            effectiveAddress: "127.0.0.1:50051",
            effectivePayload: req.payload,
            effectiveHeaders: req.metadata,
            effectiveAuth: req.auth,
            effectiveTLS: TLSConfig(mode: .plaintext)
        )
        XCTAssertTrue(goCode.contains("grpc.NewClient"))
        XCTAssertTrue(goCode.contains("/order.OrderService/CreateOrder"))
        XCTAssertTrue(goCode.contains("\"x-tenant-id\": \"tenant_99\""))
        XCTAssertTrue(goCode.contains("\"authorization\": \"Bearer jwt_token_xyz\""))
        XCTAssertFalse(goCode.contains("x-disabled-h"))

        // 2. Python
        let pyCode = engine.generateSnippet(
            language: .python,
            request: req,
            effectiveAddress: "127.0.0.1:50051",
            effectivePayload: req.payload,
            effectiveHeaders: req.metadata,
            effectiveAuth: req.auth,
            effectiveTLS: TLSConfig(mode: .plaintext)
        )
        XCTAssertTrue(pyCode.contains("grpc.insecure_channel"))
        XCTAssertTrue(pyCode.contains("/order.OrderService/CreateOrder"))
        XCTAssertTrue(pyCode.contains("(\"x-tenant-id\", \"tenant_99\")"))
        XCTAssertTrue(pyCode.contains("(\"authorization\", \"Bearer jwt_token_xyz\")"))

        // 3. TypeScript
        let tsCode = engine.generateSnippet(
            language: .typescript,
            request: req,
            effectiveAddress: "127.0.0.1:50051",
            effectivePayload: req.payload,
            effectiveHeaders: req.metadata,
            effectiveAuth: req.auth,
            effectiveTLS: TLSConfig(mode: .plaintext)
        )
        XCTAssertTrue(tsCode.contains("@grpc/grpc-js"))
        XCTAssertTrue(tsCode.contains("metadata.add('authorization', 'Bearer jwt_token_xyz')"))

        // 4. Swift
        let swiftCode = engine.generateSnippet(
            language: .swift,
            request: req,
            effectiveAddress: "127.0.0.1:50051",
            effectivePayload: req.payload,
            effectiveHeaders: req.metadata,
            effectiveAuth: req.auth,
            effectiveTLS: TLSConfig(mode: .plaintext)
        )
        XCTAssertTrue(swiftCode.contains("sendGRPCRequest() async throws"))
        XCTAssertTrue(swiftCode.contains("/order.OrderService/CreateOrder"))

        // 5. cURL
        let curlCode = engine.generateSnippet(
            language: .curl,
            request: req,
            effectiveAddress: "127.0.0.1:50051",
            effectivePayload: req.payload,
            effectiveHeaders: req.metadata,
            effectiveAuth: req.auth,
            effectiveTLS: TLSConfig(mode: .plaintext)
        )
        XCTAssertTrue(curlCode.contains("curl -X POST"))
        XCTAssertTrue(curlCode.contains("http://127.0.0.1:50051/order.OrderService/CreateOrder"))
        XCTAssertTrue(curlCode.contains("Authorization: Bearer jwt_token_xyz"))
    }

    // MARK: - 22. CollectionRunnerEngine 批量自动化测试执行与 Markdown 报告测试

    func testCollectionRunnerEngineExecution() async {
        let runner = CollectionRunnerEngine.shared

        // 请求 1: 登录并提取 Token
        var reqLogin = RequestModel(
            name: "1. Login",
            address: "127.0.0.1:50051",
            serviceName: "auth.AuthService",
            methodName: "Login",
            callType: .unary,
            payload: "{\"username\": \"admin\"}"
        )
        reqLogin.assertions = [
            AssertionRule(expression: "res.status", op: .equals, expectedValue: "0")
        ]
        reqLogin.responseVars = [
            ResponseVarRule(targetVariable: "session_token", sourcePath: "res.body.token")
        ]

        // 请求 2: 使用提取到的 {{session_token}} 获取账户信息
        var reqProfile = RequestModel(
            name: "2. GetProfile",
            address: "127.0.0.1:50051",
            serviceName: "user.UserService",
            methodName: "GetProfile",
            callType: .unary,
            payload: "{}",
            auth: AuthConfig(type: .bearer, bearerToken: "{{session_token}}")
        )
        reqProfile.assertions = [
            AssertionRule(expression: "res.status", op: .equals, expectedValue: "0"),
            AssertionRule(expression: "res.responseTime", op: .lessThan, expectedValue: "10000")
        ]

        let config = CollectionRunConfig(
            collectionId: UUID(),
            collectionName: "UserWorkflowSuite",
            delayMs: 0,
            stopOnFirstFailure: false
        )

        let summary = await runner.run(
            config: config,
            requests: [reqLogin, reqProfile],
            baseEnvironment: EnvironmentModel(name: "TestEnv"),
            globalVariables: [],
            resolveEffectiveConfig: { req in
                AppState.EffectiveRequestConfig(
                    effectiveRequest: req,
                    effectiveAuth: req.auth,
                    authSource: "直接配置",
                    inheritedMetadata: [],
                    effectiveSecurity: TLSConfig(mode: .plaintext),
                    securitySource: "默认",
                    effectiveTimeout: 15.0
                )
            }
        )

        XCTAssertEqual(summary.totalRequests, 2)
        XCTAssertEqual(summary.results.count, 2)
        XCTAssertTrue(summary.totalDurationMs >= 0)
        XCTAssertEqual(summary.totalAssertions, 3)

        // 验证 Markdown 测试报告生成
        let mdReport = summary.exportMarkdownReport()
        XCTAssertTrue(mdReport.contains("# Pulsar 自动化测试执行报告"))
        XCTAssertTrue(mdReport.contains("UserWorkflowSuite"))
        XCTAssertTrue(mdReport.contains("用例明细列表"))
        XCTAssertTrue(mdReport.contains("1. Login"))
        XCTAssertTrue(mdReport.contains("2. GetProfile"))
    }

    // MARK: - 23. EnvironmentEngine 加密散列与高级动态数据生成测试

    func testEnvironmentEngineCryptoAndGenerators() {
        let engine = EnvironmentEngine.shared

        // 1. 动态邮箱、IP、手机号
        let email = engine.resolve(template: "{{$randomEmail}}")
        XCTAssertTrue(email.hasPrefix("user_") && email.hasSuffix("@example.com"))

        let ip = engine.resolve(template: "{{$randomIPv4}}")
        let ipParts = ip.components(separatedBy: ".")
        XCTAssertEqual(ipParts.count, 4)

        let phone = engine.resolve(template: "{{$randomPhone}}")
        XCTAssertTrue(phone.hasPrefix("138"))
        XCTAssertEqual(phone.count, 11)

        // 2. Base64 编解码
        let b64Encoded = engine.resolve(template: "{{$base64Encode(\"Pulsar\")}}")
        XCTAssertEqual(b64Encoded, "UHVsc2Fy")

        let b64Decoded = engine.resolve(template: "{{$base64Decode(\"UHVsc2Fy\")}}")
        XCTAssertEqual(b64Decoded, "Pulsar")

        // 3. SHA-256 与 MD5
        // echo -n "admin123" | shasum -a 256 -> 240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9
        let sha = engine.resolve(template: "{{$sha256(\"admin123\")}}")
        XCTAssertEqual(sha, "240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9")

        // echo -n "admin123" | md5 -> 0192023a7bbd73250516f069df18b500
        let md5 = engine.resolve(template: "{{$md5(\"admin123\")}}")
        XCTAssertEqual(md5, "0192023a7bbd73250516f069df18b500")
    }

    // MARK: - 24. Git 目录机密物理隔离与 .gitignore 自动防护测试

    func testCollectionDirectorySecretsIsolation() throws {
        let syncService = CollectionDirectorySyncService.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var col = CollectionModel(name: "SecuritySuite")
        let req = RequestModel(name: "SecretReq", serviceName: "sec.SecService", methodName: "DoSec")
        col.requests.append(req)

        let envWithSecret = EnvironmentModel(
            name: "ProdEnv",
            variables: [
                VariableItem(key: "public_host", value: "api.company.com", isSecret: false),
                VariableItem(key: "api_secret_key", value: "sk_live_998877665544", isSecret: true)
            ]
        )

        // 1. 导出集合与带机密的环境
        let exportedDir = try syncService.exportCollection(col, environments: [envWithSecret], to: tempDir)

        // 2. 验证 .gitignore 存在且包含机密隔离规则
        let gitignorePath = exportedDir.appendingPathComponent(".gitignore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitignorePath.path))
        let gitignoreContent = try String(contentsOf: gitignorePath, encoding: .utf8)
        XCTAssertTrue(gitignoreContent.contains("environments/*.secrets.json"))

        // 3. 验证公开环境变量文件脱敏
        let publicEnvPath = exportedDir.appendingPathComponent("environments/ProdEnv.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: publicEnvPath.path))
        let publicEnvData = try Data(contentsOf: publicEnvPath)
        let publicEnv = try JSONDecoder().decode(EnvironmentModel.self, from: publicEnvData)
        let secretItemInPublic = publicEnv.variables.first { $0.key == "api_secret_key" }
        XCTAssertEqual(secretItemInPublic?.value, "", "公开 JSON 中的敏感变量值必须被置空脱敏")

        // 4. 验证物理独立的 .secrets.json 存在且保存真实机密
        let secretEnvPath = exportedDir.appendingPathComponent("environments/ProdEnv.secrets.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secretEnvPath.path))
        let secretEnvData = try Data(contentsOf: secretEnvPath)
        let secretVars = try JSONDecoder().decode([VariableItem].self, from: secretEnvData)
        XCTAssertEqual(secretVars.first?.value, "sk_live_998877665544")

        // 5. 导入该目录，验证本地自动将 .secrets.json 中的真实机密恢复合并
        let imported = try syncService.importCollection(from: exportedDir)
        let importedEnv = imported.environments.first { $0.name == "ProdEnv" }
        let restoredSecret = importedEnv?.variables.first { $0.key == "api_secret_key" }
        XCTAssertEqual(restoredSecret?.value, "sk_live_998877665544", "导入时应自动将 .secrets.json 机密值合并恢复")
        XCTAssertTrue(restoredSecret?.isSecret == true)
    }

    // MARK: - 25. ResponseDiffEngine 响应快照与 JSON 语义 Diff 测试

    func testResponseDiffEngine() {
        let diffEngine = ResponseDiffEngine.shared

        let baseResp = RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: 15.0,
            responsePayload: """
            {
              "id": 100,
              "name": "Alice",
              "role": "Developer"
            }
            """
        )

        // 1. 完全一致测试
        let identicalReport = diffEngine.compare(baseline: baseResp, current: baseResp)
        XCTAssertTrue(identicalReport.isIdentical)
        XCTAssertEqual(identicalReport.addedCount, 0)
        XCTAssertEqual(identicalReport.removedCount, 0)
        XCTAssertEqual(identicalReport.latencyDeltaMs, 0.0)

        // 2. 修改与新增测试
        let modifiedResp = RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: 25.0,
            responsePayload: """
            {
              "id": 100,
              "name": "Alice Cooper",
              "role": "Developer",
              "team": "Architecture"
            }
            """
        )

        let diffReport = diffEngine.compare(baseline: baseResp, current: modifiedResp)
        XCTAssertFalse(diffReport.isIdentical)
        XCTAssertTrue(diffReport.addedCount > 0)
        XCTAssertEqual(diffReport.latencyDeltaMs, 10.0)
        XCTAssertFalse(diffReport.statusCodeChanged)

        // 3. 验证 Markdown 报告生成
        let reportMD = diffReport.exportMarkdownReport()
        XCTAssertTrue(reportMD.contains("# Pulsar 响应快照差异对比报告"))
        XCTAssertTrue(reportMD.contains("载荷 Diff 详情"))
        XCTAssertTrue(reportMD.contains("+"))
    }

    // MARK: - 26. 环境变量循环引用与畸形占位符边界测试 (Edge Cases)

    func testCircularVariableReferenceProtection() {
        let engine = EnvironmentEngine.shared

        // 1. 相互循环引用 A -> B -> A
        let envCircular = EnvironmentModel(
            name: "CircularEnv",
            variables: [
                VariableItem(key: "A", value: "{{B}}"),
                VariableItem(key: "B", value: "{{A}}")
            ]
        )
        // 应该在 maxDepth 处被安全截断，绝不发生死循环或栈溢出
        let resolvedCircular = engine.resolve(template: "val_{{A}}", environment: envCircular, maxDepth: 5)
        XCTAssertTrue(resolvedCircular.contains("{{A}}") || resolvedCircular.contains("{{B}}"))

        // 2. 自引用 X -> X
        let envSelf = EnvironmentModel(
            name: "SelfEnv",
            variables: [
                VariableItem(key: "X", value: "prefix_{{X}}")
            ]
        )
        let resolvedSelf = engine.resolve(template: "{{X}}", environment: envSelf, maxDepth: 3)
        XCTAssertTrue(resolvedSelf.contains("prefix_"))

        // 3. 4 层深度正常级联解析
        let envDeep = EnvironmentModel(
            name: "DeepEnv",
            variables: [
                VariableItem(key: "k1", value: "{{k2}}"),
                VariableItem(key: "k2", value: "{{k3}}"),
                VariableItem(key: "k3", value: "{{k4}}"),
                VariableItem(key: "k4", value: "deep_success")
            ]
        )
        let resolvedDeep = engine.resolve(template: "{{k1}}", environment: envDeep, maxDepth: 5)
        XCTAssertEqual(resolvedDeep, "deep_success")

        // 4. 空占位符与畸形花括号
        XCTAssertEqual(engine.resolve(template: "{{}}"), "{{}}")
        XCTAssertEqual(engine.resolve(template: "{{   }}"), "{{   }}")
        XCTAssertEqual(engine.resolve(template: "hello {{unknown}}"), "hello {{unknown}}")
        XCTAssertEqual(engine.resolve(template: "plain text without braces"), "plain text without braces")
        XCTAssertEqual(engine.resolve(template: ""), "")
    }

    // MARK: - 27. AssertionEngine 复杂多维数组、Null 与非对称断言边界测试 (Edge Cases)

    func testAssertionEngineComplexArrayAndNullPaths() {
        let engine = AssertionEngine.shared

        let complexJSON = """
        {
            "matrix": [
                [10, 20],
                [30, 40]
            ],
            "users": [
                {"name": "Alice", "deletedAt": null},
                {"name": "Bob", "tags": ["admin", "super"]}
            ],
            "negative": -42,
            "floatVal": 3.14159,
            "emptyStr": "",
            "emptyArr": []
        }
        """

        let response = RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: 12.3,
            responsePayload: complexJSON
        )

        let rules: [AssertionRule] = [
            // 多维数组索引
            AssertionRule(expression: "res.body.matrix.1.0", op: .equals, expectedValue: "30"),
            AssertionRule(expression: "res.body.matrix.1.1", op: .equals, expectedValue: "40"),
            // 嵌套对象数组
            AssertionRule(expression: "res.body.users.1.tags.1", op: .equals, expectedValue: "super"),
            AssertionRule(expression: "res.body.users.1.tags.length", op: .equals, expectedValue: "2"),
            // null 字段校验
            AssertionRule(expression: "res.body.users.0.deletedAt", op: .isNullOrEmpty),
            AssertionRule(expression: "res.body.users.0.deletedAt", op: .notEquals, expectedValue: "valid"),
            // 越界索引防护
            AssertionRule(expression: "res.body.matrix.99.0", op: .isNullOrEmpty),
            AssertionRule(expression: "res.body.users.5.name", op: .isNullOrEmpty),
            // 负数与浮点数比较
            AssertionRule(expression: "res.body.negative", op: .lessThan, expectedValue: "0"),
            AssertionRule(expression: "res.body.negative", op: .greaterThan, expectedValue: "-50"),
            AssertionRule(expression: "res.body.floatVal", op: .equals, expectedValue: "3.14158"), // 容差范围内
            // 空字符串与空数组
            AssertionRule(expression: "res.body.emptyStr", op: .isNullOrEmpty),
            AssertionRule(expression: "res.body.emptyArr.length", op: .equals, expectedValue: "0")
        ]

        let results = engine.evaluateAssertions(rules: rules, response: response)
        for r in results {
            XCTAssertTrue(r.passed, "断言异常失败: \(r.expression) \(r.op.rawValue) \(r.expectedValue)，实际值: \(r.actualValue)")
        }

        // 畸形非 JSON 响应体保护
        let malformedResp = RPCResponse(
            requestId: UUID(),
            statusCode: 14,
            statusName: "UNAVAILABLE",
            durationMs: 1.0,
            responsePayload: "Internal Server Error HTML 502"
        )
        let malformedResults = engine.evaluateAssertions(
            rules: [AssertionRule(expression: "res.body.user.name", op: .isNullOrEmpty)],
            response: malformedResp
        )
        XCTAssertTrue(malformedResults.first?.passed ?? false)
    }

    // MARK: - 28. CollectionRunner 熔断策略与空任务边界测试 (Edge Cases)

    func testCollectionRunnerCancellationAndEdgeCases() async {
        let runner = CollectionRunnerEngine.shared

        // 1. 空用例列表
        let emptyConfig = CollectionRunConfig(collectionId: UUID(), collectionName: "EmptySuite")
        let emptySummary = await runner.run(
            config: emptyConfig,
            requests: [],
            baseEnvironment: nil,
            globalVariables: [],
            resolveEffectiveConfig: { req in
                AppState.EffectiveRequestConfig(
                    effectiveRequest: req,
                    effectiveAuth: req.auth,
                    authSource: "默认",
                    inheritedMetadata: [],
                    effectiveSecurity: TLSConfig(mode: .plaintext),
                    securitySource: "默认",
                    effectiveTimeout: 10.0
                )
            }
        )
        XCTAssertEqual(emptySummary.totalRequests, 0)
        XCTAssertTrue(emptySummary.results.isEmpty)

        // 2. 外部预先取消 (Pre-cancelled)
        let cancelledSummary = await runner.run(
            config: emptyConfig,
            requests: [RequestModel(name: "Req1"), RequestModel(name: "Req2")],
            baseEnvironment: nil,
            globalVariables: [],
            resolveEffectiveConfig: { req in
                AppState.EffectiveRequestConfig(
                    effectiveRequest: req,
                    effectiveAuth: req.auth,
                    authSource: "默认",
                    inheritedMetadata: [],
                    effectiveSecurity: TLSConfig(mode: .plaintext),
                    securitySource: "默认",
                    effectiveTimeout: 10.0
                )
            },
            isCancelled: { true }
        )
        XCTAssertEqual(cancelledSummary.results.count, 0)

        // 3. 熔断策略 (stopOnFirstFailure): 第一条请求断言失败，后续请求应被立即跳过
        var failReq = RequestModel(name: "FailReq")
        failReq.assertions = [
            AssertionRule(expression: "res.status", op: .equals, expectedValue: "999") // 故意失败
        ]
        let passReq1 = RequestModel(name: "PassReq1")
        let passReq2 = RequestModel(name: "PassReq2")

        let fuseConfig = CollectionRunConfig(
            collectionId: UUID(),
            collectionName: "FusingSuite",
            stopOnFirstFailure: true
        )

        let fusedSummary = await runner.run(
            config: fuseConfig,
            requests: [failReq, passReq1, passReq2],
            baseEnvironment: nil,
            globalVariables: [],
            resolveEffectiveConfig: { req in
                AppState.EffectiveRequestConfig(
                    effectiveRequest: req,
                    effectiveAuth: req.auth,
                    authSource: "默认",
                    inheritedMetadata: [],
                    effectiveSecurity: TLSConfig(mode: .plaintext),
                    securitySource: "默认",
                    effectiveTimeout: 10.0
                )
            }
        )
        // 应该在第 1 条失败后熔断停止，总执行结果数应为 1 而不是 3
        XCTAssertEqual(fusedSummary.results.count, 1)
        XCTAssertEqual(fusedSummary.failedRequests, 1)
        XCTAssertFalse(fusedSummary.results.first?.isSuccess ?? true)
    }

    // MARK: - 29. ResponseDiff 极端空载荷与完全不相关载荷对比测试 (Edge Cases)

    func testResponseDiffEmptyAndDisjointPayloads() {
        let diffEngine = ResponseDiffEngine.shared

        // 1. 两端均为空
        let empty1 = RPCResponse(requestId: UUID(), statusCode: 0, statusName: "OK", durationMs: 10, responsePayload: "")
        let empty2 = RPCResponse(requestId: UUID(), statusCode: 0, statusName: "OK", durationMs: 10, responsePayload: "")
        let emptyReport = diffEngine.compare(baseline: empty1, current: empty2)
        XCTAssertTrue(emptyReport.isIdentical)
        XCTAssertEqual(emptyReport.addedCount, 0)
        XCTAssertEqual(emptyReport.removedCount, 0)

        // 2. 两端完全无交集的非 JSON 纯文本
        let disjoint1 = RPCResponse(requestId: UUID(), statusCode: 0, statusName: "OK", durationMs: 10, responsePayload: "alpha\nbeta\ngamma")
        let disjoint2 = RPCResponse(requestId: UUID(), statusCode: 0, statusName: "OK", durationMs: 20, responsePayload: "one\ntwo\nthree")
        let disjointReport = diffEngine.compare(baseline: disjoint1, current: disjoint2)
        XCTAssertFalse(disjointReport.isIdentical)
        XCTAssertEqual(disjointReport.removedCount, 3)
        XCTAssertEqual(disjointReport.addedCount, 3)
        XCTAssertEqual(disjointReport.latencyDeltaMs, 10.0)

        // 3. 状态码突变 (例如 200 OK -> 503 UNAVAILABLE)
        let statusErrorResp = RPCResponse(requestId: UUID(), statusCode: 14, statusName: "UNAVAILABLE", durationMs: 50, responsePayload: "")
        let statusReport = diffEngine.compare(baseline: empty1, current: statusErrorResp)
        XCTAssertTrue(statusReport.statusCodeChanged)
    }

    // MARK: - 30. HeaderBulkConverter 边缘格式兼容测试 (Edge Cases)

    func testHeaderBulkConverterEdgeCases() {
        // 1. 空输入与全换行
        let emptyHeaders = HeaderBulkConverter.fromBulkText("   \n\n  \t  \n")
        XCTAssertTrue(emptyHeaders.isEmpty)

        // 2. 缺失冒号的非法行过滤
        let invalidLinesText = """
        This is an invalid header line without colon
        Valid-Header: 123
        Another broken line
        """
        let parsedInvalid = HeaderBulkConverter.fromBulkText(invalidLinesText)
        XCTAssertEqual(parsedInvalid.count, 1)
        XCTAssertEqual(parsedInvalid.first?.key, "Valid-Header")
        XCTAssertEqual(parsedInvalid.first?.value, "123")

        // 3. 多种注释符号 (#, //) 与首尾留白
        let commentText = """
          # Commented-Header-1: value1  
          // Commented-Header-2: value2
        Normal-Header: normal
        """
        let parsedComments = HeaderBulkConverter.fromBulkText(commentText)
        XCTAssertEqual(parsedComments.count, 3)
        XCTAssertFalse(parsedComments[0].isEnabled)
        XCTAssertEqual(parsedComments[0].key, "Commented-Header-1")
        XCTAssertFalse(parsedComments[1].isEnabled)
        XCTAssertEqual(parsedComments[1].key, "Commented-Header-2")
        XCTAssertTrue(parsedComments[2].isEnabled)
        XCTAssertEqual(parsedComments[2].key, "Normal-Header")
    }

    // MARK: - 31. AppState 标签页极端切换与搜索过滤边界测试 (UI State Edge Cases)

    @MainActor
    func testAppStateTabNavigationAndEdgeCases() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tab_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = StorageManager(appSupportDir: tempDir)
        let appState = AppState(storage: storage)
        appState.openTabIds = []
        appState.activeTabId = nil

        let col = CollectionModel(name: "UITestCol")
        let req1 = RequestModel(name: "Req 1", collectionId: col.id)
        let req2 = RequestModel(name: "Req 2", collectionId: col.id)
        let req3 = RequestModel(name: "Req 3", collectionId: col.id)
        var fullCol = col
        fullCol.requests = [req1, req2, req3]
        appState.workspace.collections = [fullCol]

        // 1. 打开 3 个 Tab，当前为 req2
        appState.openTab(for: req1)
        appState.openTab(for: req2)
        appState.openTab(for: req3)
        appState.activeTabId = req2.id
        XCTAssertEqual(appState.openTabIds.count, 3)
        XCTAssertEqual(appState.activeTabId, req2.id)

        // 2. 关闭中间激活的 req2 -> activeTab 自动平滑顺延到下一个/邻近 Tab
        appState.closeTab(id: req2.id)
        XCTAssertEqual(appState.openTabIds.count, 2)
        XCTAssertNotNil(appState.activeTabId)
        XCTAssertNotEqual(appState.activeTabId, req2.id)

        // 3. 关闭不存在的 UUID -> 不崩溃且保持不变
        let nonExistentId = UUID()
        appState.closeTab(id: nonExistentId)
        XCTAssertEqual(appState.openTabIds.count, 2)

        // 4. 全部关闭
        appState.closeTab(id: req1.id)
        appState.closeTab(id: req3.id)
        XCTAssertTrue(appState.openTabIds.isEmpty)
        XCTAssertNil(appState.activeTabId)

        // 5. 搜索过滤含特殊正则字符 (e.g. `[`, `*`, `(`, `\`) 不引起崩溃
        appState.searchQuery = "Req [1]*("
        let safeFiltered = appState.filteredRequests(in: fullCol)
        XCTAssertTrue(safeFiltered.isEmpty)

        appState.searchQuery = "req"
        let matched = appState.filteredRequests(in: fullCol)
        XCTAssertEqual(matched.count, 3)
    }

    // MARK: - 37. Proto 解析器换行括号容错与多服务测试

    func testLocalProtoParserResilienceNewlineBracesAndComments() {
        let multiServiceProto = """
        syntax = "proto3";
        package company.api;

        // User service with brace on newline
        service UserService
        {
            rpc GetUser (UserRequest) returns (UserResponse);
            rpc StreamUsers (UserRequest) returns (stream UserResponse) {}
        }

        // Notification service with inline and multiline comments
        service NotificationService {
            rpc SendEmail (EmailRequest) returns (EmailResponse) {
                option (custom.opt) = "val";
            }
        }
        """

        let file = LocalProtoParser.shared.parseString(multiServiceProto, fileName: "api.proto")
        XCTAssertEqual(file.packageName, "company.api")
        XCTAssertEqual(file.services.count, 2)

        let userSvc = file.services.first(where: { $0.name == "UserService" })
        XCTAssertNotNil(userSvc)
        XCTAssertEqual(userSvc?.fullName, "company.api.UserService")
        XCTAssertEqual(userSvc?.methods.count, 2)
        XCTAssertEqual(userSvc?.methods.first?.name, "GetUser")
        XCTAssertEqual(userSvc?.methods.first?.callType, .unary)
        XCTAssertEqual(userSvc?.methods.last?.name, "StreamUsers")
        XCTAssertEqual(userSvc?.methods.last?.callType, .serverStreaming)

        let notifSvc = file.services.first(where: { $0.name == "NotificationService" })
        XCTAssertNotNil(notifSvc)
        XCTAssertEqual(notifSvc?.methods.count, 1)
        XCTAssertEqual(notifSvc?.methods.first?.name, "SendEmail")
    }

    // MARK: - 38. Service 与 Method 专属联动与补全测试

    func testServiceAndMethodAutocompleteFieldInteraction() {
        var req = RequestModel(name: "Test RPC", address: "localhost:50051")
        req.serviceName = ""
        req.methodName = ""

        let services = ProtoRepository.shared.allServices
        XCTAssertTrue(services.count >= 2)

        // 验证 Greeter 服务的可用方法
        let greeterSvc = services.first(where: { $0.name == "Greeter" || $0.fullName.hasSuffix(".Greeter") })
        XCTAssertNotNil(greeterSvc)

        // 模拟通过 ServiceAutocompleteField 选取服务
        req.serviceName = greeterSvc!.fullName

        // 验证在此服务下，方法候选列表严格只包含该服务的 RPC (排除其他服务方法)
        let availableMethodsForGreeter = greeterSvc!.methods
        XCTAssertTrue(availableMethodsForGreeter.contains(where: { $0.name == "SayHello" }))
        XCTAssertTrue(availableMethodsForGreeter.contains(where: { $0.name == "SayHelloStream" }))
        XCTAssertFalse(availableMethodsForGreeter.contains(where: { $0.name == "CreateOrder" }))

        // 模拟选取 SayHelloStream 方法
        let streamMethod = availableMethodsForGreeter.first(where: { $0.name == "SayHelloStream" })!
        req.methodName = streamMethod.name
        req.callType = streamMethod.callType
        XCTAssertEqual(req.callType, GRPCCallType.serverStreaming)

        // 切换服务为 OrderService，验证 SayHelloStream 不属于 OrderService 并被自动重置清空
        let orderSvc = services.first(where: { $0.name == "OrderService" || $0.fullName.hasSuffix(".OrderService") })!
        req.serviceName = orderSvc.fullName
        if !orderSvc.methods.contains(where: { $0.name == req.methodName }) {
            req.methodName = ""
        }
        XCTAssertEqual(req.methodName, "")

        // 在 OrderService 下选取 CreateOrder
        let orderMethod = orderSvc.methods.first(where: { $0.name == "CreateOrder" })!
        req.methodName = orderMethod.name
        req.callType = orderMethod.callType
        XCTAssertEqual(req.callType, GRPCCallType.unary)
        XCTAssertEqual(req.serviceName, orderSvc.fullName)
    }

    // MARK: - 39. activeRequestBinding 双向实时响应与持久化同步测试

    func testActiveRequestBindingTwoWayDataSync() {
        let appState = AppState()
        guard let reqId = appState.activeTabId else {
            XCTFail("Should have active request")
            return
        }

        guard let binding = appState.activeRequestBinding() else {
            XCTFail("activeRequestBinding should not be nil")
            return
        }

        // 验证通过 binding 写入 serviceName 与 methodName
        binding.wrappedValue.serviceName = "helloworld.Greeter"
        binding.wrappedValue.methodName = "SayHello"
        binding.wrappedValue.callType = .unary

        // 验证 AppState.activeRequest 与底层 workspace 数据立即同步更新，无快照延迟
        XCTAssertEqual(appState.activeRequest?.serviceName, "helloworld.Greeter")
        XCTAssertEqual(appState.activeRequest?.methodName, "SayHello")
        XCTAssertEqual(appState.activeRequest?.callType, .unary)
        XCTAssertTrue(appState.dirtyTabIds.contains(reqId))

        // 验证 binding 读取到的值完全一致
        XCTAssertEqual(binding.wrappedValue.serviceName, "helloworld.Greeter")
        XCTAssertEqual(binding.wrappedValue.methodName, "SayHello")
    }
}

// MARK: - Mock URLProtocol for Nacos HTTP 测试

final class MockNacosURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if let data = MockNacosURLProtocol.mockData {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1:8848")!,
                statusCode: MockNacosURLProtocol.mockStatusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

