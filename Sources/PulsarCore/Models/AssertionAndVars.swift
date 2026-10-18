import Foundation

/// 声明式断言比较操作符
public enum AssertionOperator: String, Codable, CaseIterable, Identifiable {
    case equals = "等于 (==)"
    case notEquals = "不等于 (!=)"
    case contains = "包含 (contains)"
    case notContains = "不包含 (not contains)"
    case greaterThan = "大于 (>)"
    case lessThan = "小于 (<)"
    case isDefined = "存在且非空 (isDefined)"
    case isNullOrEmpty = "为空或不存在 (isEmpty)"

    public var id: String { rawValue }

    public var shortSymbol: String {
        switch self {
        case .equals: return "=="
        case .notEquals: return "!="
        case .contains: return "contains"
        case .notContains: return "!contains"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .isDefined: return "isDefined"
        case .isNullOrEmpty: return "isEmpty"
        }
    }
}

/// 单条声明式断言规则
public struct AssertionRule: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var expression: String      // 如 res.status, res.responseTime, res.body.token, res.headers.content-type
    public var op: AssertionOperator
    public var expectedValue: String   // 如 0, 500, SUCCESS
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        expression: String = "res.status",
        op: AssertionOperator = .equals,
        expectedValue: String = "0",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.expression = expression
        self.op = op
        self.expectedValue = expectedValue
        self.isEnabled = isEnabled
    }
}

/// 断言执行单项结果
public struct AssertionResult: Identifiable, Codable, Equatable {
    public var id: UUID
    public var expression: String
    public var op: AssertionOperator
    public var expectedValue: String
    public var actualValue: String
    public var passed: Bool
    public var message: String

    public init(
        id: UUID = UUID(),
        expression: String,
        op: AssertionOperator,
        expectedValue: String,
        actualValue: String,
        passed: Bool,
        message: String = ""
    ) {
        self.id = id
        self.expression = expression
        self.op = op
        self.expectedValue = expectedValue
        self.actualValue = actualValue
        self.passed = passed
        self.message = message
    }
}

/// 响应变量提取规则 (Post-Response Vars / 接口串联)
public struct ResponseVarRule: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var targetVariable: String   // 写入的环境变量键名，如 "jwt_token"
    public var sourcePath: String       // 提取来源路径，如 "res.body.token" 或 "res.body.data.id" 或 "res.headers.x-request-id"
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        targetVariable: String = "token",
        sourcePath: String = "res.body.token",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.targetVariable = targetVariable
        self.sourcePath = sourcePath
        self.isEnabled = isEnabled
    }
}
