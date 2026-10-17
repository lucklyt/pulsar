import Foundation

/// gRPC 核心调用引擎与网络抽象层
public final class GRPCClientEngine {
    public static let shared = GRPCClientEngine()

    public init() {}

    /// 执行 RPC 调用
    /// - Parameters:
    ///   - request: 请求定义模型
    ///   - activeEnvironment: 当前活动环境变量
    ///   - globalVariables: 全局变量
    ///   - onStreamEvent: 流式事件回调 (收到新入站/出站包时触发)
    public func execute(
        request: RequestModel,
        activeEnvironment: EnvironmentModel?,
        globalVariables: [VariableItem],
        onStreamEvent: ((StreamEvent) -> Void)? = nil
    ) async -> RPCResponse {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. 变量解析
        var resolvedAddress = EnvironmentEngine.shared.resolve(
            template: request.address,
            environment: activeEnvironment,
            globalVariables: globalVariables
        )

        let resolvedPayload = EnvironmentEngine.shared.resolve(
            template: request.payload,
            environment: activeEnvironment,
            globalVariables: globalVariables
        )

        // 2. Nacos 服务发现解析
        if request.discovery.scheme == .nacos || resolvedAddress.starts(with: "nacos://") {
            do {
                resolvedAddress = try await NacosResolver.shared.resolve(address: resolvedAddress)
            } catch {
                let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return RPCResponse(
                    requestId: request.id,
                    statusCode: 14, // UNAVAILABLE
                    statusName: GRPCStatusCode.name(for: 14),
                    errorMessage: "Nacos Resolution Error: \(error.localizedDescription)",
                    durationMs: durationMs,
                    responsePayload: "{\n  \"error\": \"Failed to resolve Nacos service\",\n  \"details\": \"\(error.localizedDescription)\"\n}",
                    stats: RPCStatistics(totalDurationMs: durationMs)
                )
            }
        }

        // 3. 构建发送请求头
        var outboundHeaders: [String: String] = [:]
        for h in request.metadata where h.isEnabled && !h.key.isEmpty {
            let k = h.key.lowercased()
            let v = EnvironmentEngine.shared.resolve(template: h.value, environment: activeEnvironment, globalVariables: globalVariables)
            outboundHeaders[k] = v
        }

        // 注入 Auth
        switch request.auth.type {
        case .bearer:
            let token = EnvironmentEngine.shared.resolve(template: request.auth.bearerToken, environment: activeEnvironment, globalVariables: globalVariables)
            if !token.isEmpty {
                outboundHeaders["authorization"] = "Bearer \(token)"
            }
        case .apiKey:
            let key = EnvironmentEngine.shared.resolve(template: request.auth.apiKeyName, environment: activeEnvironment, globalVariables: globalVariables)
            let val = EnvironmentEngine.shared.resolve(template: request.auth.apiKeyValue, environment: activeEnvironment, globalVariables: globalVariables)
            if !key.isEmpty && !val.isEmpty {
                outboundHeaders[key.lowercased()] = val
            }
        case .basic:
            let u = EnvironmentEngine.shared.resolve(template: request.auth.username, environment: activeEnvironment, globalVariables: globalVariables)
            let p = EnvironmentEngine.shared.resolve(template: request.auth.password, environment: activeEnvironment, globalVariables: globalVariables)
            if !u.isEmpty {
                let b64 = Data("\(u):\(p)".utf8).base64EncodedString()
                outboundHeaders["authorization"] = "Basic \(b64)"
            }
        case .none:
            break
        }

        // 4. 执行调度逻辑 (按 Unary 与三种 Streaming 分支处理)
        switch request.callType {
        case .unary:
            return await executeUnary(
                requestId: request.id,
                target: resolvedAddress,
                service: request.serviceName,
                method: request.methodName,
                payload: resolvedPayload,
                headers: outboundHeaders,
                startTime: startTime
            )
        case .serverStreaming:
            return await executeServerStreaming(
                requestId: request.id,
                target: resolvedAddress,
                service: request.serviceName,
                method: request.methodName,
                payload: resolvedPayload,
                headers: outboundHeaders,
                startTime: startTime,
                onStreamEvent: onStreamEvent
            )
        case .clientStreaming:
            return await executeClientStreaming(
                requestId: request.id,
                target: resolvedAddress,
                service: request.serviceName,
                method: request.methodName,
                payload: resolvedPayload,
                headers: outboundHeaders,
                startTime: startTime,
                onStreamEvent: onStreamEvent
            )
        case .bidiStreaming:
            return await executeBidiStreaming(
                requestId: request.id,
                target: resolvedAddress,
                service: request.serviceName,
                method: request.methodName,
                payload: resolvedPayload,
                headers: outboundHeaders,
                startTime: startTime,
                onStreamEvent: onStreamEvent
            )
        }
    }

    // MARK: - Unary 执行流程

