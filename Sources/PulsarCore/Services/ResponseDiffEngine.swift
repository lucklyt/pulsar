import Foundation

/// 差异行类型
public enum DiffLineKind: String, Codable, Equatable {
    case unchanged = " "
    case added = "+"
    case removed = "-"
}

/// 单条差异行信息
public struct DiffLine: Identifiable, Equatable {
    public var id = UUID()
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var content: String
    public var kind: DiffLineKind

    public init(oldLineNumber: Int?, newLineNumber: Int?, content: String, kind: DiffLineKind) {
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
        self.kind = kind
    }
}

/// 响应对比全面评估报告
public struct ResponseDiffReport: Equatable {
    public var baselineResponse: RPCResponse
    public var currentResponse: RPCResponse
    public var lines: [DiffLine]
    public var addedCount: Int
    public var removedCount: Int
    public var isIdentical: Bool
    public var latencyDeltaMs: Double
    public var sizeDeltaBytes: Int
    public var statusCodeChanged: Bool

    public init(
        baselineResponse: RPCResponse,
        currentResponse: RPCResponse,
        lines: [DiffLine],
        addedCount: Int,
        removedCount: Int,
        isIdentical: Bool,
        latencyDeltaMs: Double,
        sizeDeltaBytes: Int,
        statusCodeChanged: Bool
    ) {
        self.baselineResponse = baselineResponse
        self.currentResponse = currentResponse
        self.lines = lines
        self.addedCount = addedCount
        self.removedCount = removedCount
        self.isIdentical = isIdentical
        self.latencyDeltaMs = latencyDeltaMs
        self.sizeDeltaBytes = sizeDeltaBytes
        self.statusCodeChanged = statusCodeChanged
    }

    /// 导出 Markdown 格式对比报告
    public func exportMarkdownReport() -> String {
        let baseStatus = "\(baselineResponse.statusCode) (\(baselineResponse.statusName))"
        let currStatus = "\(currentResponse.statusCode) (\(currentResponse.statusName))"
        let latencyStr = String(format: "%+.1f ms", latencyDeltaMs)
        let sizeStr = sizeDeltaBytes >= 0 ? "+\(sizeDeltaBytes) B" : "\(sizeDeltaBytes) B"

        var report = """
# Pulsar 响应快照差异对比报告 (Response Diff)

- **基准响应**: 状态 `\(baseStatus)`, 耗时 `\(String(format: "%.1f", baselineResponse.durationMs)) ms`
- **当前响应**: 状态 `\(currStatus)`, 耗时 `\(String(format: "%.1f", currentResponse.durationMs)) ms`
- **差异指标**: \(isIdentical ? "✅ **完全一致 (Zero Diff)**" : "⚠️ **存在结构或内容差异**")
- **指标变动**: 耗时变动 `\(latencyStr)`, 体积变动 `\(sizeStr)`, 新增 `+\(addedCount)` 行, 删除 `-\(removedCount)` 行

---

### 载荷 Diff 详情
```diff
"""
        for line in lines {
            let symbol = line.kind.rawValue
            report += "\n\(symbol) \(line.content)"
        }
        report += "\n```\n"

        return report
    }
}

/// 响应快照对比与 JSON 语义 Diff 引擎
public final class ResponseDiffEngine {
    public static let shared = ResponseDiffEngine()

    public init() {}

    /// 格式化并标准化 JSON 字符串
    public func normalizeJSON(_ jsonString: String) -> String {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard let data = trimmed.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return trimmed
        }
        return prettyString
    }

    /// 对比基线快照与当前响应
    public func compare(baseline: RPCResponse, current: RPCResponse) -> ResponseDiffReport {
        let normalizedBase = normalizeJSON(baseline.responsePayload)
        let normalizedCurr = normalizeJSON(current.responsePayload)

        let baseLines = normalizedBase.components(separatedBy: "\n")
        let currLines = normalizedCurr.components(separatedBy: "\n")

        let diffLines = computeLCSDiff(oldLines: baseLines, newLines: currLines)

        let added = diffLines.filter { $0.kind == .added }.count
        let removed = diffLines.filter { $0.kind == .removed }.count
        let isIdentical = (added == 0 && removed == 0 && normalizedBase == normalizedCurr)

        let latencyDelta = current.durationMs - baseline.durationMs
        let baseSize = baseline.responsePayload.utf8.count
        let currSize = current.responsePayload.utf8.count
        let sizeDelta = currSize - baseSize
        let statusChanged = (baseline.statusCode != current.statusCode)

        return ResponseDiffReport(
            baselineResponse: baseline,
            currentResponse: current,
            lines: diffLines,
            addedCount: added,
            removedCount: removed,
            isIdentical: isIdentical,
            latencyDeltaMs: latencyDelta,
            sizeDeltaBytes: sizeDelta,
            statusCodeChanged: statusChanged
        )
    }

    // MARK: - 标准 LCS (最长公共子序列) 差异计算算法

    private func computeLCSDiff(oldLines: [String], newLines: [String]) -> [DiffLine] {
        let m = oldLines.count
        let n = newLines.count

        // 构造 LCS DP 表
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0..<m {
            for j in 0..<n {
                if oldLines[i] == newLines[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        // 回溯构造差异序列
        var result: [DiffLine] = []
        var i = m
        var j = n

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                result.append(DiffLine(oldLineNumber: i, newLineNumber: j, content: oldLines[i - 1], kind: .unchanged))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(DiffLine(oldLineNumber: nil, newLineNumber: j, content: newLines[j - 1], kind: .added))
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                result.append(DiffLine(oldLineNumber: i, newLineNumber: nil, content: oldLines[i - 1], kind: .removed))
                i -= 1
            }
        }

        return result.reversed()
    }
}
