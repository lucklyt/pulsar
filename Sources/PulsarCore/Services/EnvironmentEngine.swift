import Foundation
import CryptoKit

/// 环境变量插值与动态求值引擎 (类似 Postman / Bruno 核心能力)
public final class EnvironmentEngine {
    public static let shared = EnvironmentEngine()

    private let regex: NSRegularExpression

    public init() {
        // 匹配 {{ variable_name }} 或 {{ $func("arg") }}
        self.regex = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
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
        if expression == "$randomEmail" {
            let prefix = UUID().uuidString.prefix(6).lowercased()
            return "user_\(prefix)@example.com"
        }
        if expression == "$randomIPv4" {
            return "\(Int.random(in: 192...223)).\(Int.random(in: 1...254)).\(Int.random(in: 1...254)).\(Int.random(in: 1...254))"
        }
        if expression == "$randomPhone" {
            return "138\(String(format: "%08d", Int.random(in: 10000000...99999999)))"
        }
        if expression.starts(with: "$base64Encode(") {
            if let arg = parseSingleArgument(funcName: "base64Encode", expr: expression) {
                return Data(arg.utf8).base64EncodedString()
            }
        }
        if expression.starts(with: "$base64Decode(") {
            if let arg = parseSingleArgument(funcName: "base64Decode", expr: expression),
               let data = Data(base64Encoded: arg),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        if expression.starts(with: "$sha256(") {
            if let arg = parseSingleArgument(funcName: "sha256", expr: expression) {
                let digest = SHA256.hash(data: Data(arg.utf8))
                return digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        if expression.starts(with: "$md5(") {
            if let arg = parseSingleArgument(funcName: "md5", expr: expression) {
                let digest = Insecure.MD5.hash(data: Data(arg.utf8))
                return digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        return nil
    }

    private func parseSingleArgument(funcName: String, expr: String) -> String? {
        let pattern = #"\$"# + NSRegularExpression.escapedPattern(for: funcName) + #"\s*\(\s*(.*?)\s*\)"#
        if let reg = try? NSRegularExpression(pattern: pattern),
           let match = reg.firstMatch(in: expr, range: NSRange(location: 0, length: expr.utf16.count)) {
            let nsStr = expr as NSString
            let rawArg = nsStr.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            // 去除外部单双引号（若有）
            if (rawArg.hasPrefix("\"") && rawArg.hasSuffix("\"")) || (rawArg.hasPrefix("'") && rawArg.hasSuffix("'")) {
                return String(rawArg.dropFirst().dropLast())
            }
            return rawArg
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

    /// 内置函数清单
    public var availableBuiltins: [(key: String, desc: String)] {
        [
            ("$uuid", "随机 UUID (例如 e4eaaaf2-6434-4b52-9020-00c8872d4100)"),
            ("$timestamp", "当前 Unix 秒级时间戳 (例如 1714000000)"),
            ("$timestampMs", "当前毫秒时间戳 (例如 1714000000000)"),
            ("$isoTimestamp", "标准 ISO8601 时间串 (例如 2026-10-18T12:00:00Z)"),
            ("$randomInt", "随机整数 (1 到 1000)"),
            ("$randomAlpha", "8位随机小写字母串"),
            ("$randomEmail", "随机测试电子邮箱 (如 user_a1b2c3@example.com)"),
            ("$randomIPv4", "随机 IPv4 测试地址 (如 192.168.1.55)"),
            ("$randomPhone", "随机 11 位手机号 (如 13800138000)"),
            ("$base64Encode(text)", "Base64 编码"),
            ("$base64Decode(b64)", "Base64 解码"),
            ("$sha256(text)", "SHA-256 哈希散列"),
            ("$md5(text)", "MD5 哈希散列")
        ]
    }

    /// 校验某个变量名是否已定义
    public func isVariableDefined(
        _ varKey: String,
        environment: EnvironmentModel? = nil,
        globalVariables: [VariableItem] = [],
        localVariables: [VariableItem] = []
    ) -> Bool {
        let k = varKey.trimmingCharacters(in: .whitespaces)
        if evaluateDynamicFunction(k) != nil {
            return true
        }
        if let env = environment, env.variables.contains(where: { $0.isEnabled && $0.key == k }) {
            return true
        }
        if globalVariables.contains(where: { $0.isEnabled && $0.key == k }) {
            return true
        }
        if localVariables.contains(where: { $0.isEnabled && $0.key == k }) {
            return true
        }
        return false
    }

    /// 查找文本中所有未解析的未知变量名
    public func findUnresolvedVariables(
        in template: String,
        environment: EnvironmentModel? = nil,
        globalVariables: [VariableItem] = [],
        localVariables: [VariableItem] = []
    ) -> [String] {
        let refs = extractReferencedVariables(from: template)
        var unresolved: [String] = []
        for ref in refs {
            if !isVariableDefined(ref, environment: environment, globalVariables: globalVariables, localVariables: localVariables) {
                if !unresolved.contains(ref) {
                    unresolved.append(ref)
                }
            }
        }
        return unresolved
    }
}
