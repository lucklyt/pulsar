import Foundation

/// 标准 Header 与 gRPC Metadata 定义模型
public struct HeaderDefinition: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let category: String
    public let presetValues: [String]

    public init(name: String, description: String, category: String, presetValues: [String] = []) {
        self.name = name
        self.description = description
        self.category = category
        self.presetValues = presetValues
    }
}

/// 常用 Header 与 gRPC 专有元数据知识库
public struct HeaderCatalog {
    public static let sharedHeaders: [HeaderDefinition] = [
        // 1. gRPC 专有协议元数据 (gRPC Protocol Metadata)
        HeaderDefinition(
            name: "grpc-timeout",
            description: "RPC 截止时间 (如 1S, 500m, 100u, 10M)，服务端超时自动熔断",
            category: "gRPC 协议",
            presetValues: ["1S", "2S", "5S", "500m", "100m"]
        ),
        HeaderDefinition(
            name: "grpc-encoding",
            description: "指定出站消息压缩编码 (identity, gzip, deflate)",
            category: "gRPC 协议",
            presetValues: ["gzip", "deflate", "identity"]
        ),
        HeaderDefinition(
            name: "grpc-accept-encoding",
            description: "客户端允许服务端回复的压缩格式",
            category: "gRPC 协议",
            presetValues: ["gzip,deflate", "gzip", "identity"]
        ),
        HeaderDefinition(
            name: "grpc-trace-bin",
            description: "二进制分布式调用链路追踪上下文 (Base64)",
            category: "gRPC 协议",
            presetValues: []
        ),

        // 2. 链路追踪与可观测性 (Distributed Tracing & W3C)
        HeaderDefinition(
            name: "traceparent",
            description: "W3C 标准分布式链路追踪上下文 (version-traceid-parentid-flags)",
            category: "链路追踪",
            presetValues: ["00-{{$uuid}}-{{$randomInt(100000, 999999)}}-01"]
        ),
        HeaderDefinition(
            name: "tracestate",
            description: "W3C 标准分布式追踪系统特定键值对透传",
            category: "链路追踪",
            presetValues: []
        ),
        HeaderDefinition(
            name: "x-request-id",
            description: "网关与服务间请求全局唯一标识符",
            category: "链路追踪",
            presetValues: ["{{$uuid}}", "req_{{$timestamp}}"]
        ),
        HeaderDefinition(
            name: "x-correlation-id",
            description: "跨系统业务上下文关联 ID",
            category: "链路追踪",
            presetValues: ["{{$uuid}}"]
        ),
        HeaderDefinition(
            name: "x-b3-traceid",
            description: "Zipkin B3 规范 Trace ID (64 或 128 位十六进制)",
            category: "链路追踪",
            presetValues: ["{{$uuid}}"]
        ),
        HeaderDefinition(
            name: "x-b3-spanid",
            description: "Zipkin B3 规范 Span ID (当前段标识)",
            category: "链路追踪",
            presetValues: ["{{$randomInt(10000000, 99999999)}}"]
        ),
        HeaderDefinition(
            name: "x-b3-sampled",
            description: "Zipkin 链路采样指令 (1=采样, 0=不采样)",
            category: "链路追踪",
            presetValues: ["1", "0"]
        ),

        // 3. 认证与安全凭证 (Authentication & Security)
        HeaderDefinition(
            name: "authorization",
            description: "标准身份凭据 (Bearer Token 或 Basic Auth)",
            category: "认证鉴权",
            presetValues: ["Bearer {{jwt_token}}", "Bearer ", "Basic "]
        ),
        HeaderDefinition(
            name: "x-api-key",
            description: "服务接入密钥或网关 API Key",
            category: "认证鉴权",
            presetValues: ["{{api_key}}", "test-secret-key"]
        ),
        HeaderDefinition(
            name: "x-token",
            description: "业务系统自定义访问令牌",
            category: "认证鉴权",
            presetValues: ["{{token}}"]
        ),

        // 4. 传输与客户端环境 (Transport & Client)
        HeaderDefinition(
            name: "content-type",
            description: "数据格式编码 (gRPC 必须为 application/grpc 或其扩展)",
            category: "通用传输",
            presetValues: ["application/grpc+proto", "application/grpc", "application/json"]
        ),
        HeaderDefinition(
            name: "user-agent",
            description: "客户端环境与版本信息",
            category: "通用传输",
            presetValues: ["Pulsar/2.0 (macOS Native)", "grpc-client/1.0"]
        ),
        HeaderDefinition(
            name: "x-client-version",
            description: "客户端版本号 (用于后端灰度与向下兼容判断)",
            category: "通用传输",
            presetValues: ["2.0.0", "1.0.0"]
        ),
        HeaderDefinition(
            name: "x-forwarded-for",
            description: "HTTP / gRPC 代理透传客户端真实 IP",
            category: "通用传输",
            presetValues: ["127.0.0.1", "10.0.0.1"]
        ),
        HeaderDefinition(
            name: "x-tenant-id",
            description: "多租户系统租户唯一识别标识",
            category: "业务路由",
            presetValues: ["tenant_default", "tenant_001"]
        ),
        HeaderDefinition(
            name: "x-env",
            description: "流量染色与环境路由标签 (如 dev, staging, prod)",
            category: "业务路由",
            presetValues: ["dev", "staging", "prod"]
        )
    ]

    /// 根据输入模糊查询匹配的 Header 候选列表
    public static func search(query: String) -> [HeaderDefinition] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sharedHeaders }
        return sharedHeaders.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }
}

/// Bruno 风格 Header 批量编辑双向转换器 (Bulk Edit Converter)
public struct HeaderBulkConverter {
    /// 将 MetadataHeader 数组转换为纯文本 (格式: "key: value"，支持 "# key: value" 注释禁用)
    public static func toBulkText(headers: [MetadataHeader]) -> String {
        var lines: [String] = []
        for h in headers {
            let key = h.key.trimmingCharacters(in: .whitespaces)
            let val = h.value
            if h.isEnabled {
                lines.append("\(key): \(val)")
            } else {
                lines.append("# \(key): \(val)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 将纯文本解析为 MetadataHeader 数组
    public static func fromBulkText(_ text: String) -> [MetadataHeader] {
        var result: [MetadataHeader] = []
        let rawLines = text.components(separatedBy: .newlines)

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let isEnabled = !trimmed.starts(with: "#") && !trimmed.starts(with: "//")
            let cleanLine: String
            if trimmed.starts(with: "#") {
                cleanLine = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "//") {
                cleanLine = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else {
                cleanLine = trimmed
            }

            guard !cleanLine.isEmpty, cleanLine.contains(":") else { continue }

            // 以第一个冒号切割键值
            let parts = cleanLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            if !key.isEmpty {
                result.append(MetadataHeader(key: key, value: value, isEnabled: isEnabled))
            }
        }

        return result
    }
}
