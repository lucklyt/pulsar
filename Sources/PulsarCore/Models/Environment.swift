import Foundation

/// 表示单个环境变量项
public struct VariableItem: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isSecret: Bool
    public var isEnabled: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        isSecret: Bool = false,
        isEnabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
        self.notes = notes
    }
}

/// 表示环境集合（如 Local, Dev, Staging, Prod）
public struct EnvironmentModel: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var isDefault: Bool
    public var variables: [VariableItem]

    public init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        variables: [VariableItem] = []
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.variables = variables
    }

    /// 便捷访问有效变量字典
    public var activeVariableDictionary: [String: String] {
        var dict: [String: String] = [:]
        for item in variables where item.isEnabled && !item.key.trimmingCharacters(in: .whitespaces).isEmpty {
            dict[item.key.trimmingCharacters(in: .whitespaces)] = item.value
        }
        return dict
    }
}
