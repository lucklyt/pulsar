import Foundation

/// Proto 选项或扩展注解 (Proto Options / Custom Extensions)
public struct ProtoOption: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String       // e.g. "google.api.http", "(my_custom_opt)", "deprecated"
    public var value: String      // e.g. "{ post: \"/v1/orders\" body: \"*\" }", "true"
    public var isExtension: Bool  // 是否为自定义扩展 (用括号包裹的扩展字段)

    public init(id: UUID = UUID(), name: String, value: String, isExtension: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isExtension = isExtension || name.hasPrefix("(") || name.contains(".")
    }
}

/// Proto 扩展定义 (extend <Message> { ... })
public struct ProtoExtensionDef: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var extendedType: String // e.g. "google.protobuf.MethodOptions"
    public var fieldName: String    // e.g. "require_auth"
    public var fieldNumber: Int     // e.g. 50001
    public var fieldType: String     // e.g. "bool", "string", "MyCustomRule"
    public var description: String

    public init(
        id: UUID = UUID(),
        extendedType: String,
        fieldName: String,
        fieldNumber: Int,
        fieldType: String,
        description: String = ""
    ) {
        self.id = id
        self.extendedType = extendedType
        self.fieldName = fieldName
        self.fieldNumber = fieldNumber
        self.fieldType = fieldType
        self.description = description
    }
}

/// Proto Enum 枚举描述
public struct ProtoEnumDescriptor: Identifiable, Codable, Equatable, Hashable {
    public var id: String { name }
    public var name: String
    public var values: [String: Int] // Enum name -> number

    public init(name: String, values: [String: Int] = [:]) {
        self.name = name
        self.values = values
    }
}

/// 扩展插件钩子定义 (支持基于 Proto 选项自定义行为)
public struct ProtoExtensionPlugin: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String               // 插件名称，如 "Google HTTP Transcoding"
    public var isEnabled: Bool
    public var targetOptionName: String   // 匹配的选项名，如 "google.api.http"
    public var actionType: ActionType
    public var injectHeaderKey: String
    public var injectHeaderValue: String
    public var notes: String

    public enum ActionType: String, Codable, CaseIterable {
        case showBadge = "显示扩展徽标 (Show Badge)"
        case injectHeader = "自动注入 Header (Auto Inject Header)"
        case requireAuth = "标记需认证 (Require Auth)"
        case formatPrompt = "提示校验约束 (Validation Warning)"
    }

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        targetOptionName: String,
        actionType: ActionType = .showBadge,
        injectHeaderKey: String = "",
        injectHeaderValue: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.targetOptionName = targetOptionName
        self.actionType = actionType
        self.injectHeaderKey = injectHeaderKey
        self.injectHeaderValue = injectHeaderValue
        self.notes = notes
    }
}

/// Proto Import Path 搜索根目录 (等同于 protoc 的 -I / --proto_path 参数)
public struct ProtoImportPath: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var path: String
    public var isEnabled: Bool
    public var isBuiltin: Bool

    public init(id: UUID = UUID(), path: String, isEnabled: Bool = true, isBuiltin: Bool = false) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
        self.isBuiltin = isBuiltin
    }
}

/// 解析后的 import 引用状态
public struct ResolvedImport: Identifiable, Codable, Equatable, Hashable {
    public var id: String { rawImport }
    public var rawImport: String
    public var resolvedPath: String?
    public var isResolved: Bool

    public init(rawImport: String, resolvedPath: String? = nil, isResolved: Bool = false) {
        self.rawImport = rawImport
        self.resolvedPath = resolvedPath
        self.isResolved = isResolved
    }
}

/// 本地已解析的单个 .proto 文件
public struct LocalProtoFile: Identifiable, Codable, Equatable {
    public var id: UUID
    public var filePath: String
    public var fileName: String
    public var packageName: String
    public var syntax: String
    public var imports: [String]
    public var resolvedImports: [ResolvedImport]
    public var services: [ProtoServiceDescriptor]
    public var messages: [ProtoMessageDescriptor]
    public var enums: [ProtoEnumDescriptor]
    public var fileOptions: [ProtoOption]
    public var extensionDefs: [ProtoExtensionDef]
    public var rawContent: String
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        filePath: String,
        fileName: String,
        packageName: String = "",
        syntax: String = "proto3",
        imports: [String] = [],
        resolvedImports: [ResolvedImport] = [],
        services: [ProtoServiceDescriptor] = [],
        messages: [ProtoMessageDescriptor] = [],
        enums: [ProtoEnumDescriptor] = [],
        fileOptions: [ProtoOption] = [],
        extensionDefs: [ProtoExtensionDef] = [],
        rawContent: String = "",
        importedAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.packageName = packageName
        self.syntax = syntax
        self.imports = imports
        self.resolvedImports = resolvedImports
        self.services = services
        self.messages = messages
        self.enums = enums
        self.fileOptions = fileOptions
        self.extensionDefs = extensionDefs
        self.rawContent = rawContent
        self.importedAt = importedAt
    }

    public static func == (lhs: LocalProtoFile, rhs: LocalProtoFile) -> Bool {
        lhs.id == rhs.id
    }
}
