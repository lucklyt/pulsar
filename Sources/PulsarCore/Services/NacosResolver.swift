import Foundation

/// Nacos 实例数据结构
public struct NacosInstance: Codable {
    public let ip: String
    public let port: Int
    public let healthy: Bool
    public let enabled: Bool
    public let weight: Double?
}

public struct NacosInstanceList: Codable {
    public let hosts: [NacosInstance]
}

/// Nacos 服务发现解析器 (继承并优化 lucklyt/wombat 的 Nacos 扩展能力)
public final class NacosResolver {
    public static let shared = NacosResolver()
    private let urlSession: URLSession

    public init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 10.0
        self.urlSession = URLSession(configuration: config)
    }

    /// 解析形如 nacos://host1:8848,host2:8848/namespace/serviceName?username=xxx&password=yyy
    /// 或通过 NacosConfig 解析出可直连的 "ip:port"
    public func resolve(address: String) async throws -> String {
        guard address.starts(with: "nacos://") else {
            return address
        }

        let raw = String(address.dropFirst("nacos://".count))
        guard let slashIndex = raw.firstIndex(of: "/") else {
            throw NSError(domain: "NacosResolver", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Nacos URI format: missing /namespace/serviceName"])
        }

        let hostsPart = String(raw[..<slashIndex])
        let pathAndQuery = String(raw[raw.index(after: slashIndex)...])

        var namespace = "public"
        var serviceName = ""
        var queryParams: [String: String] = [:]

        // 解析 path 与 query
        let components = pathAndQuery.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true)
        let pathParts = components[0].split(separator: "/", omittingEmptySubsequences: true)

        if pathParts.count >= 2 {
            namespace = String(pathParts[0])
            serviceName = String(pathParts[1])
        } else if pathParts.count == 1 {
            serviceName = String(pathParts[0])
        }

        if components.count > 1 {
            let queryString = String(components[1])
            for item in queryString.split(separator: "&") {
                let kv = item.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let k = String(kv[0])
                    let v = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    queryParams[k] = v
                }
            }
        }

        let hosts = hostsPart.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !hosts.isEmpty else {
            throw NSError(domain: "NacosResolver", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Nacos cluster host specified"])
        }

        return try await resolveFromCluster(
            hosts: hosts,
            namespace: namespace,
            serviceName: serviceName,
            username: queryParams["username"],
            password: queryParams["password"],
            groupName: queryParams["groupName"] ?? "DEFAULT_GROUP"
        )
    }

    /// 从 Nacos 集群拉取实例列表
    public func resolveFromCluster(
        hosts: [String],
        namespace: String,
        serviceName: String,
        username: String? = nil,
        password: String? = nil,
        groupName: String = "DEFAULT_GROUP"
    ) async throws -> String {
        var lastError: Error?

        for host in hosts {
            do {
                let target = try await queryNacosHost(
                    host: host,
                    namespace: namespace,
                    serviceName: serviceName,
                    username: username,
                    password: password,
                    groupName: groupName
                )
                return target
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? NSError(domain: "NacosResolver", code: 503, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve healthy instances from all Nacos cluster nodes"])
    }

    private func queryNacosHost(
        host: String,
        namespace: String,
        serviceName: String,
        username: String?,
        password: String?,
        groupName: String
    ) async throws -> String {
        // 兼容 /nacos 路径和根路径两种部署规范
        let contextPaths = ["/nacos", ""]

        for context in contextPaths {
            guard var urlComponents = URLComponents(string: "http://\(host)\(context)/v1/ns/instance/list") else {
                continue
            }

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "serviceName", value: serviceName),
                URLQueryItem(name: "groupName", value: groupName),
                URLQueryItem(name: "healthyOnly", value: "true")
            ]

            if namespace != "public" && !namespace.isEmpty {
                queryItems.append(URLQueryItem(name: "namespaceId", value: namespace))
            }

            if let u = username, !u.isEmpty {
                queryItems.append(URLQueryItem(name: "username", value: u))
            }
            if let p = password, !p.isEmpty {
                queryItems.append(URLQueryItem(name: "password", value: p))
            }

            urlComponents.queryItems = queryItems
            guard let url = urlComponents.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }

                let decoder = JSONDecoder()
                let list = try decoder.decode(NacosInstanceList.self, from: data)
                let healthyInstances = list.hosts.filter { $0.healthy && $0.enabled }

                if let chosen = healthyInstances.randomElement() {
                    return "\(chosen.ip):\(chosen.port)"
                }
            } catch {
                continue
            }
        }

        throw NSError(domain: "NacosResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "No healthy instance found on \(host) for service \(serviceName)"])
    }
}
