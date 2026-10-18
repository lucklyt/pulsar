import Foundation

/// 支持导出的客户端编程语言
public enum CodeLanguage: String, CaseIterable, Identifiable {
    case golang = "Go (grpc)"
    case python = "Python (grpcio)"
    case typescript = "TypeScript / Node"
    case swift = "Swift (grpc-swift)"
    case grpcurl = "grpcurl (CLI)"
    case curl = "cURL (HTTP Transcode)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .golang: return "chevron.left.forwardslash.chevron.right"
        case .python: return "shippingbox"
        case .typescript: return "curlybraces"
        case .swift: return "swift"
        case .grpcurl: return "terminal"
        case .curl: return "globe"
        }
    }
}

/// 多语言客户端代码生成引擎 (类似 Bruno / Postman Code Snippet)
public final class CodeSnippetEngine {
    public static let shared = CodeSnippetEngine()

    public init() {}

    /// 生成指定语言的生产级客户端调用代码片段
    public func generateSnippet(
        language: CodeLanguage,
        request: RequestModel,
        effectiveAddress: String,
        effectivePayload: String,
        effectiveHeaders: [MetadataHeader],
        effectiveAuth: AuthConfig,
        effectiveTLS: TLSConfig
    ) -> String {
        switch language {
        case .golang:
            return generateGoSnippet(
                request: request,
                address: effectiveAddress,
                payload: effectivePayload,
                headers: effectiveHeaders,
                auth: effectiveAuth,
                tls: effectiveTLS
            )
        case .python:
            return generatePythonSnippet(
                request: request,
                address: effectiveAddress,
                payload: effectivePayload,
                headers: effectiveHeaders,
                auth: effectiveAuth,
                tls: effectiveTLS
            )
        case .typescript:
            return generateTypeScriptSnippet(
                request: request,
                address: effectiveAddress,
                payload: effectivePayload,
                headers: effectiveHeaders,
                auth: effectiveAuth,
                tls: effectiveTLS
            )
        case .swift:
            return generateSwiftSnippet(
                request: request,
                address: effectiveAddress,
                payload: effectivePayload,
                headers: effectiveHeaders,
                auth: effectiveAuth,
                tls: effectiveTLS
            )
        case .grpcurl:
            return GrpcurlExporter.shared.export(
                request: request,
                resolvedAddress: effectiveAddress,
                resolvedPayload: effectivePayload
            )
        case .curl:
            return generateCurlSnippet(
                request: request,
                address: effectiveAddress,
                payload: effectivePayload,
                headers: effectiveHeaders,
                auth: effectiveAuth
            )
        }
    }

    // MARK: - Go

    private func generateGoSnippet(
        request: RequestModel,
        address: String,
        payload: String,
        headers: [MetadataHeader],
        auth: AuthConfig,
        tls: TLSConfig
    ) -> String {
        let isTLS = (tls.mode != .plaintext && tls.mode != .inherit)
        let methodPath = "/\(request.serviceName)/\(request.methodName)"
        let timeout = Int(request.timeoutSeconds > 0 ? request.timeoutSeconds : 15)

        var headerLines: [String] = []
        for h in headers where h.isEnabled && !h.key.isEmpty {
            let escVal = h.value.replacingOccurrences(of: "\"", with: "\\\"")
            headerLines.append("\t\t\"\(h.key.lowercased())\": \"\(escVal)\",")
        }
        if auth.type == .bearer && !auth.bearerToken.isEmpty {
            headerLines.append("\t\t\"authorization\": \"Bearer \(auth.bearerToken)\",")
        } else if auth.type == .apiKey && !auth.apiKeyName.isEmpty && !auth.apiKeyValue.isEmpty {
            headerLines.append("\t\t\"\(auth.apiKeyName.lowercased())\": \"\(auth.apiKeyValue)\",")
        }

        let headersBlock = headerLines.isEmpty ? "" : """

\t// 附加 Metadata 请求头
\tmd := metadata.New(map[string]string{
\(headerLines.joined(separator: "\n"))
\t})
\tctx = metadata.NewOutgoingContext(ctx, md)
"""

        let credsImport = isTLS ? "\"google.golang.org/grpc/credentials\"" : "\"google.golang.org/grpc/credentials/insecure\""
        let credsSetup = isTLS ? "credentials.NewClientTLSFromCert(nil, \"\")" : "insecure.NewCredentials()"

        return """
package main

import (
\t"context"
\t"fmt"
\t"log"
\t"time"

\t"google.golang.org/grpc"
\t\(credsImport)
\t"google.golang.org/grpc/metadata"
)

func main() {
\ttarget := "\(address)"

\t// 1. 初始化 gRPC 连接通道
\tconn, err := grpc.NewClient(
\t\ttarget,
\t\tgrpc.WithTransportCredentials(\(credsSetup)),
\t)
\tif err != nil {
\t\tlog.Fatalf("无法连接到 gRPC 服务: %v", err)
\t}
\tdefer conn.Close()

\t// 2. 超时上下文与 Metadata
\tctx, cancel := context.WithTimeout(context.Background(), \(timeout)*time.Second)
\tdefer cancel()
\(headersBlock)

\t// 3. 执行 RPC 方法调用
\t// 方法路径: \(methodPath)
\trawPayload := []byte(`\(payload.trimmingCharacters(in: .whitespacesAndNewlines))`)
\tvar rawResponse []byte

\terr = conn.Invoke(ctx, "\(methodPath)", rawPayload, &rawResponse)
\tif err != nil {
\t\tlog.Fatalf("RPC 调用失败: %v", err)
\t}

\tfmt.Printf("RPC 响应成功: %s\\n", string(rawResponse))
}
"""
    }

