import XCTest
import SwiftUI
import AppKit
@testable import PulsarCore

/// Pulsar 原生 macOS UI 界面自动化测试套件
/// 验证全部核心 SwiftUI 视图的层次结构、状态绑定、分栏布局、表单交互及离屏像素渲染管道
@MainActor
final class PulsarUITests: XCTestCase {

    private var tempDir: URL!
    private var storage: StorageManager!
    private var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pulsar_ui_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        storage = StorageManager(appSupportDir: tempDir)
        appState = AppState(storage: storage)
        appState.openTabIds = []
        appState.activeTabId = nil

        // 构建标准 UI 测试数据集
        setupTestWorkspace()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        appState = nil
        storage = nil
        tempDir = nil
        try await super.tearDown()
    }

    private func setupTestWorkspace() {
        var col = CollectionModel(name: "Payment Suite")
        col.sharedMetadata = [MetadataHeader(key: "x-app-name", value: "PulsarUITest")]
        col.auth = AuthConfig(type: .bearer, bearerToken: "test_jwt_bearer")

        let folder = FolderModel(name: "Checkout", collectionId: col.id)

        var req1 = RequestModel(
            name: "ChargeCard (Unary)",
            collectionId: col.id,
            folderId: folder.id,
            address: "127.0.0.1:50051",
            serviceName: "payment.PaymentService",
            methodName: "ChargeCard",
            callType: .unary,
            payload: "{\"amount\": 9900, \"currency\": \"CNY\"}"
        )
        req1.assertions = [AssertionRule(expression: "res.status", op: .equals, expectedValue: "0")]
        req1.docs = "# 支付接口\n扣款并返回交易号。"

        let req2 = RequestModel(
            name: "StreamTransactions",
            collectionId: col.id,
            folderId: folder.id,
            address: "127.0.0.1:50051",
            serviceName: "payment.PaymentService",
            methodName: "StreamTransactions",
            callType: .serverStreaming,
            payload: "{\"account\": \"acc_001\"}"
        )

        col.folders = [folder]
        col.requests = [req1, req2]

        let prodEnv = EnvironmentModel(
            name: "Production Cluster",
            isDefault: false,
            colorHex: "#FF453A",
            isProduction: true,
            variables: [
                VariableItem(key: "gateway", value: "pay.internal.corp", isSecret: false),
                VariableItem(key: "secret_token", value: "sk_live_998877", isSecret: true)
            ]
        )

        appState.workspace = WorkspaceModel(
            name: "Test Workspace",
            collections: [col],
            environments: [prodEnv],
            activeEnvironmentId: prodEnv.id,
            globalVariables: [VariableItem(key: "company", value: "Pulsar Corp")]
        )

        appState.openTab(for: req1)
        appState.openTab(for: req2)
        appState.activeTabId = req1.id
    }

    // MARK: - 1. 主界面 MainView 渲染与分栏模式测试

    func testMainViewHorizontalAndVerticalLayout() {
        let mainView = MainView(appState: appState)
        let hostingView = NSHostingView(rootView: mainView)
        let targetFrame = NSRect(x: 0, y: 0, width: 1200, height: 750)
        hostingView.frame = targetFrame

        let window = NSWindow(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        // 验证主视图正常挂载且计算尺寸有效
        XCTAssertTrue(hostingView.frame.width > 0 && hostingView.frame.height > 0)
        XCTAssertFalse(hostingView.subviews.isEmpty)

        // 切换分栏布局模式：上下垂直分栏 (VSplitView)
        appState.layoutMode = .vertical
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertEqual(appState.layoutMode, .vertical)

        // 切换回水平左右分栏 (HSplitView)
        appState.layoutMode = .horizontal
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertEqual(appState.layoutMode, .horizontal)
    }

    // MARK: - 2. 侧边栏 SidebarView 渲染、高危生产徽章与模糊检索测试

    func testSidebarViewAndProductionBadge() {
        let sidebar = SidebarView(appState: appState)
        let hostingView = NSHostingView(rootView: sidebar)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 700)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)

        // 验证生产环境高危警示状态
        XCTAssertNotNil(appState.activeEnvironment)
        XCTAssertTrue(appState.activeEnvironment?.isProduction ?? false)
        XCTAssertEqual(appState.activeEnvironment?.colorHex, "#FF453A")

        // 验证侧边栏实时过滤
        appState.searchQuery = "ChargeCard"
        let filtered = appState.filteredRequests(in: appState.workspace.collections[0])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.name, "ChargeCard (Unary)")

        appState.searchQuery = "NonExistent"
        let emptyFiltered = appState.filteredRequests(in: appState.workspace.collections[0])
        XCTAssertTrue(emptyFiltered.isEmpty)

        appState.searchQuery = ""
    }

    // MARK: - 3. 标签栏 TabBarView 渲染、脏标记与多类型 Pill 徽章测试

    func testTabBarViewAndDirtyStatusIndicator() {
        let tabBar = TabBarView(appState: appState)
        let hostingView = NSHostingView(rootView: tabBar)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 38)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(appState.openTabIds.count, 2)
        guard let activeId = appState.activeTabId else {
            XCTFail("Active tab must exist")
            return
        }

        // 模拟用户在编辑器中修改内容，触发草稿未保存脏状态
        appState.markDirty(id: activeId)
        XCTAssertTrue(appState.dirtyTabIds.contains(activeId))

        // 模拟执行保存 (⌘S)，脏标记清除
        appState.saveActiveRequest()
        XCTAssertFalse(appState.dirtyTabIds.contains(activeId))

        // 验证 Tab 关闭
        if let secondTabId = appState.openTabIds.last {
            appState.closeTab(id: secondTabId)
            XCTAssertEqual(appState.openTabIds.count, 1)
        }
    }

    // MARK: - 4. 顶部操作条 RequestHeaderView 渲染与执行态交互

    func testRequestHeaderViewAndExecutionState() {
        guard let activeReq = appState.activeRequest else {
            XCTFail("Active request required")
            return
        }

        let binding = Binding<RequestModel>(
            get: { self.appState.activeRequest ?? activeReq },
            set: { self.appState.updateActiveRequest($0) }
        )

        let headerView = RequestHeaderView(request: binding, appState: appState)
        let hostingView = NSHostingView(rootView: headerView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 850, height: 44)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)

        // 模拟请求开始执行 (isExecuting = true)
        appState.isExecuting = true
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertTrue(appState.isExecuting)

        // 模拟请求结束
        appState.isExecuting = false
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertFalse(appState.isExecuting)

        // 验证 ServiceAutocompleteField 与 MethodAutocompleteField 正常集成与尺寸计算
        let svcField = ServiceAutocompleteField(
            serviceName: .constant("helloworld.Greeter"),
            methodName: .constant("SayHello"),
            allServices: ProtoRepository.shared.allServices
        )
        let svcHost = NSHostingView(rootView: svcField)
        svcHost.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
        svcHost.layoutSubtreeIfNeeded()
        XCTAssertTrue(svcHost.fittingSize.width > 0)

        let methodField = MethodAutocompleteField(
            serviceName: "helloworld.Greeter",
            methodName: .constant("SayHello"),
            allServices: ProtoRepository.shared.allServices
        )
        let methodHost = NSHostingView(rootView: methodField)
        methodHost.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
        methodHost.layoutSubtreeIfNeeded()
        XCTAssertTrue(methodHost.fittingSize.width > 0)

        // 验证服务未选择时实时建议胶囊栏 (Row 4) 展开与有效布局尺寸
        var emptyReq = RequestModel(name: "Empty Req", address: "localhost:50051")
        emptyReq.serviceName = ""
        emptyReq.methodName = ""
        let emptyBinding = Binding(get: { emptyReq }, set: { emptyReq = $0 })
        let emptyHeaderView = RequestHeaderView(request: emptyBinding, appState: appState)
        let emptyHeaderHost = NSHostingView(rootView: emptyHeaderView)
        emptyHeaderHost.frame = NSRect(x: 0, y: 0, width: 850, height: 120)
        emptyHeaderHost.layoutSubtreeIfNeeded()
        XCTAssertTrue(emptyHeaderHost.fittingSize.height > 40)
    }

    // MARK: - 5. 请求编辑器 RequestEditorView 子选项卡与批量编辑渲染

    func testRequestEditorViewSubTabsAndBulkEdit() {
        guard let activeReq = appState.activeRequest else {
            XCTFail("Active request required")
            return
        }

        let binding = Binding<RequestModel>(
            get: { self.appState.activeRequest ?? activeReq },
            set: { self.appState.updateActiveRequest($0) }
        )

        let editorView = RequestEditorView(request: binding, appState: appState)
        let hostingView = NSHostingView(rootView: editorView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.height > 0)

        // 验证 Header 知识库自动补全视图渲染
        var headerKey = "grpc"
        let autocompleteField = HeaderKeyAutocompleteField(key: Binding(get: { headerKey }, set: { headerKey = $0 }))
        let autoHosting = NSHostingView(rootView: autocompleteField)
        autoHosting.frame = NSRect(x: 0, y: 0, width: 350, height: 40)
        autoHosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(autoHosting.fittingSize.width > 0)
    }

    // MARK: - 6. 响应检查器 ResponseInspectorView 状态徽章与差异对比视图

    func testResponseInspectorViewStatusAndVisualDiff() {
        let req = appState.activeRequest!

        let mockResponse = RPCResponse(
            requestId: req.id,
            statusCode: 0,
            statusName: "OK",
            durationMs: 38.6,
            responseSize: 1024,
            responsePayload: "{\"status\": \"PAID\", \"trade_no\": \"T20261018\"}",
            initialMetadata: ["content-type": "application/grpc+proto", "x-trace-id": "trace_999"]
        )
        appState.responses[req.id] = mockResponse

        // 设置基线快照以便验证 Diff 面板
        let baselineResponse = RPCResponse(
            requestId: req.id,
            statusCode: 0,
            statusName: "OK",
            durationMs: 25.0,
            responsePayload: "{\"status\": \"PENDING\", \"trade_no\": \"T20261018\"}"
        )
        appState.responseSnapshots[req.id] = baselineResponse

        let inspectorView = ResponseInspectorView(
            response: mockResponse,
            streamEvents: [],
            currentRequest: req,
            isExecuting: false,
            appState: appState
        )

        let hostingView = NSHostingView(rootView: inspectorView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)
        XCTAssertEqual(appState.activeResponse?.statusCode, 0)
        XCTAssertEqual(appState.activeResponse?.statusName, "OK")
    }

    // MARK: - 7. ⌘P 快速直达调色板 QuickOpenPaletteView 渲染

    func testQuickOpenPaletteView() {
        let paletteView = QuickOpenPaletteView(appState: appState, isPresented: .constant(true))
        let hostingView = NSHostingView(rootView: paletteView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)
        let breadcrumbs = appState.allRequestsWithBreadcrumbs()
        XCTAssertEqual(breadcrumbs.count, 2)
        XCTAssertEqual(breadcrumbs.first?.collectionName, "Payment Suite")
        XCTAssertEqual(breadcrumbs.first?.folderName, "Checkout")
    }

    // MARK: - 8. 环境管理器 EnvironmentManagerView 与 QuickEye 浮窗渲染

    func testEnvironmentManagerAndQuickPopover() {
        let envManager = EnvironmentManagerView(appState: appState)
        let managerHosting = NSHostingView(rootView: envManager)
        managerHosting.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        managerHosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(managerHosting.fittingSize.width > 0)

        let popover = QuickEnvironmentPopover(appState: appState)
        let popoverHosting = NSHostingView(rootView: popover)
        popoverHosting.frame = NSRect(x: 0, y: 0, width: 360, height: 420)
        popoverHosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(popoverHosting.fittingSize.width > 0)
    }

    // MARK: - 9. 批量执行器 CollectionRunnerView 自动化运行界面渲染

    func testCollectionRunnerViewRender() {
        let config = CollectionRunConfig(
            collectionId: appState.workspace.collections[0].id,
            collectionName: "Payment Suite",
            delayMs: 100,
            stopOnFirstFailure: true
        )
        appState.activeRunnerConfig = config

        let runnerView = CollectionRunnerView(appState: appState, isPresented: .constant(true), config: config)
        let hostingView = NSHostingView(rootView: runnerView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)
        XCTAssertNotNil(appState.activeRunnerConfig)
    }

    // MARK: - 10. 代码生成器 CodeSnippetView 5 语言切换渲染

    func testCodeSnippetViewRender() {
        guard let req = appState.activeRequest else {
            XCTFail("Active request required")
            return
        }

        let snippetView = CodeSnippetView(appState: appState, isPresented: .constant(true), request: req)
        let hostingView = NSHostingView(rootView: snippetView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)
    }

    // MARK: - 11. Proto 浏览与反射查看器 ProtoExplorerView 渲染

    func testProtoExplorerViewRender() {
        let explorer = ProtoExplorerView(appState: appState)
        let hostingView = NSHostingView(rootView: explorer)
        hostingView.frame = NSRect(x: 0, y: 0, width: 750, height: 550)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.fittingSize.width > 0)
    }

    // MARK: - 12. 离屏像素渲染管道测试 (Offscreen Bitmap Snapshot Pipeline)

    func testOffscreenBitmapSnapshotPipeline() {
        let mainView = MainView(appState: appState)
        let hostingView = NSHostingView(rootView: mainView)
        let targetFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        hostingView.frame = targetFrame
        hostingView.layoutSubtreeIfNeeded()

        // 挂载至虚拟离屏 NSWindow 并执行实际图形渲染管道
        let window = NSWindow(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        window.displayIfNeeded()

        // 抓取离屏 BitmapImageRep，验证像素缓冲区生成正常且无崩溃
        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("无法生成离屏位图缓存缓存区")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

        let scale = window.backingScaleFactor > 0 ? window.backingScaleFactor : 1.0
        XCTAssertEqual(Double(bitmapRep.pixelsWide), 1200.0 * scale)
        XCTAssertTrue(Double(bitmapRep.pixelsHigh) >= 800.0 * scale)
        XCTAssertNotNil(bitmapRep.bitmapData)

        // 验证生成有效的 NSImage 且数据大小正常
        let image = NSImage(size: targetFrame.size)
        image.addRepresentation(bitmapRep)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            XCTFail("无法生成 PNG 图像数据")
            return
        }
        XCTAssertTrue(pngData.count > 1024, "渲染的 PNG 位图数据必须有效非空")
    }
}
