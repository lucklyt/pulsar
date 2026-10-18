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
    public var colorHex: String
    public var isProduction: Bool
    public var variables: [VariableItem]

    public init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        colorHex: String = "#0A84FF",
        isProduction: Bool = false,
        variables: [VariableItem] = []
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.colorHex = colorHex
        self.isProduction = isProduction
        self.variables = variables
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isDefault, colorHex, isProduction, variables
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名环境"
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? (self.name.lowercased().contains("prod") ? "#FF453A" : "#0A84FF")
        self.isProduction = try container.decodeIfPresent(Bool.self, forKey: .isProduction) ?? self.name.lowercased().contains("prod")
        self.variables = try container.decodeIfPresent([VariableItem].self, forKey: .variables) ?? []
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

import SwiftUI

extension Color {
    public init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 10, 132, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
