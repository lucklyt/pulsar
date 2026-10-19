import SwiftUI

/// 主界面：Bruno 风格 3 栏式原生 macOS 布局 (Sidebar + TabBar + 动态分栏 Request/Response + 快捷环境悬浮窗)
public struct MainView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState = AppState()) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .frame(minWidth: 230, idealWidth: 260, maxWidth: 340)
        } detail: {
            VStack(spacing: 0) {
                // 1. Bruno 风格多标签栏
                TabBarView(appState: appState)

                Divider()

                // 2. 主请求与响应区域
                if let activeReq = appState.activeRequest {
                    let requestBinding = appState.activeRequestBinding() ?? Binding<RequestModel>(
                        get: { appState.activeRequest ?? activeReq },
                        set: { appState.updateActiveRequest($0) }
                    )

                    VStack(spacing: 0) {
                        // 顶部地址与执行条
                        RequestHeaderView(request: requestBinding, appState: appState)

                        Divider()

                        // Bruno 风格灵活分栏：支持左右并排 (HSplitView) 与上下并排 (VSplitView)
                        if appState.layoutMode == .horizontal {
                            HSplitView {
                                RequestEditorView(request: requestBinding, appState: appState)
                                    .frame(minWidth: 350, idealWidth: 480)

                                ResponseInspectorView(
                                    response: appState.activeResponse,
                                    streamEvents: appState.activeStreamEvents,
                                    currentRequest: activeReq,
                                    isExecuting: appState.isExecuting,
                                    appState: appState
                                )
                                .frame(minWidth: 350, idealWidth: 480)
                            }
                        } else {
                            VSplitView {
                                RequestEditorView(request: requestBinding, appState: appState)
                                    .frame(minHeight: 240, idealHeight: 320)

                                ResponseInspectorView(
                                    response: appState.activeResponse,
                                    streamEvents: appState.activeStreamEvents,
                                    currentRequest: activeReq,
                                    isExecuting: appState.isExecuting,
                                    appState: appState
                                )
                                .frame(minHeight: 240, idealHeight: 320)
                            }
                        }
                    }
                } else {
                    emptyWorkspaceView
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // 生产环境安全高亮徽标 (Bruno 风格警示，防止在生产环境误操作)
                if let activeEnv = appState.activeEnvironment, activeEnv.isProduction {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 11))
                        Text("PROD")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(5)
                    .help("当前已连接生产环境 [\(activeEnv.name)]，所有调用将作用于真实线上！")
                }

                // 环境快速切换下拉菜单 (带环境识别色圆点)
                Picker("", selection: Binding<UUID?>(
                    get: { appState.workspace.activeEnvironmentId },
                    set: { appState.switchEnvironment(id: $0) }
                )) {
                    Text("未选择环境 (No Env)").tag(nil as UUID?)
                    Divider()
                    ForEach(appState.workspace.environments) { env in
                        HStack {
                            Circle()
                                .fill(Color(hex: env.colorHex))
                                .frame(width: 8, height: 8)
                            Text(env.name)
                        }
                        .tag(env.id as UUID?)
                    }
                }
                .frame(width: 160)

                // Bruno 标志性 Quick Eye 环境变量速览按钮
                Button(action: {
                    appState.isQuickEnvPopoverPresented.toggle()
                }) {
                    Image(systemName: "eye")
                        .foregroundColor(appState.activeEnvironment != nil ? .accentColor : .secondary)
                }
                .help("查看当前环境活动变量 (Quick View)")
                .popover(isPresented: $appState.isQuickEnvPopoverPresented) {
                    QuickEnvironmentPopover(appState: appState)
                }

                // 布局切换按键 (左右 / 上下)
                Button(action: {
                    withAnimation {
                        appState.layoutMode = appState.layoutMode == .horizontal ? .vertical : .horizontal
                    }
                }) {
                    Image(systemName: appState.layoutMode == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                }
                .help("切换编辑器与响应面板布局 (左右并排 / 上下并排)")

                // 全局极速跳转 (⌘P Quick Open)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.isQuickOpenPresented.toggle()
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("p", modifiers: .command)
                .help("全局极速跳转到请求、服务或方法 (⌘P)")

                // 集合批量自动化运行器 (Collection Runner ⌘⇧R)
                Button(action: {
                    if let firstCol = appState.workspace.collections.first {
                        appState.activeRunnerConfig = CollectionRunConfig(
                            collectionId: firstCol.id,
                            folderId: nil,
                            collectionName: firstCol.name,
                            folderName: nil,
                            environmentId: appState.workspace.activeEnvironmentId
                        )
                    }
                }) {
                    Image(systemName: "play.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("打开集合批量自动化运行器 (Collection Runner ⌘⇧R)")

                // Proto 仓库与 Import Path 配置按键 (⌘⇧P)
                Button(action: {
                    appState.isProtoExplorerPresented = true
                }) {
                    Image(systemName: "doc.badge.gearshape")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("打开本地 Proto 仓库与 Import Path 路径管理 (⌘⇧P)")

                // 环境管理模态弹窗按键
                Button(action: {
                    appState.isEnvironmentModalPresented = true
                }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("管理全部环境与敏感变量")

                // 新建请求按键
                Button(action: {
                    appState.createNewRequest()
                }) {
                    Image(systemName: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("新建 gRPC 请求 (⌘N)")
            }
        }
        .sheet(isPresented: $appState.isEnvironmentModalPresented) {
            EnvironmentManagerView(appState: appState)
        }
        .sheet(isPresented: $appState.isProtoExplorerPresented) {
            ProtoExplorerView(appState: appState)
                .frame(minWidth: 880, minHeight: 560)
        }
        .sheet(item: Binding<CollectionRunConfig?>(
            get: { appState.activeRunnerConfig },
            set: { appState.activeRunnerConfig = $0 }
        )) { config in
            CollectionRunnerView(
                appState: appState,
                isPresented: Binding(
                    get: { appState.activeRunnerConfig != nil },
                    set: { if !$0 { appState.activeRunnerConfig = nil } }
                ),
                config: config
            )
        }
        .overlay {
            if appState.isQuickOpenPresented {
                QuickOpenPaletteView(appState: appState, isPresented: $appState.isQuickOpenPresented)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var emptyWorkspaceView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 46))
                .foregroundColor(.accentColor)

            Text("欢迎使用 Pulsar")
                .font(.system(size: 20, weight: .bold))

            Text("macOS 原生高性能 gRPC / Protobuf 调试测试客户端")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Button("新建 gRPC 请求") {
                appState.createNewRequest()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
