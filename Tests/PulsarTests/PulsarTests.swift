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
}
