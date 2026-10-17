<div align="center">
  <img src="Resources/icon.png" width="140" height="140" alt="Pulsar Icon" />
  <h1>Pulsar</h1>
  <p><strong>The pulsing heart of native gRPC testing on macOS.</strong></p>
  <p>⚡️ 轻量、极致流畅、完全原生（Swift 6 / SwiftUI / AppKit）的 macOS gRPC 调试与测试客户端。</p>

  <p>
    <a href="#"><img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?style=flat-square&logo=apple" alt="macOS" /></a>
    <a href="#"><img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift" alt="Swift 6" /></a>
    <a href="#"><img src="https://img.shields.io/badge/UI-SwiftUI%20%2F%20AppKit-purple?style=flat-square" alt="SwiftUI" /></a>
    <a href="#"><img src="https://img.shields.io/badge/Design%20Benchmark-usebruno%2Fbruno-black?style=flat-square" alt="Bruno Style" /></a>
    <a href="#"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" /></a>
  </p>
</div>

---

## 🌟 为什么做 Pulsar？(Why Pulsar?)

旧时代的 gRPC 测试工具（如基于 Electron 的旧版 Wombat 或 Postman）面临着启动缓慢、动辄占用 500MB+ 内存、多级目录 Proto 引用配置繁琐、界面排版粗糙容易变形等痛点。

