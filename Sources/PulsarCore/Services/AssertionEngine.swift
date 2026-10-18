import Foundation

/// 声明式断言评估与响应变量提取核心引擎 (Bruno 风格自动化测试与接口串联)
public final class AssertionEngine {
    public static let shared = AssertionEngine()

    public init() {}

    // MARK: - 1. 响应断言评估

    /// 对单个 RPCResponse 执行一组断言规则
    public func evaluateAssertions(rules: [AssertionRule], response: RPCResponse) -> [AssertionResult] {
        var results: [AssertionResult] = []

        for rule in rules where rule.isEnabled {
            let actual = resolvePathValue(path: rule.expression, response: response) ?? ""
            let (passed, message) = checkOperator(op: rule.op, actual: actual, expected: rule.expectedValue)

            results.append(AssertionResult(
                id: rule.id,
                expression: rule.expression,
                op: rule.op,
                expectedValue: rule.expectedValue,
                actualValue: actual,
                passed: passed,
                message: message
            ))
        }

        return results
    }

    private func checkOperator(op: AssertionOperator, actual: String, expected: String) -> (passed: Bool, message: String) {
        let cleanActual = actual.trimmingCharacters(in: .whitespaces)
        let cleanExpected = expected.trimmingCharacters(in: .whitespaces)

        switch op {
        case .equals:
            if let aNum = Double(cleanActual), let eNum = Double(cleanExpected) {
                let passed = abs(aNum - eNum) < 0.0001
                return (passed, passed ? "数值匹配成功 (\(cleanActual) == \(cleanExpected))" : "期望 \(cleanExpected)，实际为 \(cleanActual)")
            } else {
                let passed = cleanActual == cleanExpected
                return (passed, passed ? "文本完全匹配" : "期望「\(cleanExpected)」，实际为「\(cleanActual)」")
            }

        case .notEquals:
            if let aNum = Double(cleanActual), let eNum = Double(cleanExpected) {
                let passed = abs(aNum - eNum) >= 0.0001
                return (passed, passed ? "数值不等校验通过" : "实际值与不期望值相同 (\(cleanActual))")
            } else {
                let passed = cleanActual != cleanExpected
                return (passed, passed ? "文本不等校验通过" : "实际值等于不期望值")
            }

        case .contains:
            let passed = cleanActual.contains(cleanExpected)
            return (passed, passed ? "包含期望子串「\(cleanExpected)」" : "实际内容不包含「\(cleanExpected)」")

        case .notContains:
            let passed = !cleanActual.contains(cleanExpected)
            return (passed, passed ? "校验通过，未包含「\(cleanExpected)」" : "实际内容包含了不期望出现的「\(cleanExpected)」")

        case .greaterThan:
            guard let aNum = Double(cleanActual), let eNum = Double(cleanExpected) else {
                return (false, "无法进行数值大于比较 (实际: \(cleanActual), 期望: \(cleanExpected))")
            }
            let passed = aNum > eNum
            return (passed, passed ? "\(aNum) > \(eNum) 满足条件" : "实际值 \(aNum) 不大于期望值 \(eNum)")

        case .lessThan:
            guard let aNum = Double(cleanActual), let eNum = Double(cleanExpected) else {
                return (false, "无法进行数值小于比较 (实际: \(cleanActual), 期望: \(cleanExpected))")
            }
            let passed = aNum < eNum
            return (passed, passed ? "\(aNum) < \(eNum) 满足条件" : "实际值 \(aNum) 不小于期望值 \(eNum)")

        case .isDefined:
            let passed = !cleanActual.isEmpty && cleanActual.lowercased() != "null"
            return (passed, passed ? "字段已定义且非空" : "字段未定义或为 null/空")

        case .isNullOrEmpty:
            let passed = cleanActual.isEmpty || cleanActual.lowercased() == "null"
            return (passed, passed ? "字段为空/null" : "字段不为空 (实际为: \(cleanActual))")
        }
    }

    // MARK: - 2. 响应字段提取到环境变量 (Post-Response Vars)

    /// 根据规则从响应中提取键值对
    public func extractVariables(rules: [ResponseVarRule], response: RPCResponse) -> [String: String] {
        var extracted: [String: String] = [:]

        for rule in rules where rule.isEnabled {
            let key = rule.targetVariable.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if let val = resolvePathValue(path: rule.sourcePath, response: response), !val.isEmpty {
                extracted[key] = val
            }
        }

        return extracted
    }

    // MARK: - 3. 通用路径解析器 (JsonPath & Metadata Lookup)

    /// 解析形如 res.status, res.responseTime, res.body.data.id, res.headers.x-trace-id
    public func resolvePathValue(path: String, response: RPCResponse) -> String? {
        let clean = path.trimmingCharacters(in: .whitespaces)

        // 1. 状态码与耗时
        if clean == "res.status" || clean == "status" {
            return String(response.statusCode)
        }
        if clean == "res.statusName" || clean == "statusName" {
            return response.statusName
        }
        if clean == "res.responseTime" || clean == "res.durationMs" || clean == "durationMs" {
            return String(format: "%.1f", response.durationMs)
        }
        if clean == "res.body" || clean == "body" {
            return response.responsePayload
        }

        // 2. 响应体 JSON 字段深入提取: res.body.data.token 或 body.data.token
        let bodyPrefixes = ["res.body.", "body."]
        for prefix in bodyPrefixes {
            if clean.starts(with: prefix) {
                let subPath = String(clean.dropFirst(prefix.count))
                return extractJSONPath(payload: response.responsePayload, keyPath: subPath)
            }
        }

        // 3. 响应头提取: res.headers.key 或 headers.key
        let headerPrefixes = ["res.headers.", "headers."]
        for prefix in headerPrefixes {
            if clean.starts(with: prefix) {
                let headerKey = String(clean.dropFirst(prefix.count)).lowercased()
                if let v = response.initialMetadata.first(where: { $0.key.lowercased() == headerKey })?.value {
                    return v
                }
                if let v = response.trailingMetadata.first(where: { $0.key.lowercased() == headerKey })?.value {
                    return v
                }
                return nil
            }
        }

        // 4. 兜底尝试当作 body 字段
        return extractJSONPath(payload: response.responsePayload, keyPath: clean)
    }

    private func extractJSONPath(payload: String, keyPath: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let parts = keyPath.split(separator: ".").map { String($0) }
        var current: Any = json

        for part in parts {
            if let dict = current as? [String: Any] {
                guard let next = dict[part] else { return nil }
                current = next
            } else if let arr = current as? [Any] {
                if let idx = Int(part), idx >= 0 && idx < arr.count {
                    current = arr[idx]
                } else if part == "length" || part == "count" {
                    return String(arr.count)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        if let str = current as? String {
            return str
        } else if let num = current as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return num.stringValue
        } else if let dict = current as? [String: Any],
                  let d = try? JSONSerialization.data(withJSONObject: dict),
                  let s = String(data: d, encoding: .utf8) {
            return s
        } else if let arr = current as? [Any],
                  let d = try? JSONSerialization.data(withJSONObject: arr),
                  let s = String(data: d, encoding: .utf8) {
            return s
        }

        return String(describing: current)
    }
}
