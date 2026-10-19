import Foundation

/// 本地 .proto 文件解析器 (支持 Proto3/Proto2、服务与 RPC 定义、Message/Enum、以及扩展 Extend 与自定义 Option 注解)
public final class LocalProtoParser {
    public static let shared = LocalProtoParser()

    public init() {}

    /// 解析指定路径的单个 .proto 文件
    public func parseFile(at path: String) throws -> LocalProtoFile {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseString(content, filePath: path, fileName: url.lastPathComponent)
    }

    /// 解析内存中的 proto 文本字符串
    public func parseString(_ content: String, filePath: String = "", fileName: String = "inline.proto") -> LocalProtoFile {
        var protoFile = LocalProtoFile(filePath: filePath, fileName: fileName, rawContent: content)

        // 规范化与行处理
        let lines = content.components(separatedBy: .newlines)
        var syntax = "proto3"
        var packageName = ""
        var imports: [String] = []
        var fileOptions: [ProtoOption] = []
        var extensions: [ProtoExtensionDef] = []

        var currentComment = ""
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            // 注释提取
            if line.hasPrefix("//") {
                let c = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                currentComment = currentComment.isEmpty ? c : "\(currentComment)\n\(c)"
                index += 1
                continue
            }

            if line.isEmpty {
                currentComment = ""
                index += 1
                continue
            }

            // 1. syntax
            if line.hasPrefix("syntax") {
                if let match = line.range(of: #""([^"]+)""#, options: .regularExpression) {
                    syntax = String(line[match]).replacingOccurrences(of: "\"", with: "")
                }
                index += 1
                currentComment = ""
                continue
            }

            // 2. package
            if line.hasPrefix("package ") {
                let rest = line.dropFirst("package ".count)
                packageName = String(rest.prefix(while: { $0 != ";" })).trimmingCharacters(in: .whitespaces)
                index += 1
                currentComment = ""
                continue
            }

            // 3. import
            if line.hasPrefix("import ") {
                if let match = line.range(of: #""([^"]+)""#, options: .regularExpression) {
                    let imp = String(line[match]).replacingOccurrences(of: "\"", with: "")
                    imports.append(imp)
                }
                index += 1
                currentComment = ""
                continue
            }

            // 4. extend 扩展定义块 (extend <Message> { ... })
            if isDeclaration(line, keyword: "extend") && (line.contains("{") || hasBlockOpening(lines: lines, startIndex: index)) {
                let (extDefs, newIndex) = parseExtendBlock(lines: lines, startIndex: index)
                extensions.append(contentsOf: extDefs)
                index = newIndex
                currentComment = ""
                continue
            }

            // 5. option (全局文件选项)
            if isDeclaration(line, keyword: "option") && !line.contains("service ") {
                if let opt = parseOption(from: line) {
                    fileOptions.append(opt)
                }
                index += 1
                currentComment = ""
                continue
            }

            // 6. service 服务定义块
            if isDeclaration(line, keyword: "service") && (line.contains("{") || hasBlockOpening(lines: lines, startIndex: index)) {
                let (svc, newIndex) = parseService(lines: lines, startIndex: index, packageName: packageName, leadingComment: currentComment)
                protoFile.services.append(svc)
                index = newIndex
                currentComment = ""
                continue
            }

            // 7. message 结构体定义块
            if isDeclaration(line, keyword: "message") && (line.contains("{") || hasBlockOpening(lines: lines, startIndex: index)) {
                let (msg, newIndex) = parseMessage(lines: lines, startIndex: index, packageName: packageName)
                protoFile.messages.append(msg)
                index = newIndex
                currentComment = ""
                continue
            }

            // 8. enum 枚举定义块
            if isDeclaration(line, keyword: "enum") && (line.contains("{") || hasBlockOpening(lines: lines, startIndex: index)) {
                let (enumDesc, newIndex) = parseEnum(lines: lines, startIndex: index)
                protoFile.enums.append(enumDesc)
                index = newIndex
                currentComment = ""
                continue
            }

            index += 1
            currentComment = ""
        }

        protoFile.syntax = syntax
        protoFile.packageName = packageName
        protoFile.imports = imports
        protoFile.fileOptions = fileOptions
        protoFile.extensionDefs = extensions

