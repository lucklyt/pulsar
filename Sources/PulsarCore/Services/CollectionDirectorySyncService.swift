import Foundation

/// 类似 Bruno 的 Git 友好型多文件目录同步与导入导出服务
/// 将集合、文件夹、请求用例与环境变量分拆为清晰的独立 JSON 文件，极大降低团队 Git 协同合并冲突
public final class CollectionDirectorySyncService {
    public static let shared = CollectionDirectorySyncService()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    // MARK: - 目录导出数据模型结构

    public struct CollectionMetaFile: Codable {
        public var version: String = "pulsar/v1"
        public var name: String
        public var sharedMetadata: [MetadataHeader]
        public var auth: AuthConfig
        public var security: TLSConfig
        public var timeoutSeconds: Double

        public init(from collection: CollectionModel) {
            self.name = collection.name
            self.sharedMetadata = collection.sharedMetadata
            self.auth = collection.auth
            self.security = collection.security
            self.timeoutSeconds = collection.timeoutSeconds
        }
    }

    public struct FolderMetaFile: Codable {
        public var name: String
        public var sharedMetadata: [MetadataHeader]
        public var auth: AuthConfig

        public init(from folder: FolderModel) {
            self.name = folder.name
            self.sharedMetadata = folder.sharedMetadata
            self.auth = folder.auth
        }
    }

    // MARK: - 导出方法

    /// 将集合完整导出为 Git 友好的多文件目录结构
    /// - Parameters:
    ///   - collection: 待导出的集合模型
    ///   - environments: 关联的环境模型（可选）
    ///   - parentDirectory: 目标父目录
    /// - Returns: 实际创建的集合文件夹 URL
    @discardableResult
    public func exportCollection(
        _ collection: CollectionModel,
        environments: [EnvironmentModel] = [],
        to parentDirectory: URL
    ) throws -> URL {
        let safeCollectionName = sanitizeFileName(collection.name)
        let collectionDir = parentDirectory.appendingPathComponent(safeCollectionName, isDirectory: true)

        try fileManager.createDirectory(at: collectionDir, withIntermediateDirectories: true)

        // 1. 写入 collection.json
        let collectionMeta = CollectionMetaFile(from: collection)
        let metaData = try encoder.encode(collectionMeta)
        try metaData.write(to: collectionDir.appendingPathComponent("collection.json"), options: .atomic)

        // 2. 导出每个文件夹及其包含的请求
        var processedRequestIds = Set<UUID>()

        for folder in collection.folders {
            let safeFolderName = sanitizeFileName(folder.name)
            let folderDir = collectionDir.appendingPathComponent(safeFolderName, isDirectory: true)
            try fileManager.createDirectory(at: folderDir, withIntermediateDirectories: true)

            // 写入 folder.json
            let folderMeta = FolderMetaFile(from: folder)
            let folderData = try encoder.encode(folderMeta)
            try folderData.write(to: folderDir.appendingPathComponent("folder.json"), options: .atomic)

            // 导出该文件夹下的所有请求
            let folderRequests = collection.requests.filter { $0.folderId == folder.id || folder.requestIds.contains($0.id) }
            for req in folderRequests {
                processedRequestIds.insert(req.id)
                let safeReqName = sanitizeFileName(req.name)
                let reqFile = folderDir.appendingPathComponent("\(safeReqName).grpc.json")
                let reqData = try encoder.encode(req)
                try reqData.write(to: reqFile, options: .atomic)
            }
        }

        // 3. 导出根目录下的独立请求 (不属于任何文件夹)
        let rootRequests = collection.requests.filter { !processedRequestIds.contains($0.id) }
        for req in rootRequests {
            let safeReqName = sanitizeFileName(req.name)
            let reqFile = collectionDir.appendingPathComponent("\(safeReqName).grpc.json")
            let reqData = try encoder.encode(req)
            try reqData.write(to: reqFile, options: .atomic)
        }

        // 4. 导出环境配置 (支持本地 Secrets 物理隔离与自动防泄漏保护)
        if !environments.isEmpty {
            let envsDir = collectionDir.appendingPathComponent("environments", isDirectory: true)
            try fileManager.createDirectory(at: envsDir, withIntermediateDirectories: true)

            for env in environments {
                let safeEnvName = sanitizeFileName(env.name)
                var publicVars: [VariableItem] = []
                var secretVars: [VariableItem] = []

                for v in env.variables {
                    if v.isSecret {
                        // 公开版本脱敏：保留键名与开关，清空机密值，防止 Git 泄密
                        var sanitized = v
                        sanitized.value = ""
                        publicVars.append(sanitized)
                        secretVars.append(v)
                    } else {
                        publicVars.append(v)
                    }
                }

                var publicEnv = env
                publicEnv.variables = publicVars
                let envFile = envsDir.appendingPathComponent("\(safeEnvName).json")
                let envData = try encoder.encode(publicEnv)
                try envData.write(to: envFile, options: .atomic)

                // 物理独立保存机密文件
                if !secretVars.isEmpty {
                    let secFile = envsDir.appendingPathComponent("\(safeEnvName).secrets.json")
                    let secData = try encoder.encode(secretVars)
                    try secData.write(to: secFile, options: .atomic)
                }
            }

            // 5. 自动生成 .gitignore 文件，杜绝机密进入版本控制系统
            let gitignoreContent = """
            # Pulsar Environment Secrets Isolation (Auto-generated)
            # Never commit local secrets to version control
            environments/*.secrets.json
            *.secrets.json
            .env*
            """
            let gitignoreFile = collectionDir.appendingPathComponent(".gitignore")
            if !fileManager.fileExists(atPath: gitignoreFile.path) {
                try? gitignoreContent.write(to: gitignoreFile, atomically: true, encoding: .utf8)
            }
        }

        return collectionDir
    }

