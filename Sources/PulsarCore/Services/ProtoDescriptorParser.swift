import Foundation

/// Proto 字段类型描述
public enum ProtoFieldKind: String, Codable {
    case string = "string"
    case int32 = "int32"
    case int64 = "int64"
    case uint32 = "uint32"
    case uint64 = "uint64"
    case float = "float"
    case double = "double"
    case bool = "bool"
    case bytes = "bytes"
    case enumType = "enum"
    case message = "message"
    case mapType = "map"
}

public class ProtoFieldDescriptor: Codable {
    public var name: String
    public var number: Int
    public var kind: ProtoFieldKind
    public var isRepeated: Bool
    public var enumValues: [String]
    public var messageDescriptor: ProtoMessageDescriptor?
    public var mapKeyKind: ProtoFieldKind?
    public var mapValueKind: ProtoFieldKind?
    public var options: [ProtoOption]
    public var comments: String

    public init(
        name: String,
        number: Int,
        kind: ProtoFieldKind,
        isRepeated: Bool = false,
        enumValues: [String] = [],
        messageDescriptor: ProtoMessageDescriptor? = nil,
        mapKeyKind: ProtoFieldKind? = nil,
        mapValueKind: ProtoFieldKind? = nil,
        options: [ProtoOption] = [],
        comments: String = ""
    ) {
        self.name = name
        self.number = number
        self.kind = kind
        self.isRepeated = isRepeated
        self.enumValues = enumValues
        self.messageDescriptor = messageDescriptor
        self.mapKeyKind = mapKeyKind
        self.mapValueKind = mapValueKind
        self.options = options
        self.comments = comments
    }
}

public class ProtoMessageDescriptor: Codable {
    public var name: String
    public var fullName: String
    public var fields: [ProtoFieldDescriptor]
    public var options: [ProtoOption]

    public init(name: String, fullName: String, fields: [ProtoFieldDescriptor] = [], options: [ProtoOption] = []) {
        self.name = name
        self.fullName = fullName
        self.fields = fields
        self.options = options
    }
}

public struct ProtoMethodDescriptor: Identifiable, Codable {
    public var id: String { fullName }
    public var name: String
    public var fullName: String
    public var serviceName: String
    public var clientStreaming: Bool
    public var serverStreaming: Bool
    public var inputMessage: ProtoMessageDescriptor
    public var outputMessage: ProtoMessageDescriptor
    public var options: [ProtoOption]
    public var comments: String
    public var sourceLocation: String

    public var callType: GRPCCallType {
        if clientStreaming && serverStreaming {
            return .bidiStreaming
        } else if clientStreaming {
            return .clientStreaming
        } else if serverStreaming {
            return .serverStreaming
        } else {
            return .unary
        }
    }

    public var httpOption: ProtoOption? {
        options.first { $0.name.contains("http") || $0.name.contains("google.api.http") }
    }

    public var isAuthRequired: Bool {
        options.contains { opt in
            let n = opt.name.lowercased()
            return n.contains("auth") || n.contains("security") || opt.value.lowercased().contains("auth")
        }
    }

    public var customExtensionOptions: [ProtoOption] {
        options.filter { $0.isExtension }
    }

    public init(
        name: String,
        fullName: String,
        serviceName: String,
        clientStreaming: Bool = false,
        serverStreaming: Bool = false,
        inputMessage: ProtoMessageDescriptor,
        outputMessage: ProtoMessageDescriptor,
        options: [ProtoOption] = [],
        comments: String = "",
        sourceLocation: String = ""
    ) {
        self.name = name
        self.fullName = fullName
        self.serviceName = serviceName
        self.clientStreaming = clientStreaming
        self.serverStreaming = serverStreaming
        self.inputMessage = inputMessage
        self.outputMessage = outputMessage
        self.options = options
        self.comments = comments
        self.sourceLocation = sourceLocation
    }
}

public struct ProtoServiceDescriptor: Identifiable, Codable {
    public var id: String { fullName }
    public var name: String
    public var fullName: String
    public var methods: [ProtoMethodDescriptor]
    public var options: [ProtoOption]
    public var comments: String

    public init(
        name: String,
        fullName: String,
        methods: [ProtoMethodDescriptor] = [],
        options: [ProtoOption] = [],
        comments: String = ""
    ) {
        self.name = name
        self.fullName = fullName
        self.methods = methods
        self.options = options
        self.comments = comments
    }
}

/// 针对 Proto 架构自动生成 Mock JSON Payload 模板
public final class MockJSONGenerator {
    public static let shared = MockJSONGenerator()

    public func generateMockJSON(for message: ProtoMessageDescriptor, depth: Int = 0) -> String {
        // 防止递归自引用的死循环
        guard depth < 4 else { return "{}" }

        // 处理 Google Well-Known Types
        if let wellKnown = handleWellKnownTypes(fullName: message.fullName) {
            return wellKnown
        }

        var dict: [String: Any] = [:]

        for field in message.fields {
            if field.isRepeated {
                dict[field.name] = [generateFieldValue(for: field, depth: depth + 1)]
            } else {
                dict[field.name] = generateFieldValue(for: field, depth: depth + 1)
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }

        return "{\n}"
    }

    private func generateFieldValue(for field: ProtoFieldDescriptor, depth: Int) -> Any {
        switch field.kind {
        case .string:
            return "sample_\(field.name)"
        case .int32, .int64, .uint32, .uint64:
            return 0
        case .float, .double:
            return 0.0
        case .bool:
            return true
        case .bytes:
            return "dGVzdA==" // base64 for "test"
        case .enumType:
            return field.enumValues.first ?? "UNKNOWN"
        case .mapType:
            return ["key": "value"]
        case .message:
            if let nested = field.messageDescriptor {
                if let wellKnown = handleWellKnownTypes(fullName: nested.fullName) {
                    if let data = wellKnown.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) {
                        return obj
                    }
                    return wellKnown
                }
                var subDict: [String: Any] = [:]
                guard depth < 3 else { return subDict }
                for subField in nested.fields {
                    subDict[subField.name] = generateFieldValue(for: subField, depth: depth + 1)
                }
                return subDict
            }
            return [:]
        }
    }

    private func handleWellKnownTypes(fullName: String) -> String? {
        switch fullName {
        case "google.protobuf.Timestamp":
            return "\"2026-10-16T12:00:00Z\""
        case "google.protobuf.Duration":
            return "\"10s\""
        case "google.protobuf.Empty":
            return "{}"
        case "google.protobuf.Struct":
            return "{\"key\": \"value\"}"
        case "google.protobuf.FieldMask":
            return "\"paths,to,field\""
        case "google.protobuf.StringValue":
            return "\"sample_string\""
        case "google.protobuf.Int32Value", "google.protobuf.Int64Value":
            return "100"
        case "google.protobuf.BoolValue":
            return "true"
        default:
            return nil
        }
    }
}
