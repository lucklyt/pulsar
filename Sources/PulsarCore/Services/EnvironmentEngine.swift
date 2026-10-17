import Foundation

/// 环境变量插值与动态求值引擎 (类似 Postman / Bruno 核心能力)
public final class EnvironmentEngine {
    public static let shared = EnvironmentEngine()

    private let regex: NSRegularExpression

    public init() {
        // 匹配 {{ variable_name }} 或 {{ $func(args) }}
        self.regex = try! NSRegularExpression(pattern: #"\{\{\s*([a-zA-Z0-9_\$.\(\), -]+)\s*\}\}"#)
    }

    /// 执行插值替换
    /// - Parameters:
    ///   - template: 含有 {{var}} 的原始字符串
    ///   - environment: 当前选中的环境模型
    ///   - globalVariables: 全局变量列表
    ///   - localVariables: 请求或集合级私有变量
    ///   - maxDepth: 防止递归循环引用的最大迭代深度
    public func resolve(
        template: String,
        environment: EnvironmentModel? = nil,
        globalVariables: [VariableItem] = [],
        localVariables: [VariableItem] = [],
        maxDepth: Int = 5
    ) -> String {
        guard !template.isEmpty && template.contains("{{") else {
            return template
        }

        // 构建变量字典：Local > Environment > Global
        var variableMap: [String: String] = [:]

        for item in globalVariables where item.isEnabled && !item.key.isEmpty {
            variableMap[item.key.trimmingCharacters(in: .whitespaces)] = item.value
        }

        if let env = environment {
            for item in env.variables where item.isEnabled && !item.key.isEmpty {
                variableMap[item.key.trimmingCharacters(in: .whitespaces)] = item.value
            }
        }

        for item in localVariables where item.isEnabled && !item.key.isEmpty {
            variableMap[item.key.trimmingCharacters(in: .whitespaces)] = item.value
        }

        var result = template
        var currentDepth = 0

        while currentDepth < maxDepth && result.contains("{{") {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            if matches.isEmpty {
                break
            }

            var mutated = false
            // 从后往前替换，避免偏移量错位
            for match in matches.reversed() {
                guard match.numberOfRanges > 1 else { continue }
                let varKey = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)

                if let dynamicVal = evaluateDynamicFunction(varKey) {
                    result = (result as NSString).replacingCharacters(in: match.range, with: dynamicVal)
                    mutated = true
                } else if let val = variableMap[varKey] {
                    result = (result as NSString).replacingCharacters(in: match.range, with: val)
                    mutated = true
                }
            }

            if !mutated {
                // 如果没有匹配的已知变量或动态函数，终止循环防止死循环
                break
            }

            currentDepth += 1
        }

        return result
    }

    /// 提取模板中所有引用的变量名列表
    public func extractReferencedVariables(from template: String) -> [String] {
        guard !template.isEmpty else { return [] }
        let nsString = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
    }

    /// 计算内置动态函数
    private func evaluateDynamicFunction(_ expression: String) -> String? {
        if expression == "$uuid" || expression == "$guid" {
            return UUID().uuidString.lowercased()
        }
        if expression == "$timestamp" {
            return String(Int(Date().timeIntervalSince1970))
        }
        if expression == "$timestampMs" {
            return String(Int64(Date().timeIntervalSince1970 * 1000))
        }
        if expression == "$isoTimestamp" {
            return ISO8601DateFormatter().string(from: Date())
        }
        if expression.starts(with: "$randomInt") {
            // 解析 $randomInt 或 $randomInt(min, max)
            return parseRandomInt(expression)
        }
        if expression == "$randomAlpha" {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        }
        return nil
    }

    private func parseRandomInt(_ expr: String) -> String {
        // 匹配 $randomInt(1, 100)
        let pattern = #"\$randomInt\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)"#
        if let reg = try? NSRegularExpression(pattern: pattern),
           let match = reg.firstMatch(in: expr, range: NSRange(location: 0, length: expr.utf16.count)) {
            let nsStr = expr as NSString
            let minStr = nsStr.substring(with: match.range(at: 1))
            let maxStr = nsStr.substring(with: match.range(at: 2))
            if let min = Int(minStr), let max = Int(maxStr), max > min {
                let randomVal = Int.random(in: min...max)
                return String(randomVal)
            }
        }
        return String(Int.random(in: 1...1000))
    }
}