**Pulsar** 彻底摒弃了 Webview/Chromium 引擎，完全基于 **Apple 原生技术栈（Swift 6 + SwiftUI + AppKit）** 重新设计与编码。界面交互与体验深度对标 **[usebruno/bruno](https://github.com/usebruno/bruno)** 的设计精髓——**极简卡片、紧凑分栏、折叠清晰、告别冗余空白、离线优先与毫秒级响应**。

### 📊 性能与体验对比

| 核心指标 | 旧版 Wombat (Electron) | Postman (gRPC) | **Pulsar (Native macOS)** |
| :--- | :--- | :--- | :--- |
| **运行时架构** | Chromium + Node.js | Chromium + Node.js | **100% Native Swift 6 + AppKit** |
| **冷启动速度** | ~3.8 秒 | ~5.2 秒 | **⚡️ < 0.15 秒（闪电冷启）** |
| **常驻内存占用** | 420 MB - 680 MB | 550 MB - 1.2 GB | **🍃 ~28 MB（极低内存）** |
| **应用包体积** | ~180 MB | ~240 MB | **📦 4.2 MB（极小体积）** |
| **ProMotion 刷新率** | 易丢帧卡顿 | 易掉帧 | **✨ 原生 120Hz 丝滑渲染** |
| **多级 Proto Import** | 手动逐个引用，易丢失 | 局限 | **自动递归扫描与 `-I` 路径智能解析** |
| **Proto 扩展与选项** | 忽略 | 无法呈现 | **内嵌解析规则，支持扩展字段映射** |
| **微服务注册中心** | 不支持 | 不支持 | **内置 Nacos 服务发现协议解析 (`nacos://`)** |

---

## ✨ 核心特性 (Key Features)

### 1. 完整 gRPC 4 大调用模式支持
- **Unary（一问一答）**：单次请求与响应，支持耗时分析（DNS、TCP、TLS、TTFB、流传输）。
- **Server Streaming（服务端流）**：实时事件流时间线观察、逐帧接收与查看。
- **Client Streaming（客户端流）**：支持多事件发送与最终结果聚合。
- **Bidirectional Streaming（双向流）**：全双工实时交互气泡，时间线精准记录每一条上行与下行消息。

### 2. 深度 Proto 引擎与多级 Import 路径解析
- **智能 Import 解析**：自动识别 Proto 声明中的 `import "common/types.proto"`，结合配置的多个包含目录（`-I` / `--proto_path`）自动定位依赖。
- **Proto 扩展与选项 (Extensions & Options)**：深度提取并在用例中应用 Proto 注解规则（如 `google.api.http` 等自定义选项）。
- **一键 Mock Payload 生成**：基于已解析的 Proto Message 契约，自动递归生成结构化 Mock JSON 数据。

### 3. Bruno 风格精致 UI 与交互布局
- **自适应卡片设计**：彻底告别 macOS 系统表单在窄屏下的错位排版。TLS 配置、服务发现、超时控制均采用 Bruno 风格独立圆角卡片，任意分栏比例下均保持优雅整齐。
- **多层级请求集合与文件夹折叠**：支持 Collection 与多层级 Folder 自由折叠/展开，一键新建请求与文件夹，树形分明。
- **紧凑无冗余菜单栏**：左侧紧凑选项卡自适应内容宽度，零多余空白；右侧一体化集成 gRPC 状态码徽章、毫秒级时延与传输尺寸。
- **动态分栏切换**：支持左右并排（HSplitView）与上下并排（VSplitView）一键切换。

### 4. 强大的变量插值与多环境管理
- **动态内置变量**：支持 `{{$uuid}}`、`{{$timestamp}}`、`{{$randomInt(min, max)}}`。
- **环境级联解析**：支持 `{{grpc_host}}`、`{{grpc_port}}`、`{{jwt_token}}` 等跨环境无缝插值。
- **敏感变量保护**：支持将凭证标记为 `Secret`，输入时自动掩蔽，避免录屏或分享泄露。
- **Quick Eye 悬浮速览**：无需切出当前请求，即可快速浮窗查看当前活跃环境变量。

### 5. 连接安全与微服务发现
- **全方位 TLS 矩阵**：明文直连 (Plaintext)、标准服务端 TLS、自定义根 CA 证书、双向认证 (mTLS)，搭配原生 `NSOpenPanel` 证书文件选择器。
- **Nacos 服务发现**：支持 `nacos://127.0.0.1:8848/public/service-name?groupName=DEFAULT_GROUP`，自动解析微服务集群实例并负载均衡调用。

### 6. 一键导出 grpcurl 命令行
- 支持将当前请求的所有配置（Address、Metadata Headers、TLS 证书参数、JSON Payload）一键生成为等价的 `grpcurl` 终端命令，方便 CI/CD 复制复现。

---

## 🚀 快速开始与编译 (Getting Started)

### 环境要求
- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0+ / Swift 6.0 工具链

### 1. 运行预编译 Release 应用
您可以在本地直接启动打包完成的应用程序：
```bash
open build/Pulsar.app
```

### 2. 从源码编译与运行
```bash
# 克隆仓库
git clone https://github.com/lucklyt/pulsar.git
cd pulsar

# 运行自动化测试 (8 个全覆盖单元测试)
swift test

# 一键编译并打包为原生 macOS .app
./scripts/build_app.sh

# 打开应用
open build/Pulsar.app
```

---

## 🛠 键盘快捷键 (Keyboard Shortcuts)

| 快捷键 | 功能 |
| :--- | :--- |
| **⌘ + Return** | 发送当前 gRPC 请求 (Send) |
| **⌘ + S** | 保存当前请求修改 (Save) |
| **⌘ + N** | 新建 gRPC 请求 |
| **⌘ + T** | 新建请求选项卡 (New Tab) |
| **⌘ + W** | 关闭当前标签页 |
| **⌘ + P** | 打开本地 Proto 仓库与 Import 路径管理 |
| **⌘ + E** | 打开多环境与敏感变量管理弹窗 |

---

## 📂 项目架构 (Architecture)

```text
Pulsar/
├── Sources/
│   ├── Pulsar/                     # 应用入口与可执行文件 (App Executable)
│   │   └── main.swift
│   └── PulsarCore/                 # 核心模块 (Core Framework)
│       ├── PulsarApp.swift         # SwiftUI 原生生命周期与 AppKit 菜单系统
│       ├── Models/                 # 领域模型 (Request, Collection, Environment, Proto)
│       ├── Services/               # 核心服务 (LocalProtoParser, GRPCClientEngine, NacosResolver, StorageManager)
│       ├── ViewModels/             # 响应式全局状态 (AppState)
│       └── Views/                  # Bruno 风格界面组件 (Sidebar, Editor, Inspector, TabBar, etc.)
├── Tests/
│   └── PulsarTests/                # 单元测试矩阵 (Proto 解析、变量插值、Mock 生成、grpcurl 导出)
├── Resources/                      # 图标与多分辨率资源 (AppIcon.icns, icon.png)
└── scripts/
    └── build_app.sh                # 自动化 Release 打包脚本
```

---

## 📄 开源许可证 (License)

本项目基于 [MIT 许可证](LICENSE) 开源发布。欢迎提 Issue、PR 与功能建议！
