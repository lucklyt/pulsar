import Foundation

/// 将 gRPC 请求导出为标准 grpcurl 命令行，便于终端调试或在 CI/CD 中复现
public final class GrpcurlExporter {
    public static let shared = GrpcurlExporter()

    public func export(
        request: RequestModel,
        resolvedAddress: String,
        resolvedPayload: String,
        headers: [MetadataHeader]? = nil,
        auth: AuthConfig? = nil,
        tls: TLSConfig? = nil,
        importPaths: [String] = [],
        protoFile: String? = nil
    ) -> String {
        let effTLS = tls ?? request.tls
        let effHeaders = headers ?? request.metadata
        let effAuth = auth ?? request.auth

        var args: [String] = ["grpcurl"]

        // 1. Import Paths 与 Proto 文件指定 (对应 protoc -I)
        for ip in importPaths where !ip.isEmpty {
            args.append("-import-path \"\(ip)\"")
        }
        if let pf = protoFile, !pf.isEmpty {
            args.append("-proto \"\(pf)\"")
        }

        // 2. 安全配置
        switch effTLS.mode {
        case .plaintext, .inherit:
            args.append("-plaintext")
        case .tlsSystem:
            if effTLS.insecureSkipVerify {
                args.append("-insecure")
            }
        case .tlsCustomCA:
            if !effTLS.rootCAPath.isEmpty {
                args.append("-cacert \"\(effTLS.rootCAPath)\"")
            }
            if effTLS.insecureSkipVerify {
                args.append("-insecure")
            }
        case .mtls:
            if !effTLS.rootCAPath.isEmpty {
                args.append("-cacert \"\(effTLS.rootCAPath)\"")
            }
            if !effTLS.clientCertPath.isEmpty {
                args.append("-cert \"\(effTLS.clientCertPath)\"")
            }
            if !effTLS.clientKeyPath.isEmpty {
                args.append("-key \"\(effTLS.clientKeyPath)\"")
            }
        }

        if !effTLS.serverNameOverride.isEmpty {
            args.append("-authority \"\(effTLS.serverNameOverride)\"")
        }

        // 2. 超时配置
        if request.timeoutSeconds > 0 {
            args.append("-max-time \(Int(request.timeoutSeconds))")
        }

        // 3. Metadata 请求头
        for header in effHeaders where header.isEnabled && !header.key.isEmpty {
            let escapedVal = header.value.replacingOccurrences(of: "\"", with: "\\\"")
            args.append("-H \"\(header.key): \(escapedVal)\"")
        }

        // 4. 身份验证
        switch effAuth.type {
        case .bearer:
            if !effAuth.bearerToken.isEmpty {
                args.append("-H \"authorization: Bearer \(effAuth.bearerToken)\"")
            }
        case .apiKey:
            if !effAuth.apiKeyName.isEmpty && !effAuth.apiKeyValue.isEmpty {
                args.append("-H \"\(effAuth.apiKeyName): \(effAuth.apiKeyValue)\"")
            }
        case .basic:
            if !effAuth.username.isEmpty {
                let combo = "\(effAuth.username):\(effAuth.password)"
                let base64 = Data(combo.utf8).base64EncodedString()
                args.append("-H \"authorization: Basic \(base64)\"")
            }
        case .none, .inherit:
            break
        }

        // 5. 数据载荷 (JSON Payload)
        let trimmedPayload = resolvedPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPayload.isEmpty && trimmedPayload != "{}" {
            // 单行压缩以便于 shell 参数传递
            let flattened = trimmedPayload
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "'", with: "'\\''")
            args.append("-d '\(flattened)'")
        }

        // 6. 目标地址
        args.append(resolvedAddress)

        // 7. 服务/方法全名
        if !request.serviceName.isEmpty && !request.methodName.isEmpty {
            args.append("\(request.serviceName)/\(request.methodName)")
        } else if !request.methodName.isEmpty {
            args.append(request.methodName)
        }

        return args.joined(separator: " \\\n  ")
    }
}
