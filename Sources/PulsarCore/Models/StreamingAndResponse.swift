import Foundation

/// 流式消息方向
public enum StreamDirection: String, Codable {
    case inbound = "INBOUND"   // 服务端发送给客户端 ⬇️
    case outbound = "OUTBOUND" // 客户端发送给服务端 ⬆️
}

/// 流式调用中的单个消息事件
public struct StreamEvent: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var direction: StreamDirection
    public var payload: String
    public var byteSize: Int
    public var isHalfClose: Bool
    public var summary: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: StreamDirection,
        payload: String,
        byteSize: Int = 0,
        isHalfClose: Bool = false,
        summary: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.payload = payload
        self.byteSize = byteSize > 0 ? byteSize : payload.utf8.count
        self.isHalfClose = isHalfClose
        self.summary = summary
    }
}

/// 网络度量与统计
public struct RPCStatistics: Codable, Equatable, Hashable {
    public var dnsLookupMs: Double
    public var tcpConnectMs: Double
    public var tlsHandshakeMs: Double
    public var ttfbMs: Double // Time to first byte
    public var totalDurationMs: Double

    public init(
        dnsLookupMs: Double = 0.0,
        tcpConnectMs: Double = 0.0,
        tlsHandshakeMs: Double = 0.0,
        ttfbMs: Double = 0.0,
        totalDurationMs: Double = 0.0
    ) {
        self.dnsLookupMs = dnsLookupMs
        self.tcpConnectMs = tcpConnectMs
        self.tlsHandshakeMs = tlsHandshakeMs
        self.ttfbMs = ttfbMs
        self.totalDurationMs = totalDurationMs
    }
}

/// gRPC 响应模型
public struct RPCResponse: Identifiable, Codable, Equatable {
    public var id: UUID
    public var requestId: UUID
    public var statusCode: Int
    public var statusName: String
    public var errorMessage: String?
    public var durationMs: Double
    public var responseSize: Int
    public var responsePayload: String
    public var initialMetadata: [String: String]
    public var trailingMetadata: [String: String]
    public var streamEvents: [StreamEvent]
    public var stats: RPCStatistics
    public var executedAt: Date

    public var isSuccess: Bool {
        statusCode == 0
    }

    public init(
        id: UUID = UUID(),
        requestId: UUID,
        statusCode: Int = 0,
        statusName: String = "OK",
        errorMessage: String? = nil,
        durationMs: Double = 0,
        responseSize: Int = 0,
        responsePayload: String = "",
        initialMetadata: [String: String] = [:],
        trailingMetadata: [String: String] = [:],
        streamEvents: [StreamEvent] = [],
        stats: RPCStatistics = RPCStatistics(),
        executedAt: Date = Date()
    ) {
        self.id = id
        self.requestId = requestId
        self.statusCode = statusCode
        self.statusName = statusName
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.responseSize = responseSize > 0 ? responseSize : responsePayload.utf8.count
        self.responsePayload = responsePayload
        self.initialMetadata = initialMetadata
        self.trailingMetadata = trailingMetadata
        self.streamEvents = streamEvents
        self.stats = stats
        self.executedAt = executedAt
    }
}

/// gRPC 标准状态码映射表
public struct GRPCStatusCode {
    public static func name(for code: Int) -> String {
        switch code {
        case 0: return "OK"
        case 1: return "CANCELLED"
        case 2: return "UNKNOWN"
        case 3: return "INVALID_ARGUMENT"
        case 4: return "DEADLINE_EXCEEDED"
        case 5: return "NOT_FOUND"
        case 6: return "ALREADY_EXISTS"
        case 7: return "PERMISSION_DENIED"
        case 8: return "RESOURCE_EXHAUSTED"
        case 9: return "FAILED_PRECONDITION"
        case 10: return "ABORTED"
        case 11: return "OUT_OF_RANGE"
        case 12: return "UNIMPLEMENTED"
        case 13: return "INTERNAL"
        case 14: return "UNAVAILABLE"
        case 15: return "DATA_LOSS"
        case 16: return "UNAUTHENTICATED"
        default: return "UNKNOWN_CODE(\(code))"
        }
    }
}
