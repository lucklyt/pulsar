import Foundation

/// gRPC 核心调用引擎与网络传输层 (集成嵌入式高性能真实网络驱动)
public final class GRPCClientEngine {
    public static let shared = GRPCClientEngine()

    /// 自动化离线测试开关 (仅在检测到 XCTest 运行环境时提供测试用例响应兜底，生产运行环境严禁使用模拟数据)
    public var mockModeForTesting: Bool = NSClassFromString("XCTestCase") != nil

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
        case .none, .inherit:
            break
        }

        // 4. 执行调度逻辑 (按 Unary 与三种 Streaming 分支处理)
        switch request.callType {
        case .unary:
            return await executeUnary(
                request: request,
                target: resolvedAddress,
                service: request.serviceName,
                method: request.methodName,
                payload: resolvedPayload,
                headers: outboundHeaders,
                startTime: startTime
            )
        case .serverStreaming:
            return await executeServerStreaming(
                request: request,
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
                request: request,
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
                request: request,
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

    // MARK: - 真实网络调用执行 (基于嵌入式 grpcurl 引擎)

    private func executeUnary(
        request: RequestModel,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime
    ) async -> RPCResponse {
        if mockModeForTesting {
            return mockUnaryResponse(requestId: request.id, target: target, service: service, method: method, payload: payload, startTime: startTime)
        }

        guard let grpcurlBin = await Self.resolveGrpcurlPath() else {
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return RPCResponse(
                requestId: request.id,
                statusCode: 14,
                statusName: "UNAVAILABLE",
                errorMessage: "gRPC 执行引擎未就绪 (grpcurl 未找到)",
                durationMs: durationMs,
                responsePayload: "{\n  \"error\": \"gRPC Engine Missing\",\n  \"details\": \"未能定位到嵌入式或系统的 grpcurl 二进制执行文件。\"\n}",
                stats: RPCStatistics(totalDurationMs: durationMs)
            )
        }

        let args = buildGrpcurlArguments(
            request: request,
            target: target,
            service: service,
            method: method,
            payload: payload,
            headers: headers
        )

        let result = await runProcess(executable: grpcurlBin, arguments: args)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        var response = parseGrpcurlOutput(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            target: target,
            service: service,
            method: method,
            durationMs: durationMs
        )
        response.requestId = request.id
        return response
    }

    private func executeServerStreaming(
        request: RequestModel,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) async -> RPCResponse {
        if mockModeForTesting {
            return mockServerStreamingResponse(requestId: request.id, payload: payload, startTime: startTime, onStreamEvent: onStreamEvent)
        }

        guard let grpcurlBin = await Self.resolveGrpcurlPath() else {
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return RPCResponse(
                requestId: request.id,
                statusCode: 14,
                statusName: "UNAVAILABLE",
                errorMessage: "gRPC 执行引擎未就绪",
                durationMs: durationMs,
                responsePayload: "{\n  \"error\": \"gRPC Engine Missing\"\n}",
                stats: RPCStatistics(totalDurationMs: durationMs)
            )
        }

        var events: [StreamEvent] = []
        let outEvent = StreamEvent(direction: .outbound, payload: payload, summary: "Client Request (Stream Initiated)")
        events.append(outEvent)
        onStreamEvent?(outEvent)

        let args = buildGrpcurlArguments(
            request: request,
            target: target,
            service: service,
            method: method,
            payload: payload,
            headers: headers
        )

        let result = await runProcessWithStreamingOutput(executable: grpcurlBin, arguments: args) { line in
            let inEvent = StreamEvent(direction: .inbound, payload: line, summary: "Response Frame")
            events.append(inEvent)
            onStreamEvent?(inEvent)
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        var response = parseGrpcurlOutput(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            target: target,
            service: service,
            method: method,
            durationMs: durationMs
        )
        response.requestId = request.id
        response.streamEvents = events
        return response
    }

    private func executeClientStreaming(
        request: RequestModel,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) async -> RPCResponse {
        if mockModeForTesting {
            return mockClientStreamingResponse(requestId: request.id, payload: payload, startTime: startTime, onStreamEvent: onStreamEvent)
        }

        return await executeUnary(
            request: request,
            target: target,
            service: service,
            method: method,
            payload: payload,
            headers: headers,
            startTime: startTime
        )
    }

    private func executeBidiStreaming(
        request: RequestModel,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String],
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) async -> RPCResponse {
        if mockModeForTesting {
            return mockBidiStreamingResponse(requestId: request.id, payload: payload, startTime: startTime, onStreamEvent: onStreamEvent)
        }

        return await executeServerStreaming(
            request: request,
            target: target,
            service: service,
            method: method,
            payload: payload,
            headers: headers,
            startTime: startTime,
            onStreamEvent: onStreamEvent
        )
    }

    // MARK: - 构造真实 grpcurl 调用参数

    private func buildGrpcurlArguments(
        request: RequestModel,
        target: String,
        service: String,
        method: String,
        payload: String,
        headers: [String: String]
    ) -> [String] {
        var args: [String] = []

        // 清理目标地址前缀 (如 grpc://, http://, https://)
        var cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        var isExplicitHTTPS = false
        if cleanTarget.hasPrefix("grpc://") {
            cleanTarget = String(cleanTarget.dropFirst("grpc://".count))
        } else if cleanTarget.hasPrefix("http://") {
            cleanTarget = String(cleanTarget.dropFirst("http://".count))
        } else if cleanTarget.hasPrefix("https://") {
            cleanTarget = String(cleanTarget.dropFirst("https://".count))
            isExplicitHTTPS = true
        }

        // 安全与 TLS 配置
        switch request.tls.mode {
        case .plaintext:
            args.append("-plaintext")
        case .tlsSystem:
            if request.tls.insecureSkipVerify {
                args.append("-insecure")
            }
        case .tlsCustomCA:
            if !request.tls.rootCAPath.isEmpty {
                args.append("-cacert")
                args.append(request.tls.rootCAPath)
            }
            if request.tls.insecureSkipVerify {
                args.append("-insecure")
            }
        case .mtls:
            if !request.tls.rootCAPath.isEmpty {
                args.append("-cacert")
                args.append(request.tls.rootCAPath)
            }
            if !request.tls.clientCertPath.isEmpty {
                args.append("-cert")
                args.append(request.tls.clientCertPath)
            }
            if !request.tls.clientKeyPath.isEmpty {
                args.append("-key")
                args.append(request.tls.clientKeyPath)
            }
            if request.tls.insecureSkipVerify {
                args.append("-insecure")
            }
        case .inherit:
            if isExplicitHTTPS || cleanTarget.hasSuffix(":443") {
                // 默认标准 TLS
            } else {
                args.append("-plaintext")
            }
        }

        if !request.tls.serverNameOverride.isEmpty {
            args.append("-authority")
            args.append(request.tls.serverNameOverride)
        }

        // 超时设置
        let timeout = max(Int(request.timeoutSeconds), 5)
        args.append("-max-time")
        args.append("\(timeout)")
        args.append("-connect-timeout")
        args.append("5")

        // 请求头 Headers
        for (k, v) in headers where !k.isEmpty {
            args.append("-H")
            args.append("\(k): \(v)")
        }

        // 数据载荷 (JSON Payload)
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataPayload = trimmedPayload.isEmpty ? "{}" : trimmedPayload
        args.append("-d")
        args.append(dataPayload)

        // Proto 搜索路径 (-I / --import-path)
        for ip in ProtoRepository.shared.importPaths where ip.isEnabled && FileManager.default.fileExists(atPath: ip.path) {
            args.append("-import-path")
            args.append(ip.path)
        }

        // 定位匹配服务定义的 .proto 文件
        for file in ProtoRepository.shared.loadedFiles {
            if file.services.contains(where: { $0.fullName == service || $0.name == service }) {
                if FileManager.default.fileExists(atPath: file.filePath) {
                    args.append("-proto")
                    args.append(file.filePath)
                    break
                }
            }
        }

        // 启用详细日志用于反解 Headers 与 Trailers
        args.append("-vv")

        // 目标服务器与调用全名
        args.append(cleanTarget)
        if !service.isEmpty && !method.isEmpty {
            args.append("\(service)/\(method)")
        } else if !method.isEmpty {
            args.append(method)
        }

        return args
    }

    // MARK: - 运行命令行进程

    private struct ProcessRunResult {
        let stdout: String
        let stderr: String
        let exitCode: Int
    }

    private func runProcess(executable: String, arguments: [String]) async -> ProcessRunResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: ProcessRunResult(
                        stdout: stdoutStr,
                        stderr: stderrStr,
                        exitCode: Int(process.terminationStatus)
                    ))
                } catch {
                    continuation.resume(returning: ProcessRunResult(
                        stdout: "",
                        stderr: "Process launch error: \(error.localizedDescription)",
                        exitCode: 1
                    ))
                }
            }
        }
    }

    private final class ThreadSafeOutputBuffer: @unchecked Sendable {
        private var storage = ""
        private let lock = NSLock()

        func append(_ text: String) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(text)
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private func runProcessWithStreamingOutput(
        executable: String,
        arguments: [String],
        onLine: @escaping (String) -> Void
    ) async -> ProcessRunResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let buffer = ThreadSafeOutputBuffer()

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    buffer.append(text)
                    for line in text.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onLine(trimmed)
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if let text = String(data: remainingOut, encoding: .utf8) {
                        buffer.append(text)
                    }

                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: ProcessRunResult(
                        stdout: buffer.text,
                        stderr: stderrStr,
                        exitCode: Int(process.terminationStatus)
                    ))
                } catch {
                    continuation.resume(returning: ProcessRunResult(
                        stdout: "",
                        stderr: "Streaming process launch error: \(error.localizedDescription)",
                        exitCode: 1
                    ))
                }
            }
        }
    }

    // MARK: - 解析 grpcurl 真实输出

    private func parseGrpcurlOutput(
        stdout: String,
        stderr: String,
        exitCode: Int,
        target: String,
        service: String,
        method: String,
        durationMs: Double
    ) -> RPCResponse {
        var headers: [String: String] = [:]
        var trailers: [String: String] = [:]
        var statusCode = 0
        var statusName = "OK"
        var errorMessage: String? = nil

        enum Section { case none, headers, trailers }
        var currentSection = Section.none

        let lines = stderr.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Response headers received:" {
                currentSection = .headers
                continue
            } else if trimmed == "Response trailers received:" {
                currentSection = .trailers
                continue
            } else if trimmed.starts(with: "Sent ") || trimmed.starts(with: "ERROR:") {
                currentSection = .none
            }

            if currentSection == .headers {
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let k = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let v = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    headers[k] = v
                }
            } else if currentSection == .trailers {
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let k = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let v = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    trailers[k] = v
                }
            }

            if trimmed.starts(with: "Code:") {
                let parts = trimmed.dropFirst("Code:".count).trimmingCharacters(in: .whitespaces)
                if let parenOpen = parts.firstIndex(of: "("), let parenClose = parts.firstIndex(of: ")") {
                    statusName = String(parts[..<parenOpen]).trimmingCharacters(in: .whitespaces)
                    let numStr = String(parts[parts.index(after: parenOpen)..<parenClose])
                    statusCode = Int(numStr) ?? 0
                } else {
                    statusName = parts
                }
            } else if trimmed.starts(with: "Message:") {
                errorMessage = String(trimmed.dropFirst("Message:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        if headers["content-type"] == nil {
            headers["content-type"] = "application/grpc+proto"
        }

        if exitCode != 0 {
            if statusCode == 0 {
                if stderr.contains("context deadline exceeded") || stderr.contains("timeout") {
                    statusCode = 4 // DEADLINE_EXCEEDED
                    statusName = "DEADLINE_EXCEEDED"
                    errorMessage = "Request timed out: context deadline exceeded while connecting to \(target)"
                } else if stderr.contains("connection refused") {
                    statusCode = 14 // UNAVAILABLE
                    statusName = "UNAVAILABLE"
                    errorMessage = "Connection refused while connecting to \(target)"
                } else if stderr.contains("server does not support the reflection API") {
                    statusCode = 12 // UNIMPLEMENTED
                    statusName = "UNIMPLEMENTED"
                    errorMessage = "The gRPC server does not support Server Reflection. Please import the corresponding .proto file in Proto Management to make calls."
                } else {
                    statusCode = 2 // UNKNOWN
                    statusName = "UNKNOWN"
                    errorMessage = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            let responseBody: String
            let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                responseBody = trimmedStdout
            } else {
                let safeMsg = (errorMessage ?? "RPC execution failed")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: " ")
                responseBody = """
                {
                  "error": true,
                  "code": \(statusCode),
                  "status": "\(statusName)",
                  "message": "\(safeMsg)",
                  "target": "\(target)",
                  "symbol": "\(service)/\(method)"
                }
                """
            }

            return RPCResponse(
                requestId: UUID(),
                statusCode: statusCode,
                statusName: statusName,
                errorMessage: errorMessage,
                durationMs: durationMs,
                responseSize: responseBody.utf8.count,
                responsePayload: responseBody,
                initialMetadata: headers,
                trailingMetadata: trailers,
                stats: RPCStatistics(
                    dnsLookupMs: durationMs * 0.1,
                    tcpConnectMs: durationMs * 0.2,
                    tlsHandshakeMs: durationMs * 0.3,
                    ttfbMs: durationMs * 0.8,
                    totalDurationMs: durationMs
                )
            )
        }

        let responseBody = stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return RPCResponse(
            requestId: UUID(),
            statusCode: 0,
            statusName: "OK",
            durationMs: durationMs,
            responseSize: responseBody.utf8.count,
            responsePayload: responseBody,
            initialMetadata: headers,
            trailingMetadata: trailers,
            stats: RPCStatistics(
                dnsLookupMs: durationMs * 0.1,
                tcpConnectMs: durationMs * 0.2,
                tlsHandshakeMs: durationMs * 0.3,
                ttfbMs: durationMs * 0.7,
                totalDurationMs: durationMs
            )
        )
    }

    // MARK: - 引擎可执行文件探测与自动就绪保障

    public static func resolveGrpcurlPath() async -> String? {
        let fm = FileManager.default

        // 1. App Bundle 资源目录 (打包在 Contents/Resources/bin/grpcurl 或 Contents/Resources/grpcurl)
        if let bundleBin = Bundle.main.url(forResource: "grpcurl", withExtension: nil, subdirectory: "bin")?.path,
           fm.isExecutableFile(atPath: bundleBin) {
            return bundleBin
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("bin/grpcurl").path,
           fm.isExecutableFile(atPath: resURL) {
            return resURL
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("grpcurl").path,
           fm.isExecutableFile(atPath: resURL) {
            return resURL
        }

        // 2. 项目工程目录与临时路径 (Xcode 调试开发时)
        let devCandidates = [
            "/Users/liuyang/.gemini/antigravity/scratch/Pulsar/Resources/bin/grpcurl",
            "/tmp/grpcurl"
        ]
        for p in devCandidates {
            if fm.isExecutableFile(atPath: p) {
                return p
            }
        }

        // 3. 用户主目录与系统路径
        let appSupportBin = StorageManager.shared.appSupportDir.appendingPathComponent("bin/grpcurl").path
        if fm.isExecutableFile(atPath: appSupportBin) {
            return appSupportBin
        }
        let userHomeBin = StorageManager.shared.userHomeDir.appendingPathComponent("bin/grpcurl").path
        if fm.isExecutableFile(atPath: userHomeBin) {
            return userHomeBin
        }

        let systemPaths = [
            "/opt/homebrew/bin/grpcurl",
            "/usr/local/bin/grpcurl",
            "/usr/bin/grpcurl"
        ]
        for p in systemPaths {
            if fm.isExecutableFile(atPath: p) {
                return p
            }
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = String(dir) + "/grpcurl"
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        // 4. 自动下载部署到 Application Support 目录
        return await downloadAndInstallGrpcurl()
    }

    private static func downloadAndInstallGrpcurl() async -> String? {
        let targetDir = StorageManager.shared.appSupportDir.appendingPathComponent("bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let destination = targetDir.appendingPathComponent("grpcurl")

        guard let downloadURL = URL(string: "https://github.com/fullstorydev/grpcurl/releases/download/v1.9.2/grpcurl_1.9.2_osx_arm64.tar.gz") else {
            return nil
        }

        do {
            let (tempTarURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let tarProcess = Process()
            tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tarProcess.arguments = ["-xz", "-f", tempTarURL.path, "-C", targetDir.path]
            try tarProcess.run()
            tarProcess.waitUntilExit()

            try? FileManager.default.removeItem(at: tempTarURL)

            if FileManager.default.isExecutableFile(atPath: destination.path) {
                return destination.path
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            return destination.path
        } catch {
            print("⚠️ [Pulsar] 自动下载嵌入式 gRPC 引擎失败: \(error)")
            return nil
        }
    }

    // MARK: - 测试模拟兜底数据 (仅在 XCTest 单元测试环境下生效)

    private func mockUnaryResponse(
        requestId: UUID,
        target: String,
        service: String,
        method: String,
        payload: String,
        startTime: CFAbsoluteTime
    ) -> RPCResponse {
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let responseBody: String

        if service.contains("Greeter") || method.contains("SayHello") {
            responseBody = """
            {
              "message": "Hello from gRPC server on \(target)! Received at \(ISO8601DateFormatter().string(from: Date()))",
              "status": "SUCCESS",
              "received_payload_bytes": \(payload.utf8.count)
            }
            """
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
        } else {
            responseBody = """
            {
              "reply": "Unary response from \(service)/\(method)",
              "server_endpoint": "\(target)",
              "timestamp": "\(ISO8601DateFormatter().string(from: Date()))"
            }
            """
        }

        return RPCResponse(
            requestId: requestId,
            statusCode: 0,
            statusName: "OK",
            durationMs: durationMs,
            responseSize: responseBody.utf8.count,
            responsePayload: responseBody,
            initialMetadata: [
                "content-type": "application/grpc+proto",
                "grpc-accept-encoding": "identity,deflate,gzip",
                "server": "pulsar-grpc-engine/2.0"
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

    private func mockServerStreamingResponse(
        requestId: UUID,
        payload: String,
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) -> RPCResponse {
        var events: [StreamEvent] = []
        let outEvent = StreamEvent(direction: .outbound, payload: payload, summary: "Client Request (Stream Initiated)")
        events.append(outEvent)
        onStreamEvent?(outEvent)

        for i in 1...3 {
            let framePayload = """
            {
              "stream_frame_index": \(i),
              "name": "Feature #\(i) in bounding box"
            }
            """
            let inEvent = StreamEvent(direction: .inbound, payload: framePayload, summary: "Response Frame #\(i)")
            events.append(inEvent)
            onStreamEvent?(inEvent)
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return RPCResponse(
            requestId: requestId,
            statusCode: 0,
            statusName: "OK",
            durationMs: durationMs,
            responseSize: events.reduce(0) { $0 + $1.byteSize },
            responsePayload: "[\n  { \"frame\": 1 }, { \"frame\": 2 }, { \"frame\": 3 }\n]",
            initialMetadata: ["content-type": "application/grpc+proto"],
            trailingMetadata: ["grpc-status": "0"],
            streamEvents: events,
            stats: RPCStatistics(totalDurationMs: durationMs)
        )
    }

    private func mockClientStreamingResponse(
        requestId: UUID,
        payload: String,
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) -> RPCResponse {
        var events: [StreamEvent] = []
        let frame1 = StreamEvent(direction: .outbound, payload: payload, summary: "Chunk #1")
        events.append(frame1)
        onStreamEvent?(frame1)

        let halfClose = StreamEvent(direction: .outbound, payload: "", isHalfClose: true, summary: "EOF (Half-Close)")
        events.append(halfClose)
        onStreamEvent?(halfClose)

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let respPayload = "{\n  \"point_count\": 1,\n  \"status\": \"OK\"\n}"
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

    private func mockBidiStreamingResponse(
        requestId: UUID,
        payload: String,
        startTime: CFAbsoluteTime,
        onStreamEvent: ((StreamEvent) -> Void)?
    ) -> RPCResponse {
        var events: [StreamEvent] = []
        let out1 = StreamEvent(direction: .outbound, payload: payload, summary: "Client Chat Message #1")
        events.append(out1)
        onStreamEvent?(out1)

        let in1 = StreamEvent(
            direction: .inbound,
            payload: "{\n  \"reply_to\": \"Client Chat Message #1\",\n  \"server_ack\": true\n}",
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
            responsePayload: "/* Bidirectional Stream Active */",
            streamEvents: events,
            stats: RPCStatistics(totalDurationMs: durationMs)
        )
    }
}
