import Foundation

/// 集合自动化批量测试执行引擎 (Collection Runner Engine)
public final class CollectionRunnerEngine {
    public static let shared = CollectionRunnerEngine()

    public init() {}

    /// 批量执行请求列表
    /// - Parameters:
    ///   - config: 运行配置 (包含延时、熔断策略等)
    ///   - requests: 待执行的请求序列
    ///   - baseEnvironment: 初始环境变量
    ///   - globalVariables: 全局变量
    ///   - resolveEffectiveConfig: 解析层级继承的闭包
    ///   - isCancelled: 外部取消检测闭包
    ///   - onProgress: 进度回调 (当前索引, 总数, 最新执行结果)
    /// - Returns: 测试运行汇总结果
    public func run(
        config: CollectionRunConfig,
        requests: [RequestModel],
        baseEnvironment: EnvironmentModel?,
        globalVariables: [VariableItem],
        resolveEffectiveConfig: (RequestModel) -> AppState.EffectiveRequestConfig,
        isCancelled: () -> Bool = { false },
        onProgress: ((Int, Int, RequestRunResult) -> Void)? = nil
    ) async -> CollectionRunSummary {
        let startTime = Date()
        var runResults: [RequestRunResult] = []

        // 运行期会话环境副本：支持请求间后置变量动态链式传递 (Chaining)
        var sessionEnvironment = baseEnvironment ?? EnvironmentModel(name: "Session Runner")

        let total = requests.count

        for (index, rawReq) in requests.enumerated() {
            if isCancelled() {
                break
            }

            // 1. 延时控制 (Delay between requests)
            if index > 0 && config.delayMs > 0 {
                let delayNanos = UInt64(config.delayMs * 1_000_000)
                try? await Task.sleep(nanoseconds: delayNanos)
            }

            if isCancelled() {
                break
            }

            // 2. 解析继承层级 (Request -> Folder -> Collection)
            let effConfig = resolveEffectiveConfig(rawReq)
            let effReq = effConfig.effectiveRequest

            // 3. 执行 gRPC 调用 (使用携带最新链路变量的 sessionEnvironment)
            let resp = await GRPCClientEngine.shared.execute(
                request: effReq,
                activeEnvironment: sessionEnvironment,
                globalVariables: globalVariables
            )

            // 4. 断言评估 (Bruno Assertions)
            let assertionResults = AssertionEngine.shared.evaluateAssertions(
                rules: rawReq.assertions,
                response: resp
            )

            // 5. 变量提取与链路更新 (Post-Response Variable Chaining)
            let extracted = AssertionEngine.shared.extractVariables(
                rules: rawReq.responseVars,
                response: resp
            )

            for (k, v) in extracted {
                if let vIdx = sessionEnvironment.variables.firstIndex(where: { $0.key == k }) {
                    sessionEnvironment.variables[vIdx].value = v
                } else {
                    sessionEnvironment.variables.append(VariableItem(key: k, value: v, isEnabled: true))
                }
            }

            // 6. 判定成功条件：gRPC 状态码为 0 (OK) 且 所有已启用的断言全部通过
            let assertsPassed = assertionResults.allSatisfy { $0.passed }
            let isSuccess = (resp.statusCode == 0) && assertsPassed

            let runResult = RequestRunResult(
                requestId: rawReq.id,
                requestName: rawReq.name,
                serviceName: rawReq.serviceName,
                methodName: rawReq.methodName,
                callType: rawReq.callType,
                durationMs: resp.durationMs,
                statusCode: resp.statusCode,
                statusName: resp.statusName,
                assertionResults: assertionResults,
                extractedVariables: extracted,
                isSuccess: isSuccess,
                responsePayload: resp.responsePayload,
                errorMessage: resp.errorMessage
            )

            runResults.append(runResult)
            onProgress?(index + 1, total, runResult)

            // 7. 熔断策略：若开启失败即停止且当前用例失败，则中止后续执行
            if config.stopOnFirstFailure && !isSuccess {
                break
            }
        }

        return CollectionRunSummary(
            collectionName: config.collectionName,
            folderName: config.folderName,
            startedAt: startTime,
            completedAt: Date(),
            results: runResults
        )
    }
}