        return protoFile
    }

    private func hasBlockOpening(lines: [String], startIndex: Int) -> Bool {
        var j = startIndex
        while j < lines.count && j < startIndex + 5 {
            let l = lines[j].trimmingCharacters(in: .whitespaces)
            if l.contains("{") { return true }
            if l.hasSuffix(";") { return false }
            j += 1
        }
        return false
    }

    private func isDeclaration(_ line: String, keyword: String) -> Bool {
        line.hasPrefix("\(keyword) ") || line.starts(with: "\(keyword)\t")
    }

    // MARK: - Extend 扩展块解析

    private func parseExtendBlock(lines: [String], startIndex: Int) -> ([ProtoExtensionDef], Int) {
        var defs: [ProtoExtensionDef] = []
        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)

        // 提取 extend 目标，如 extend google.protobuf.MethodOptions {
        var extendedType = "google.protobuf.MethodOptions"
        let parts = headerLine.split(separator: " ")
        if parts.count >= 2 {
            extendedType = String(parts[1]).replacingOccurrences(of: "{", with: "").trimmingCharacters(in: .whitespaces)
        }

        var i = startIndex + 1
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("}") {
                return (defs, i + 1)
            }

            // 例如: bool require_auth = 50001;
            // 或者: string custom_route = 50002;
            if line.contains("=") && line.contains(";") {
                let clean = line.prefix(while: { $0 != ";" })
                let tokens = clean.split(separator: "=")
                if tokens.count == 2 {
                    let left = tokens[0].trimmingCharacters(in: .whitespaces).split(separator: " ")
                    let right = tokens[1].trimmingCharacters(in: .whitespaces)

                    if left.count >= 2, let fieldNum = Int(right) {
                        let typeStr = String(left[0])
                        let nameStr = String(left[1])
                        defs.append(ProtoExtensionDef(
                            extendedType: extendedType,
                            fieldName: nameStr,
                            fieldNumber: fieldNum,
                            fieldType: typeStr,
                            description: "Custom extension on \(extendedType)"
                        ))
                    }
                }
            }
            i += 1
        }
        return (defs, i)
    }

    // MARK: - Service 解析

    private func parseService(lines: [String], startIndex: Int, packageName: String, leadingComment: String) -> (ProtoServiceDescriptor, Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let cleanFirst = (firstLine.components(separatedBy: "//").first ?? firstLine).trimmingCharacters(in: .whitespaces)
        let svcName = cleanFirst
            .replacingOccurrences(of: "service", with: "")
            .replacingOccurrences(of: "{", with: "")
            .trimmingCharacters(in: .whitespaces)

        let fullName = packageName.isEmpty ? svcName : "\(packageName).\(svcName)"
        var methods: [ProtoMethodDescriptor] = []
        var options: [ProtoOption] = []

        var i = startIndex + 1
        if !firstLine.contains("{") {
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                i += 1
                if l.contains("{") { break }
            }
        }

        var methodComment = ""

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") {
                let c = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                methodComment = methodComment.isEmpty ? c : "\(methodComment)\n\(c)"
                i += 1
                continue
            }

            if line.isEmpty || line == "{" {
                i += 1
                continue
            }

            if line.contains("}") && !line.contains("{") {
                // service 结束
                return (ProtoServiceDescriptor(
                    name: svcName,
                    fullName: fullName,
                    methods: methods,
                    options: options,
                    comments: leadingComment
                ), i + 1)
            }

            // option (service_level)
            if line.hasPrefix("option ") || line.starts(with: "option\t") {
                if let opt = parseOption(from: line) {
                    options.append(opt)
                }
                i += 1
                continue
            }

            // rpc MethodName (InMsg) returns (OutMsg)
            if line.hasPrefix("rpc ") || line.starts(with: "rpc\t") {
                let (method, newIndex) = parseMethod(lines: lines, startIndex: i, serviceFullName: fullName, leadingComment: methodComment)
                if !method.name.isEmpty {
                    methods.append(method)
                }
                i = newIndex
                methodComment = ""
                continue
            }

            i += 1
            methodComment = ""
        }

        return (ProtoServiceDescriptor(
            name: svcName,
            fullName: fullName,
            methods: methods,
            options: options,
            comments: leadingComment
        ), i)
    }

    // MARK: - RPC Method 解析

    private func parseMethod(lines: [String], startIndex: Int, serviceFullName: String, leadingComment: String) -> (ProtoMethodDescriptor, Int) {
        var rpcLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        rpcLine = (rpcLine.components(separatedBy: "//").first ?? rpcLine).trimmingCharacters(in: .whitespaces)
        var i = startIndex

        // 收集多行 rpc 签名直至出现 ; 或 {
        while !rpcLine.contains(";") && !rpcLine.contains("{") && i + 1 < lines.count {
            i += 1
            let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
            if nextLine.hasPrefix("//") { continue }
            let cleanNext = (nextLine.components(separatedBy: "//").first ?? nextLine).trimmingCharacters(in: .whitespaces)
            rpcLine += " " + cleanNext
        }

        var methodName = ""
        var inputMsgName = ""
        var outputMsgName = ""
        var clientStream = false
        var serverStream = false

        // 匹配: rpc MethodName ( [stream] Input ) returns ( [stream] Output )
        let pattern = #"rpc\s+([a-zA-Z0-9_]+)\s*\(\s*(stream\s+)?([a-zA-Z0-9_\.]*)\s*\)\s*returns\s*\(\s*(stream\s+)?([a-zA-Z0-9_\.]*)\s*\)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: rpcLine, range: NSRange(location: 0, length: rpcLine.utf16.count)) {
            let ns = rpcLine as NSString
            methodName = ns.substring(with: match.range(at: 1))
            clientStream = match.range(at: 2).location != NSNotFound
            inputMsgName = ns.substring(with: match.range(at: 3))
            serverStream = match.range(at: 4).location != NSNotFound
            outputMsgName = ns.substring(with: match.range(at: 5))
        }

        let fullMethodName = "\(serviceFullName)/\(methodName)"
        var options: [ProtoOption] = []

        // 如果包含大括号，解析其中的 RPC Option / Extension (例如 google.api.http, require_auth)
        if rpcLine.contains("{") {
            let openBraces = rpcLine.filter { $0 == "{" }.count
            let closeBraces = rpcLine.filter { $0 == "}" }.count
            if openBraces > 0 && openBraces == closeBraces {
                // 单行完成的 RPC 块，如: rpc SayHello(...) returns (...) {}
                if let optContent = rpcLine.components(separatedBy: "{").last?.components(separatedBy: "}").first {
                    let trimmed = optContent.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("option ") {
                        if let opt = parseOption(from: trimmed) {
                            options.append(opt)
                        }
                    }
                }
                i += 1
            } else {
                i += 1
                var multiLineOptionBuffer = ""
                var insideBraces = max(1, openBraces - closeBraces)

                while i < lines.count && insideBraces > 0 {
                    let rawInner = lines[i].trimmingCharacters(in: .whitespaces)
                    let innerLine = (rawInner.components(separatedBy: "//").first ?? rawInner).trimmingCharacters(in: .whitespaces)

                    for ch in innerLine {
                        if ch == "{" { insideBraces += 1 }
                        else if ch == "}" { insideBraces -= 1 }
                    }

                    if insideBraces == 0 {
                        if !multiLineOptionBuffer.isEmpty {
                            if let opt = parseOption(from: multiLineOptionBuffer) {
                                options.append(opt)
                            }
                        }
                        i += 1
                        break
                    }

                    if innerLine.hasPrefix("option ") || !multiLineOptionBuffer.isEmpty {
                        multiLineOptionBuffer += (multiLineOptionBuffer.isEmpty ? "" : " ") + innerLine
                        if innerLine.hasSuffix(";") {
                            if let opt = parseOption(from: multiLineOptionBuffer) {
                                options.append(opt)
                            }
                            multiLineOptionBuffer = ""
                        }
                    }

                    i += 1
                }
            }
        } else {
            i += 1
        }

        let method = ProtoMethodDescriptor(
            name: methodName,
            fullName: fullMethodName,
            serviceName: serviceFullName,
            clientStreaming: clientStream,
            serverStreaming: serverStream,
            inputMessage: ProtoMessageDescriptor(name: inputMsgName, fullName: inputMsgName),
            outputMessage: ProtoMessageDescriptor(name: outputMsgName, fullName: outputMsgName),
            options: options,
            comments: leadingComment,
            sourceLocation: "Line \(startIndex + 1)"
        )

        return (method, i)
    }

    // MARK: - Message 解析

    private func parseMessage(lines: [String], startIndex: Int, packageName: String) -> (ProtoMessageDescriptor, Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let cleanFirst = (firstLine.components(separatedBy: "//").first ?? firstLine).trimmingCharacters(in: .whitespaces)
        let name = cleanFirst
            .replacingOccurrences(of: "message", with: "")
            .replacingOccurrences(of: "{", with: "")
            .trimmingCharacters(in: .whitespaces)

        let fullName = packageName.isEmpty ? name : "\(packageName).\(name)"
        var fields: [ProtoFieldDescriptor] = []
        var options: [ProtoOption] = []

        var i = startIndex + 1
        if !firstLine.contains("{") {
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                i += 1
                if l.contains("{") { break }
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("}") && !line.contains("{") {
                return (ProtoMessageDescriptor(name: name, fullName: fullName, fields: fields, options: options), i + 1)
            }

            if line.hasPrefix("option ") || line.starts(with: "option\t") {
                if let opt = parseOption(from: line) {
                    options.append(opt)
                }
                i += 1
                continue
            }

            // 解析 message 字段: repeated string tags = 1 [json_name = "..."];
            if line.contains("=") && line.contains(";") {
                if let field = parseField(from: line) {
                    fields.append(field)
                }
            }

            i += 1
        }

        return (ProtoMessageDescriptor(name: name, fullName: fullName, fields: fields, options: options), i)
    }

    // MARK: - Enum 解析

    private func parseEnum(lines: [String], startIndex: Int) -> (ProtoEnumDescriptor, Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let cleanFirst = (firstLine.components(separatedBy: "//").first ?? firstLine).trimmingCharacters(in: .whitespaces)
        let name = cleanFirst
            .replacingOccurrences(of: "enum", with: "")
            .replacingOccurrences(of: "{", with: "")
            .trimmingCharacters(in: .whitespaces)

        var values: [String: Int] = [:]
        var i = startIndex + 1
        if !firstLine.contains("{") {
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                i += 1
                if l.contains("{") { break }
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("}") && !line.contains("{") {
                return (ProtoEnumDescriptor(name: name, values: values), i + 1)
            }

            // 例如: STATUS_OK = 0;
            if line.contains("=") && line.contains(";") {
                let clean = line.prefix(while: { $0 != ";" })
                let parts = clean.split(separator: "=")
                if parts.count == 2 {
                    let k = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let vStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    if let v = Int(vStr) {
                        values[k] = v
                    }
                }
            }
            i += 1
        }

        return (ProtoEnumDescriptor(name: name, values: values), i)
    }

    // MARK: - Field 与 Option 辅助解析

    private func parseField(from rawLine: String) -> ProtoFieldDescriptor? {
        let clean = rawLine.prefix(while: { $0 != ";" })
        var fieldOptions: [ProtoOption] = []

        var corePart = String(clean)
        // 提取中括号内的字段选项 [(validate.rules)...]
        if let bracketStart = clean.firstIndex(of: "["), let bracketEnd = clean.lastIndex(of: "]") {
            let optStr = String(clean[clean.index(after: bracketStart)..<bracketEnd])
            corePart = String(clean[..<bracketStart])
            fieldOptions.append(contentsOf: parseBracketOptions(optStr))
        }

        let tokens = corePart.split(separator: "=")
        guard tokens.count == 2 else { return nil }

        let leftTokens = tokens[0].trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard let number = Int(tokens[1].trimmingCharacters(in: .whitespaces)) else { return nil }

        var isRepeated = false
        var typeStr = ""
        var nameStr = ""

        if leftTokens.count >= 3 && leftTokens[0] == "repeated" {
            isRepeated = true
            typeStr = String(leftTokens[1])
            nameStr = String(leftTokens[2])
        } else if leftTokens.count >= 2 {
            typeStr = String(leftTokens[0])
            nameStr = String(leftTokens[1])
        } else {
            return nil
        }

        let kind = mapKind(typeStr)
        return ProtoFieldDescriptor(
            name: nameStr,
            number: number,
            kind: kind,
            isRepeated: isRepeated,
            options: fieldOptions
        )
    }

    private func mapKind(_ str: String) -> ProtoFieldKind {
        switch str {
        case "string": return .string
        case "int32": return .int32
        case "int64": return .int64
        case "uint32": return .uint32
        case "uint64": return .uint64
        case "float": return .float
        case "double": return .double
        case "bool": return .bool
        case "bytes": return .bytes
        default:
            if str.starts(with: "map<") { return .mapType }
            return .message
        }
    }

    private func parseOption(from line: String) -> ProtoOption? {
        // option (google.api.http) = { post: "/v1/orders" };
        // option (require_auth) = true;
        guard line.contains("option") && line.contains("=") else { return nil }
        let clean = line
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "option ", with: "")
            .replacingOccurrences(of: ";", with: "")

        let parts = clean.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let optName = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let optVal = String(parts[1]).trimmingCharacters(in: .whitespaces)

        return ProtoOption(name: optName, value: optVal)
    }

    private func parseBracketOptions(_ str: String) -> [ProtoOption] {
        // (validate.rules).string.email = true, (my_custom) = "val"
        var list: [ProtoOption] = []
        let items = str.split(separator: ",")
        for item in items {
            let kv = item.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let k = String(kv[0]).trimmingCharacters(in: .whitespaces)
                let v = String(kv[1]).trimmingCharacters(in: .whitespaces)
                list.append(ProtoOption(name: k, value: v))
            }
        }
        return list
    }
}