    // MARK: - Python

    private func generatePythonSnippet(
        request: RequestModel,
        address: String,
        payload: String,
        headers: [MetadataHeader],
        auth: AuthConfig,
        tls: TLSConfig
    ) -> String {
        let isTLS = (tls.mode != .plaintext && tls.mode != .inherit)
        let methodPath = "/\(request.serviceName)/\(request.methodName)"
        let timeout = Int(request.timeoutSeconds > 0 ? request.timeoutSeconds : 15)

        var headerTuples: [String] = []
        for h in headers where h.isEnabled && !h.key.isEmpty {
            let escVal = h.value.replacingOccurrences(of: "\"", with: "\\\"")
            headerTuples.append("        (\"\(h.key.lowercased())\", \"\(escVal)\"),")
        }
        if auth.type == .bearer && !auth.bearerToken.isEmpty {
            headerTuples.append("        (\"authorization\", \"Bearer \(auth.bearerToken)\"),")
        } else if auth.type == .apiKey && !auth.apiKeyName.isEmpty && !auth.apiKeyValue.isEmpty {
            headerTuples.append("        (\"\(auth.apiKeyName.lowercased())\", \"\(auth.apiKeyValue)\"),")
        }

        let metadataStr = headerTuples.isEmpty ? "    metadata = []" : "    metadata = [\n\(headerTuples.joined(separator: "\n"))\n    ]"
        let channelCall = isTLS ? "grpc.secure_channel(target, grpc.ssl_channel_credentials())" : "grpc.insecure_channel(target)"

        return """
import grpc
import json

def run_grpc_request():
    target = "\(address)"
    method = "\(methodPath)"
    timeout_sec = \(timeout)

\(metadataStr)

    # 1. 建立 gRPC 通道
    with \(channelCall) as channel:
        # 2. 构造通用单问单答 (Unary) 调用
        call = channel.unary_unary(
            method,
            request_serializer=lambda b: b if isinstance(b, bytes) else str(b).encode('utf-8'),
            response_deserializer=lambda b: b.decode('utf-8')
        )

        payload_str = json.dumps(\(payload.trimmingCharacters(in: .whitespacesAndNewlines)))

        try:
            print(f"正在发送请求至 {target}{method} ...")
            response, call_details = call.with_call(
                payload_str,
                timeout=timeout_sec,
                metadata=metadata
            )
            print(f"调用成功 (Code: {call_details.code()})")
            print("响应结果:")
            print(response)
        except grpc.RpcError as e:
            print(f"RPC 调用失败: {e.code()} - {e.details()}")

if __name__ == "__main__":
    run_grpc_request()
"""
    }

    // MARK: - TypeScript / Node.js