    private func executeUnary(
        requestId: UUID,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime
    ) async -> RPCResponse {
        // 模拟真实网络往返延时与响应封装 (毫秒级响应)
        try? await Task.sleep(nanoseconds: 35_000_000)

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        let responseBody: String
        let statusCode: Int
        let statusName: String

        if service.contains("Greeter") || method.contains("SayHello") {
            responseBody = """
            {
              "message": "Hello from gRPC server on \(target)! Received at \(ISO8601DateFormatter().string(from: Date()))",
              "status": "SUCCESS",
              "received_payload_bytes": \(payload.utf8.count)
            }
            """
            statusCode = 0
            statusName = "OK"
        } else if service.contains("OrderService") {
            responseBody = """
            {
              "order_id": "ord_98765",
              "status": "CONFIRMED",
              "items_count": 3,
              "total_amount": 199.50,
              "currency": "USD",
              "routed_by_nacos": true,
              "target_node": "\(target)"
            }
            """
            statusCode = 0
            statusName = "OK"
        } else {
            responseBody = """
            {
              "reply": "Unary response from \(service)/\(method)",
              "server_endpoint": "\(target)",
              "timestamp": "\(ISO8601DateFormatter().string(from: Date()))"
            }
            """
            statusCode = 0
            statusName = "OK"
        }

        return RPCResponse(
            requestId: requestId,
            statusCode: statusCode,
            statusName: statusName,
            durationMs: durationMs,
            responseSize: responseBody.utf8.count,
            responsePayload: responseBody,
            initialMetadata: [
                "content-type": "application/grpc+proto",
                "grpc-accept-encoding": "identity,deflate,gzip",
                "server": "wombat-grpc-engine/2.0"
            ],
            trailingMetadata: [
                "grpc-status": "0",
                "grpc-message": ""
            ],
            stats: RPCStatistics(
                dnsLookupMs: 2.1,
                tcpConnectMs: 5.4,
                tlsHandshakeMs: 8.2,
                ttfbMs: durationMs * 0.7,
                totalDurationMs: durationMs
            )
        )
    }

    // MARK: - Server Streaming

    private func executeServerStreaming(
        requestId: UUID,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) async -> RPCResponse {
        var events: [StreamEvent] = []

        // 出站初始请求包
        let outEvent = StreamEvent(
            direction: .outbound,
            payload: payload,
            summary: "Client Request (Stream Initiated)"
        )
        events.append(outEvent)
        onStreamEvent?(outEvent)

        // 模拟多帧返回
        for i in 1...3 {
            try? await Task.sleep(nanoseconds: 60_000_000)
            let framePayload = """
            {
              "stream_frame_index": \(i),
              "name": "Feature #\(i) in bounding box",
              "location": {
                "latitude": \(400000000 + i * 50000),
                "longitude": \(-750000000 + i * 40000)
              }
            }
            """
            let inEvent = StreamEvent(
                direction: .inbound,
                payload: framePayload,
                summary: "Response Frame #\(i)"
            )
            events.append(inEvent)
            onStreamEvent?(inEvent)
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        let finalSummary = """
        [
          /* Server Streaming Completed: 3 frames received */
          { "frame": 1, "status": "received" },
          { "frame": 2, "status": "received" },
          { "frame": 3, "status": "received" }
        ]
        """

        return RPCResponse(
            requestId: requestId,
            statusCode: 0,
            statusName: "OK",
            durationMs: durationMs,
            responseSize: events.reduce(0) { $0 + $1.byteSize },
            responsePayload: finalSummary,
            initialMetadata: ["content-type": "application/grpc+proto"],
            trailingMetadata: ["grpc-status": "0"],
            streamEvents: events,
            stats: RPCStatistics(totalDurationMs: durationMs)
        )
    }

    // MARK: - Client Streaming

    private func executeClientStreaming(
        requestId: UUID,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) async -> RPCResponse {
        var events: [StreamEvent] = []

        // 模拟客户端分批发送两个数据帧并半关连接 (Half-Close)
        let frame1 = StreamEvent(direction: .outbound, payload: payload, summary: "Chunk #1")
        events.append(frame1)
        onStreamEvent?(frame1)

        try? await Task.sleep(nanoseconds: 40_000_000)

        let halfClose = StreamEvent(direction: .outbound, payload: "", isHalfClose: true, summary: "EOF (Half-Close)")
        events.append(halfClose)
        onStreamEvent?(halfClose)

        try? await Task.sleep(nanoseconds: 50_000_000)

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let respPayload = """
        {
          "point_count": 1,
          "feature_count": 1,
          "distance": 0,
          "elapsed_time_seconds": \(Int(durationMs / 1000))
        }
        """

        let inEvent = StreamEvent(direction: .inbound, payload: respPayload, summary: "Final Aggregate Response")
        events.append(inEvent)
        onStreamEvent?(inEvent)

        return RPCResponse(
            requestId: requestId,
            statusCode: 0,
            statusName: "OK",
            durationMs: durationMs,
            responseSize: respPayload.utf8.count,
            responsePayload: respPayload,
            streamEvents: events,
            stats: RPCStatistics(totalDurationMs: durationMs)
        )
    }

    // MARK: - Bidirectional Streaming

    private func executeBidiStreaming(
        requestId: UUID,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) async -> RPCResponse {
        var events: [StreamEvent] = []

        // 1. 客户端发送第 1 帧
        let out1 = StreamEvent(direction: .outbound, payload: payload, summary: "Client Chat Message #1")
        events.append(out1)
        onStreamEvent?(out1)

        try? await Task.sleep(nanoseconds: 50_000_000)

        // 2. 服务端实时回传第 1 帧
        let in1 = StreamEvent(
            direction: .inbound,
            payload: "{\n  \"reply_to\": \"Client Chat Message #1\",\n  \"server_ack\": true,\n  \"echo_time\": \"\(Date())\"\n}",
            summary: "Server Echo Frame #1"
        )
        events.append(in1)
        onStreamEvent?(in1)

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return RPCResponse(
            requestId: requestId,
            statusCode: 0,
            statusName: "OK",
            durationMs: durationMs,
            responseSize: events.reduce(0) { $0 + $1.byteSize },
            responsePayload: "/* Bidirectional Stream Active. Check Stream Timeline for frames. */",
            streamEvents: events,
            stats: RPCStatistics(totalDurationMs: durationMs)
        )
    }
}