    // MARK: - 导入方法

    /// 从 Git 友好的目录结构恢复集合模型与环境变量
    /// - Parameter directoryURL: 包含 collection.json 的目录
    /// - Returns: 重建好的 CollectionModel 与 EnvironmentModel 列表
    public func importCollection(from directoryURL: URL) throws -> (collection: CollectionModel, environments: [EnvironmentModel]) {
        let metaFileURL = directoryURL.appendingPathComponent("collection.json")

        var collectionName = directoryURL.lastPathComponent
        var sharedMetadata: [MetadataHeader] = []
        var auth: AuthConfig = AuthConfig()
        var security: TLSConfig = TLSConfig()
        var timeoutSeconds: Double = 30.0

        if fileManager.fileExists(atPath: metaFileURL.path),
           let metaData = try? Data(contentsOf: metaFileURL),
           let meta = try? decoder.decode(CollectionMetaFile.self, from: metaData) {
            collectionName = meta.name
            sharedMetadata = meta.sharedMetadata
            auth = meta.auth
            security = meta.security
            timeoutSeconds = meta.timeoutSeconds
        }

        let newCollectionId = UUID()
        var folders: [FolderModel] = []
        var requests: [RequestModel] = []
        var environments: [EnvironmentModel] = []

        let items = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                if item.lastPathComponent == "environments" {
                    // 读取环境定义 (自动合并公开变量与本地 .secrets.json 机密文件)
                    let envFiles = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    for ef in envFiles where ef.pathExtension == "json" && !ef.lastPathComponent.contains(".secrets.json") {
                        if let d = try? Data(contentsOf: ef),
                           var env = try? decoder.decode(EnvironmentModel.self, from: d) {
                            // 检查是否存在同名本地机密文件 <env_name>.secrets.json
                            let baseName = ef.deletingPathExtension().lastPathComponent
                            let secFile = item.appendingPathComponent("\(baseName).secrets.json")
                            if fileManager.fileExists(atPath: secFile.path),
                               let secData = try? Data(contentsOf: secFile),
                               let secretItems = try? decoder.decode([VariableItem].self, from: secData) {
                                for sec in secretItems {
                                    if let idx = env.variables.firstIndex(where: { $0.key == sec.key }) {
                                        env.variables[idx].value = sec.value
                                        env.variables[idx].isSecret = true
                                    } else {
                                        env.variables.append(sec)
                                    }
                                }
                            }
                            environments.append(env)
                        }
                    }
                } else {
                    // 文件夹子目录
                    let folderId = UUID()
                    var folderName = item.lastPathComponent
                    var folderMetadata: [MetadataHeader] = []
                    var folderAuth = AuthConfig(type: .inherit)

                    let folderMetaURL = item.appendingPathComponent("folder.json")
                    if fileManager.fileExists(atPath: folderMetaURL.path),
                       let fData = try? Data(contentsOf: folderMetaURL),
                       let fMeta = try? decoder.decode(FolderMetaFile.self, from: fData) {
                        folderName = fMeta.name
                        folderMetadata = fMeta.sharedMetadata
                        folderAuth = fMeta.auth
                    }

                    var folderRequestIds: [UUID] = []

                    let reqFiles = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    for rf in reqFiles where rf.lastPathComponent.hasSuffix(".grpc.json") {
                        if let d = try? Data(contentsOf: rf),
                           var req = try? decoder.decode(RequestModel.self, from: d) {
                            req.id = UUID() // 重新生成 ID 避免跨工作空间冲突
                            req.collectionId = newCollectionId
                            req.folderId = folderId
                            folderRequestIds.append(req.id)
                            requests.append(req)
                        }
                    }

                    var folder = FolderModel(
                        id: folderId,
                        name: folderName,
                        collectionId: newCollectionId,
                        requestIds: folderRequestIds
                    )
                    folder.sharedMetadata = folderMetadata
                    folder.auth = folderAuth
                    folders.append(folder)
                }
            } else if item.lastPathComponent.hasSuffix(".grpc.json") {
                // 集合根目录下的独立请求
                if let d = try? Data(contentsOf: item),
                   var req = try? decoder.decode(RequestModel.self, from: d) {
                    req.id = UUID()
                    req.collectionId = newCollectionId
                    req.folderId = nil
                    requests.append(req)
                }
            }
        }

        var collection = CollectionModel(
            id: newCollectionId,
            name: collectionName,
            folders: folders,
            requests: requests
        )
        collection.sharedMetadata = sharedMetadata
        collection.auth = auth
        collection.security = security
        collection.timeoutSeconds = timeoutSeconds

        return (collection, environments)
    }

    // MARK: - 文件名安全清洗

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var clean = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "untitled" : clean
    }
}