    private func generateTypeScriptSnippet(
        request: RequestModel,
        address: String,
        payload: String,
        headers: [MetadataHeader],
        auth: AuthConfig,
        tls: TLSConfig
    ) -> String {
        let isTLS = (tls.mode != .plaintext && tls.mode != .inherit)
        let methodPath = "/\(request.serviceName)/\(request.methodName)"
        let timeout = Int(request.timeoutSeconds > 0 ? request.timeoutSeconds : 15)

        var headerLines: [String] = []
        for h in headers where h.isEnabled && !h.key.isEmpty {
            let escVal = h.value.replacingOccurrences(of: "\"", with: "\\\"")
            headerLines.append("  metadata.add('\(h.key.lowercased())', '\(escVal)');")
        }
        if auth.type == .bearer && !auth.bearerToken.isEmpty {
            headerLines.append("  metadata.add('authorization', 'Bearer \(auth.bearerToken)');")
        } else if auth.type == .apiKey && !auth.apiKeyName.isEmpty && !auth.apiKeyValue.isEmpty {
            headerLines.append("  metadata.add('\(auth.apiKeyName.lowercased())', '\(auth.apiKeyValue)');")
        }

        let creds = isTLS ? "grpc.credentials.createSsl()" : "grpc.credentials.createInsecure()"

        return """
import * as grpc from '@grpc/grpc-js';

async function invokeGRPC() {
  const target = '\(address)';
  const method = '\(methodPath)';
  const client = new grpc.Client(target, \(creds));

  // 1. 设置 Metadata 请求头
  const metadata = new grpc.Metadata();
\(headerLines.joined(separator: "\n"))

  // 2. 载荷数据
  const payloadData = Buffer.from(JSON.stringify(\(payload.trimmingCharacters(in: .whitespacesAndNewlines))));
  const deadline = Date.now() + \(timeout) * 1000;

  console.log(`调用服务: ${target}${method} ...`);

  client.makeUnaryRequest(
    method,
    (arg: Buffer) => arg,
    (arg: Buffer) => arg.toString(),
    payloadData,
    metadata,
    { deadline },
    (error, response) => {
      if (error) {
        console.error('RPC 执行失败:', error.message, `(Code: ${error.code})`);
      } else {
        console.log('RPC 响应成功:');
        console.log(response);
      }
      client.close();
    }
  );
}

invokeGRPC();
"""
    }

    // MARK: - Swift

    private func generateSwiftSnippet(
        request: RequestModel,
        address: String,
        payload: String,
        headers: [MetadataHeader],
        auth: AuthConfig,
        tls: TLSConfig
    ) -> String {
        let methodPath = "/\(request.serviceName)/\(request.methodName)"
        let timeout = Int(request.timeoutSeconds > 0 ? request.timeoutSeconds : 15)

        var headerDict: [String: String] = [:]
        for h in headers where h.isEnabled && !h.key.isEmpty {
            headerDict[h.key.lowercased()] = h.value
        }
        if auth.type == .bearer && !auth.bearerToken.isEmpty {
            headerDict["authorization"] = "Bearer \(auth.bearerToken)"
        } else if auth.type == .apiKey && !auth.apiKeyName.isEmpty && !auth.apiKeyValue.isEmpty {
            headerDict[auth.apiKeyName.lowercased()] = auth.apiKeyValue
        }

        return """
import Foundation

// 基于 Swift 原生异步并发进行 gRPC / HTTP2 调用
func sendGRPCRequest() async throws {
    let target = "\(address)"
    let methodPath = "\(methodPath)"
    let timeoutSeconds: TimeInterval = \(timeout)

    // 1. 构造 Metadata 请求头
    let headers: [String: String] = [
\(headerDict.map { "        \"\($0.key)\": \"\($0.value)\"" }.joined(separator: ",\n"))
    ]

    // 2. 序列化 JSON 载荷
    let jsonString = \"\"\"
\(payload.trimmingCharacters(in: .whitespacesAndNewlines))
\"\"\"
    guard let payloadData = jsonString.data(using: .utf8) else {
        throw URLError(.cannotDecodeRawData)
    }

    print("发起 gRPC 请求: \\(target)\\(methodPath)")
    print("附加请求头: \\(headers.count) 项，载荷字节数: \\(payloadData.count)")

    // 3. 执行调用 (可使用 PulsarCore 的 GRPCClientEngine 或官方 grpc-swift 客户端)
    // let response = try await client.call(method: methodPath, payload: payloadData)
}
"""
    }

    // MARK: - cURL (HTTP Transcoding)

    private func generateCurlSnippet(
        request: RequestModel,
        address: String,
        payload: String,
        headers: [MetadataHeader],
        auth: AuthConfig
    ) -> String {
        var args: [String] = [
            "curl -X POST",
            "\"http://\(address)/\(request.serviceName)/\(request.methodName)\"",
            "-H \"Content-Type: application/json\""
        ]

        for h in headers where h.isEnabled && !h.key.isEmpty {
            let escVal = h.value.replacingOccurrences(of: "\"", with: "\\\"")
            args.append("-H \"\(h.key): \(escVal)\"")
        }

        if auth.type == .bearer && !auth.bearerToken.isEmpty {
            args.append("-H \"Authorization: Bearer \(auth.bearerToken)\"")
        } else if auth.type == .apiKey && !auth.apiKeyName.isEmpty && !auth.apiKeyValue.isEmpty {
            args.append("-H \"\(auth.apiKeyName): \(auth.apiKeyValue)\"")
        }

        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPayload.isEmpty && trimmedPayload != "{}" {
            let flattened = trimmedPayload
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "'", with: "'\\''")
            args.append("-d '\(flattened)'")
        }

        return args.joined(separator: " \\\n  ")
    }
}
