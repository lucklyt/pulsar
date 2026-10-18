import Foundation

/// 集合自动化批量运行配置 (Collection Runner Config)
public struct CollectionRunConfig: Identifiable, Equatable, Hashable {
    public var id: UUID = UUID()
    public var collectionId: UUID
    public var folderId: UUID?
    public var collectionName: String
    public var folderName: String?
    public var delayMs: Double // 请求间隔毫秒 (0 - 2000ms)
    public var stopOnFirstFailure: Bool
    public var environmentId: UUID?

    public init(
        collectionId: UUID,
        folderId: UUID? = nil,
        collectionName: String,
        folderName: String? = nil,
        delayMs: Double = 0.0,
        stopOnFirstFailure: Bool = false,
        environmentId: UUID? = nil
    ) {
        self.collectionId = collectionId
        self.folderId = folderId
        self.collectionName = collectionName
        self.folderName = folderName
        self.delayMs = delayMs
        self.stopOnFirstFailure = stopOnFirstFailure
        self.environmentId = environmentId
    }
}

/// 单个请求用例执行结果记录
public struct RequestRunResult: Identifiable, Codable, Equatable {
    public var id: UUID
    public var requestId: UUID
    public var requestName: String
    public var serviceName: String
    public var methodName: String
    public var callType: GRPCCallType
    public var durationMs: Double
    public var statusCode: Int
    public var statusName: String
    public var assertionResults: [AssertionResult]
    public var extractedVariables: [String: String]
    public var isSuccess: Bool
    public var responsePayload: String
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        requestId: UUID,
        requestName: String,
        serviceName: String,
        methodName: String,
        callType: GRPCCallType,
        durationMs: Double,
        statusCode: Int,
        statusName: String,
        assertionResults: [AssertionResult] = [],
        extractedVariables: [String: String] = [:],
        isSuccess: Bool,
        responsePayload: String = "",
        errorMessage: String? = nil
    ) {
        self.id = id
        self.requestId = requestId
        self.requestName = requestName
        self.serviceName = serviceName
        self.methodName = methodName
        self.callType = callType
        self.durationMs = durationMs
        self.statusCode = statusCode
        self.statusName = statusName
        self.assertionResults = assertionResults
        self.extractedVariables = extractedVariables
        self.isSuccess = isSuccess
        self.responsePayload = responsePayload
        self.errorMessage = errorMessage
    }
}

/// 集合测试运行总结
public struct CollectionRunSummary: Identifiable, Codable, Equatable {
    public var id: UUID
    public var collectionName: String
    public var folderName: String?
    public var startedAt: Date
    public var completedAt: Date?
    public var results: [RequestRunResult]

    public init(
        id: UUID = UUID(),
        collectionName: String,
        folderName: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        results: [RequestRunResult] = []
    ) {
        self.id = id
        self.collectionName = collectionName
        self.folderName = folderName
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.results = results
    }

    public var totalRequests: Int { results.count }
    public var passedRequests: Int { results.filter { $0.isSuccess }.count }
    public var failedRequests: Int { results.filter { !$0.isSuccess }.count }

    public var totalAssertions: Int {
        results.reduce(0) { $0 + $1.assertionResults.count }
    }
    public var passedAssertions: Int {
        results.reduce(0) { $0 + $1.assertionResults.filter { $0.passed }.count }
    }
    public var failedAssertions: Int {
        results.reduce(0) { $0 + $1.assertionResults.filter { !$0.passed }.count }
    }

    public var totalDurationMs: Double {
        results.reduce(0.0) { $0 + $1.durationMs }
    }
    public var averageDurationMs: Double {
        results.isEmpty ? 0 : totalDurationMs / Double(results.count)
    }

    public var isAllPassed: Bool {
        !results.isEmpty && failedRequests == 0
    }

    /// 生成 Markdown 测试报告
    public func exportMarkdownReport() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let startTimeStr = df.string(from: startedAt)
        let targetTitle = folderName.map { "\(collectionName) / \($0)" } ?? collectionName

        var md = """
# Pulsar 自动化测试执行报告

- **测试目标**: `\(targetTitle)`
- **执行时间**: `\(startTimeStr)`
- **用例总数**: `\(totalRequests)` (通过: `\(passedRequests)` / 失败: `\(failedRequests)`)
- **断言总数**: `\(totalAssertions)` (通过: `\(passedAssertions)` / 失败: `\(failedAssertions)`)
- **总耗时**: `\(String(format: "%.1f", totalDurationMs)) ms` (平均: `\(String(format: "%.1f", averageDurationMs)) ms`)
- **最终结论**: \(isAllPassed ? "✅ **全部通过 (ALL PASSED)**" : "⚠️ **存在失败用例 (FAILED)**")

---

### 用例明细列表

| 状态 | 请求名称 | 方法路径 | 耗时 | 状态码 | 断言通过率 | 提取变量 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
"""

        for r in results {
            let statusIcon = r.isSuccess ? "✅" : "❌"
            let passCount = r.assertionResults.filter { $0.passed }.count
            let totalAssert = r.assertionResults.count
            let assertStr = totalAssert > 0 ? "\(passCount)/\(totalAssert)" : "-"
            let varsStr = r.extractedVariables.isEmpty ? "-" : "\(r.extractedVariables.keys.joined(separator: ", "))"
            let method = "\(r.serviceName)/\(r.methodName)"

            md += "\n| \(statusIcon) | \(r.requestName) | `\(method)` | `\(String(format: "%.1f", r.durationMs)) ms` | `\(r.statusCode)` (\(r.statusName)) | `\(assertStr)` | `\(varsStr)` |"
        }

        let failedList = results.filter { !$0.isSuccess }
        if !failedList.isEmpty {
            md += "\n\n---\n\n### 失败用例深度排查\n"
            for fail in failedList {
                md += "\n#### ❌ \(fail.requestName) (`\(fail.serviceName)/\(fail.methodName)`)\n"
                if let err = fail.errorMessage {
                    md += "- **执行错误**: `\(err)`\n"
                }
                let failedAsserts = fail.assertionResults.filter { !$0.passed }
                if !failedAsserts.isEmpty {
                    md += "- **未通过断言**:\n"
                    for fa in failedAsserts {
                        md += "  - `\(fa.expression)`: \(fa.message)\n"
                    }
                }
                if !fail.responsePayload.isEmpty {
                    md += "- **响应载荷**:\n```json\n\(fail.responsePayload)\n```\n"
                }
            }
        }

        md += "\n\n_报告由 Pulsar 2.0 原生 macOS 客户端自动生成_\n"
        return md
    }
}
