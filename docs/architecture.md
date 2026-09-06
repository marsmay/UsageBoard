# UsageBoard 架构说明与开发规范

> 本文档描述 UsageBoard macOS 端的代码组织、依赖规则和后续开发规范。它以当前 `Sources/` 代码为准。

---

## 1. 项目定位

UsageBoard 是一款 macOS menu bar 工具，用于集中展示各种 AI 服务的 API 用量和配额状态。

核心目标：

- **插件驱动**：所有用量查询逻辑由外部插件（主要是 Python 脚本）实现，app 只负责调度和展示。
- **menu bar 优先**：主入口是状态栏图标和 popover，不占 Dock 位，即开即用。
- **自动更新**：支持从远程服务器检查和下载更新，自动替换 app 并重启。
- **双语支持**：中文和英文，通过 `AppLanguage` 统一管理，切换后重启生效。

---

## 2. 技术栈

| 类别        | 选型                                                                      |
| ----------- | ------------------------------------------------------------------------- |
| 应用框架    | SwiftUI App lifecycle + AppKit（`NSStatusItem`、`NSPopover`、`NSWindow`） |
| 构建        | Swift Package Manager                                                     |
| 最低版本    | macOS 13                                                                  |
| 并发        | Swift 6 strict concurrency（`@MainActor`、`Sendable`、`Task`）            |
| 状态管理    | `ObservableObject` + `@Published`（`UsageBoardStore`）                    |
| 配置持久化  | `~/Library/Application Support/UsageBoard/config.json`（JSON 文件）       |
| 插件缓存    | `~/Library/Application Support/UsageBoard/states/` 按 `stateID` 分文件    |
| 插件执行    | `Process`（子进程），Python 插件用 `/usr/bin/env python3`                 |
| JSON 编解码 | 统一 `UsageBoardJSON.decoder()` / `UsageBoardJSON.encoder()`              |
| 本地化      | `AppLocalization`（`(key, language)` 匹配）+ 插件元数据 `field@lang` 后缀 |
| 测试        | XCTest（Core 与 App 层）+ pytest（Python 插件）                                  |
| 开机启动    | `SMAppService`（macOS 13+ Login Items）                                   |

常用验证命令：

```sh
swift build               # 编译检查
swift test                # Core 与 App 回归测试
swift build -c release    # release 构建
bash scripts/build.sh     # 本地 app 构建、签名、启动
python3 -m pytest Tests/PluginTests/ -v   # Python 插件测试
```

---

## 3. 目录结构

```
UsageBoard/
├── Package.swift                          # SPM 定义，macOS 13+，Swift 6
├── Sources/
│   ├── UsageBoardCore/                    # 核心逻辑，无 SwiftUI 依赖
│   │   ├── CodableHelpers.swift           # AnyCodingKey 和多语言翻译编解码扩展
│   │   ├── AppConfiguration.swift         # AppLanguage、AppTheme、DisplayMode、ChartMode、AppConfiguration
│   │   ├── PluginConfiguration.swift      # 参数类型、参数元数据、插件元数据、插件配置
│   │   ├── PluginOutput.swift             # UsageItem、PluginOutput、PluginChart 等
│   │   ├── PluginSnapshot.swift           # PluginSnapshotState、PluginSnapshot、PluginCachedState
│   │   ├── Protocols.swift                # ConfigStoring/PluginStateStoring/PluginExecuting/UpdateChecking 协议
│   │   ├── ConfigStore.swift              # 配置文件读写和目录路径
│   │   ├── PluginExecutor.swift           # 子进程执行插件
│   │   ├── PluginMetadataParser.swift     # 解析插件元数据注释块
│   │   ├── PluginStateStore.swift         # 插件数据缓存（内存 + 磁盘两级）
│   │   ├── PluginDisplayNames.swift       # 插件显示名去重
│   │   ├── BundledPluginInstaller.swift   # 内置插件符号链接安装
│   │   ├── UpdateChecker.swift            # 更新检查、下载、解压
│   │   ├── AppRelauncher.swift            # 退出后替换并重启
│   │   └── JSONCoding.swift               # 统一 JSON 编解码器
│   └── UsageBoardApp/                     # SwiftUI + AppKit macOS app
│       ├── UsageBoardApp.swift            # App 入口、AppDelegate、StatusItem、窗口管理
│       ├── UsageBoardStore.swift          # @MainActor ObservableObject 主状态
│       ├── AppLocalization.swift          # UI 文案国际化（@MainActor static shared 单例）
│       ├── Dashboard/                     # 主面板视图
│       │   ├── DashboardView.swift        # DashboardView、EmptyPluginsView
│       │   ├── OverviewView.swift         # OverviewView、SettingsButton、QuitButton
│       │   ├── PluginGroupView.swift      # 插件卡片
│       │   ├── UsageItemRow.swift         # 用量行、进度条
│       │   ├── TokenChartView.swift       # token 统计图容器和摘要
│       │   ├── TokenLineChartPlot.swift   # 折线图绘制和格式化
│       │   ├── TokenBarChartPlot.swift    # 堆叠直方图绘制和 hover 明细
│       │   └── MeasuredScrollView.swift   # 自适应高度滚动容器
│       ├── Settings/                      # 设置窗口视图
│       │   ├── SettingsView.swift         # SettingsTab、SettingsView 骨架
│       │   ├── GeneralSettingsView.swift  # 通用设置
│       │   ├── PluginSettingsView.swift   # 插件列表和拖拽排序
│       │   ├── PluginSettingsCard.swift   # 插件详情卡片和参数表单
│       │   ├── AboutView.swift            # 关于和更新
│       │   └── SettingsComponents.swift   # SettingsSection、SettingsRow
│       └── DesignSystem/                  # 共享视觉组件
│           ├── UBDesignTokens.swift       # 圆角、字体、颜色 token
│           ├── AppIconSquircle.swift       # 圆角方形图标
│           ├── BrandTile.swift            # 品牌卡片
│           ├── CountdownLabel.swift        # 倒计时标签
│           └── PlanTag.swift              # 套餐徽章标签
├── Tests/
│   ├── UsageBoardTests/                   # XCTest 单元测试（Core 层）
│   ├── UsageBoardAppTests/                # Store 调度、图表与布局测试
│   └── PluginTests/                       # pytest 插件测试
├── Resources/
│   ├── BundledPlugins/                    # 内置 Python 插件
│   │   ├── _common.py                     # 公共模块
│   │   ├── claude-usage-plugin.py
│   │   ├── codex-usage-plugin.py
│   │   ├── deepseek-usage-plugin.py
│   │   ├── glm-usage-plugin.py
│   │   ├── minimax-usage-plugin.py
│   │   ├── kimi-usage-plugin.py
│   │   └── tavily-usage-plugin.py
│   ├── icons/                             # light/dark 插件 PNG 图标
│   ├── PluginAuthoringGuide.html          # 插件编写说明
│   └── UsageBoard.icns                    # 应用图标
├── scripts/
│   ├── build.sh                           # 本地构建、签名、启动
│   └── release.sh                         # 发布脚本
├── dist/                                  # 构建产物
└── docs/                                  # 本文档所在目录
```

---

## 4. 分层架构与依赖方向

UsageBoard 采用两层架构：**Core（纯逻辑）→ App（UI + 组装）**，依赖方向为 `App → Core`。

```
┌─────────────────────────────────────────────────────────────┐
│ UsageBoardApp (SwiftUI + AppKit)                            │
│                                                             │
│ ┌─────────────────────┐  ┌──────────────────────────────┐   │
│ │ App / AppDelegate   │  │ Views                        │   │
│ │ 状态栏、popover、    │  │ DashboardView (Overview /    │   │
│ │ 窗口管理、入口       │  │   Grouped / Tabs / Chart)    │   │
│ └─────────┬───────────┘  │ SettingsView (General /      │   │
│           │              │   Plugins / About)            │   │
│           ▼              └──────────────┬───────────────┘   │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ UsageBoardStore                                         │ │
│ │ @MainActor ObservableObject                             │ │
│ │ 配置、快照、调度、刷新、缓存、更新、开机启动                │ │
│ └────────────────────────┬────────────────────────────────┘ │
│                          │                                  │
│ DesignSystem/            │  AppLocalization                 │
│ UBDesignTokens, PlanTag  │  (key, language) 文案映射        │
└──────────────────────────┼──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ UsageBoardCore (Foundation only, no SwiftUI)                │
│                                                             │
│ ┌──────────────┐ ┌───────────────┐ ┌──────────────────────┐│
│ │ Models       │ │ ConfigStore   │ │ PluginExecutor       ││
│ │ 全部数据类型  │ │ 配置读写       │ │ 子进程执行 + 超时      ││
│ └──────────────┘ └───────────────┘ └──────────────────────┘│
│ ┌──────────────┐ ┌───────────────┐ ┌──────────────────────┐│
│ │ StateStore   │ │ MetadataParser│ │ BundledPluginInstaller││
│ │ 缓存读写      │ │ 注释块解析     │ │ 符号链接安装           ││
│ └──────────────┘ └───────────────┘ └──────────────────────┘│
│ ┌──────────────┐ ┌───────────────┐ ┌──────────────────────┐│
│ │ UpdateChecker│ │ AppRelauncher │ │ JSONCoding            ││
│ │ 版本比较+下载 │ │ 进程替换重启    │ │ 统一编解码器           ││
│ └──────────────┘ └───────────────┘ └──────────────────────┘│
│ ┌──────────────┐                                           │
│ │ DisplayNames │                                           │
│ │ 显示名去重    │                                           │
│ └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Python Plugins (外部进程)                                    │
│ _common.py → 各插件脚本                                      │
│ stdin: 无  /  args: --usageboard-param K=V  /  stdout: JSON │
└─────────────────────────────────────────────────────────────┘
```

### 4.1 依赖规则

| 层                | 可以依赖                                                                                        | 不允许依赖                                  |
| ----------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `UsageBoardCore`  | `Foundation`                                                                                    | SwiftUI、AppKit、`UsageBoardApp` 内任何类型 |
| `UsageBoardStore` | `UsageBoardCore`、`Foundation`、`AppKit`、`ServiceManagement`                                   | 具体 View 类型                              |
| Views             | `SwiftUI`、`UsageBoardCore`（只读 model）、`UsageBoardStore`、`DesignSystem`、`AppLocalization` | 直接构造 `Process`、直接读写文件            |
| `DesignSystem`    | `SwiftUI`                                                                                       | 业务逻辑、`UsageBoardStore`                 |
| Python 插件       | `_common.py`、Python 标准库                                                                     | Swift 代码、app 内部状态                    |

**硬性规则**：

1. `UsageBoardCore` 不得 `import SwiftUI` 或 `import AppKit`。
2. View 不直接构造 `PluginExecutor`、`ConfigStore` 或 `Process`，一切行为通过 `UsageBoardStore`。
3. 新增 Core 类型必须实现 `Sendable`。
4. JSON 编解码统一使用 `UsageBoardJSON.decoder()` / `UsageBoardJSON.encoder()`，不自行构造 `JSONDecoder`。
5. 插件显示名统一用 `PluginDisplayNames.make(for:language:)`，不直接读 `plugin.name`。

---

## 5. App 层

### 5.1 入口与窗口管理

`UsageBoardApp.swift` 包含：

- `UsageBoardApplication`：`@main` App struct，使用 `@NSApplicationDelegateAdaptor` 桥接 AppKit。
- `AppDelegate`：`@MainActor` 单例，管理：
  - `NSStatusItem`（menu bar 图标）
  - `NSPopover`（点击弹出面板，`applicationDefined` behavior + 全局/局部点击监听自动关闭）
  - 设置窗口（`NSWindow` + `NSWindowController`，初始 800×520，最小 800×480）
  - `UsageBoardStore` 单例的创建与持有

规范：

- `AppDelegate` 只做窗口生命周期管理，不写业务逻辑。
- app 策略设为 `.accessory`（不显示 Dock 图标），全部交互从 menu bar 开始。
- popover 关闭时必须清理全局事件监听器，避免泄漏。

### 5.2 UsageBoardStore

`UsageBoardStore` 是全局唯一的 `@MainActor ObservableObject`，是 View 层的唯一状态入口。

职责：

| 职责         | 说明                                                                             |
| ------------ | -------------------------------------------------------------------------------- |
| 配置管理     | 加载/保存 `AppConfiguration`，`scheduleConfigurationWrite` 合并写入              |
| 插件调度     | 为每个已启用插件启动定时刷新 `Task`，支持系统睡眠/唤醒门控                       |
| 插件执行     | 委托 `PluginExecutor` 在后台线程运行插件，返回 `PluginSnapshot`                  |
| 缓存管理     | 启动时从 `PluginStateStore` 加载缓存，刷新成功后异步写回                         |
| 快照发布     | 维护 `snapshots: [UUID: PluginSnapshot]`，驱动 View 更新                         |
| 元数据重载   | 启动时 `reloadAllMetadata()` 重新解析所有插件的 metadata 并持久化                |
| 内置插件安装 | 启动时调用 `BundledPluginInstaller.installIfNeeded()`                            |
| 更新检查     | 通过 `UpdateChecker` 检查版本，`UpdateDownloader` 下载，`AppRelauncher` 替换重启 |
| 开机启动     | 通过 `SMAppService.mainApp` 注册/注销                                            |

关键设计：

- **定时刷新**：每个插件一个独立的 `Task` 循环，按 `refreshIntervalSeconds`（最小 5 秒）调度，基于缓存 `updatedAt` 计算首次延迟。
- **系统活动门控**：睡眠时暂停刷新，唤醒时检查到期插件立即刷新；4 小时安全超时防止唤醒通知丢失导致永久冻结。
- **配置写入合并**：`scheduleConfigurationWrite` 使用 generation 计数器，连续快速修改只落盘最后一次，退出前持续等待所有待写配置完成，包括等待期间新增的写入。配置以 0600 权限写入临时文件后原子替换。
- **inflight 任务管理**：`inflightRefreshTasks` 跟踪正在运行的插件执行，重复刷新合并；禁用、删除或更新执行配置时取消，取消会传递至子进程。更新配置等待前一次执行结束后重跑，并切换缓存 ID，旧结果不得写回新配置。

规范：

- View 不直接修改 `configuration.plugins`，通过 Store 方法（`addPlugin`/`removePlugin`/`setPluginEnabled`/`saveConfiguration`）操作。
- 插件启用前自动检查必填参数，缺失时拒绝启用并显示错误。
- `makeSnapshot` 是构造 `PluginSnapshot` 的唯一入口，确保 `iconURL` 等字段一致传递。

---

## 6. Core 层

### 6.1 Models

共享数据类型按主题分散在多个文件（`AppConfiguration.swift`、`PluginConfiguration.swift`、`PluginOutput.swift`、`PluginSnapshot.swift`，枚举辅助见 `CodableHelpers.swift`），无外部依赖，全部 `Sendable`：

| 类型                                                       | 职责                                                                         |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `AppLanguage`                                              | 语言枚举（`zh-Hans`、`en`）                                                  |
| `DisplayMode`                                              | 展示模式（`grouped`、`tabs`）                                                |
| `ChartMode`                                                | 图表模式（`line`、`bar`）                                                    |
| `AppConfiguration`                                         | 顶层配置（schema version、language、theme、display/chart mode、plugins、launch at login） |
| `PluginConfiguration`                                      | 单个插件配置（`id`=运行时 UUID、`stateID`=持久化 ID、路径、参数值等）        |
| `PluginMetadata`                                           | 插件元数据（name、description、icon、parameters，支持多语言翻译）            |
| `PluginParameterMetadata`                                  | 参数定义（7 种类型：string/secret/integer/boolean/choice/directory/file）    |
| `PluginOutput`                                             | 插件 stdout JSON 解码目标                                                    |
| `UsageItem`                                                | 单条用量（id、name、used、limit、displayStyle、resetAt、status、color）      |
| `PluginChart` / `PluginChartBucket` / `PluginChartSegment` | token 统计图数据                                                             |
| `PluginSnapshot`                                           | UI 层消费的插件快照（state、items、badge、iconURL、chart）                   |
| `PluginCachedState`                                        | 磁盘缓存结构                                                                 |

多语言翻译机制：

- 元数据 JSON 中使用 `field@lang` 后缀字段（如 `name@zh-Hans`、`label@en`）。
- 解码时通过 `AnyCodingKey` 动态扫描前缀，提取到 `*Translations` 字典。
- 运行时通过 `localizedName(language:)` 等方法按语言回退。

规范：

- Model 必须是纯值类型 + `Sendable`，不持有 UI 状态。
- `PluginConfiguration.id` 是运行时 UUID（不持久化），`stateID` 用于磁盘缓存，二者语义不同。
- `UsageItem.progress` 内部限制在 `0...1`，`displayValue()` 按 `displayStyle` 格式化。

### 6.2 ConfigStore

读写 `config.json` 的值类型，提供配置目录、插件目录、状态目录的 URL。

- `loadOrCreate()`：文件存在则加载，不存在则创建默认配置。
- `save(_:)`：在同目录以 0600 权限写临时文件，再原子替换，自动创建目录。

### 6.3 PluginExecutor

执行插件脚本并返回 `PluginSnapshot`：

- `.py` 文件通过 `/usr/bin/env python3 <script>` 执行，其他可执行文件直接运行。
- 参数通过 `--usageboard-param KEY=value` 传入，自动注入 `USAGEBOARD_LANGUAGE`。
- 强制设置 `PYTHONIOENCODING=utf-8` + `LANG=en_US.UTF-8` + `LC_ALL=en_US.UTF-8` 环境变量，避免编码问题；`PYTHONDONTWRITEBYTECODE=1` 禁止写入 Python 字节码，避免修改 app 包。
- 默认 15 秒超时；超时或取消时发送 SIGTERM，1 秒后仍未退出则发送 SIGKILL。
- stdout 用 `DataBuffer`（`NSLock` + `readabilityHandler`）异步收集，上限 8 MiB；stderr 最多保留 64 KiB，持续排空管道避免死锁。
- 非空顶层 `error` 优先视为失败，即使同时包含成功字段。

### 6.4 PluginMetadataParser

读取插件文件**前 80 行**中的 `UsageBoardPlugin:` ... `/UsageBoardPlugin` 注释块，提取 JSON 后用 `UsageBoardJSON.decoder()` 解码为 `PluginMetadata`。

### 6.5 PluginStateStore

按 `stateID` 管理缓存（`states/<stateID>.json`），内存 + 磁盘两级：内部 `StateCache`（`NSLock` 保护）作为内存层，磁盘文件作为持久层。

- `load(stateID:)`：先查内存缓存命中即返回；未命中则读磁盘并回填内存（磁盘文件被删后内存仍可命中）。
- `save(stateID:state:)`：原子写入磁盘并同步更新内存缓存。
- `needsRefresh(stateID:intervalSeconds:)`：判断缓存是否过期（间隔下限 5 秒）。

### 6.6 BundledPluginInstaller

启动时将 app 包 `Contents/Resources/Plugins/` 中的 `.py` 文件以符号链接方式安装到用户 `plugins/` 目录：

- 以 `_` 开头的文件（如 `_common.py`）不安装。
- 已存在且指向正确源的符号链接跳过。
- 目标为普通文件时保留；已有符号链接指向不同位置时替换链接。

### 6.7 UpdateChecker / UpdateDownloader / AppRelauncher

三阶段更新流程：

1. `UpdateChecker.check()`：从 `UBUpdateCheckURL`（Info.plist 注入）获取 `version.json`，比较语义版本号。
2. `UpdateDownloader.download()`：下载 zip，用 `ditto` 解压到临时目录。
3. `AppRelauncher.relaunch(replacingWith:)`：先在目标目录暂存并签名新 app；旧进程退出后将原 app 改名为备份，再替换并启动。移动或启动命令失败时恢复原 app；成功后清理备份。

更新检查与下载只接受 HTTPS 和成功 HTTP 状态；下载后验证唯一 UsageBoard app 的标识、版本和包内可执行文件。UI 显示独立的检查中状态并阻止重复检查或安装。

`AppRelauncher.relaunchCurrent()` 用于语言切换后的简单重启（不替换 app）。

### 6.8 PluginDisplayNames

处理同名插件的显示名去重：相同 base name 的第二个及之后追加序号（如 `Claude 2`）。优先使用 metadata 的本地化名称，回退到 `plugin.name`。

### 6.9 JSONCoding

`UsageBoardJSON` 提供统一的编解码器：

- **解码**：自定义 ISO 8601 日期策略，同时支持带/不带小数秒。
- **编码**：`.prettyPrinted` + `.sortedKeys`，便于人工阅读和 diff。

---

## 7. Views 层

### 7.1 DashboardView / OverviewView

`Dashboard/` 按职责拆分面板视图：

| 视图                  | 职责                                                        |
| --------------------- | ----------------------------------------------------------- |
| `OverviewView`        | popover 顶层容器：标题栏 + DashboardView + 设置/退出按钮    |
| `DashboardView`       | 根据 `DisplayMode` 切换 grouped/tabs 布局                   |
| `EmptyPluginsView`    | 无启用插件时的占位提示                                      |
| `PluginGroupView`     | 单个插件卡片：图标 + 标题 + 徽章 + 倒计时 + 用量行 + 统计图 |
| `UsageItemRow`        | 单条用量行：名称 + 进度条 + 数值 + 重置时间                 |
| `UsageProgressBar`    | 彩色进度条，高度接近文字行高，数值居中                      |
| `TokenUsageChartView` | token 统计图容器、摘要与图表模式切换                       |
| `TokenLineChartPlot`  | 折线图绘制（支持 hour/day 粒度，hover 交互）                |
| `TokenBarChartPlot`   | 堆叠直方图绘制；未选中时每个时间桶按图例顺序堆叠统计项      |
| `TokenMetricView`     | 统计摘要数字（总量、日均、峰值等）                          |
| `MeasuredScrollView`  | 自适应高度滚动容器，按调用方传入的高度预算封顶               |

`DesignSystem/BrandTile.swift` 统一解析和加载图标：`icon` 字符串兼容 HTTP(S)、绝对文件路径、file URL 和 app 资源相对路径。内置配置使用 `icons/light/<filename>`，以 app 的 Resources 为根，开发时 fallback 到当前目录的 Resources。深色主题优先使用同名 dark 文件，缺失时回退 light。SwiftUI task 以解析后的 URL 为标识，主题变化会重新加载，取消的旧任务不回写；本地文件直接读取，远程请求检查 HTTP 成功状态，NSCache 按实际 URL 分开缓存。构建和发布脚本均将 `Resources/icons/` 复制到包内 `Contents/Resources/icons/`。

### 7.2 SettingsView

通用页以“外观 / 使用偏好”分组，提供浅色、深色、跟随系统主题。`AppConfiguration.theme` 默认 `system`，旧配置解码兼容；`UsageBoardStore.setTheme` 更新并持久保存，AppDelegate 订阅主题变更设置 `NSApp.appearance`，同步已有 popover 及 hosting view。`system` 使用 nil 外观继承，避免冻结当前系统主题；无需重启。

侧栏不显示版本号；关于页集中展示应用信息、版本和独立更新操作/消息，支持提示换行和滚动。插件列表宽 190，基础选项和参数共用 SettingsRow（左侧 96 pt 标签、右侧控件），choice 直接比较选项文字宽度和可用空间，只创建分段选择或回退菜单其中一种控件，避免 ViewThatFits 对原生控件的重复测量；通用页的主题、显示、图表、语言也统一为分段选择，控件右对齐，开关使用 mini 尺寸；搜索、排序、保存、重置和草稿处理保持原有行为。

`Settings/` 按职责拆分设置视图：

| 视图 / 组件                       | 职责                                                                            |
| --------------------------------- | ------------------------------------------------------------------------------- |
| `SettingsView`                    | 顶层骨架：sidebar + detail，三个 tab（通用/插件/关于）                          |
| `GeneralSettingsView`             | 主题、开机启动、语言、展示模式、图表模式                                              |
| `PluginSettingsView`              | 插件列表（拖拽排序）+ 详情面板（draft 机制编辑）                                |
| `PluginSettingsCard`              | 单个插件详情卡片：参数表单、启用/禁用、保存/重置                                |
| `PluginParameterField`            | 按参数类型渲染对应输入控件（text/secret/integer/boolean/choice/directory/file） |
| `PluginDropDelegate`              | 插件列表拖拽排序代理                                                            |
| `AboutView`                       | 版本信息、更新检查、更新安装                                                    |
| `SettingsSection` / `SettingsRow` | 设置页共享布局组件                                                              |

设置编辑规范：

- 插件详情使用 **draft 机制**：编辑只改设置窗口持有、传入插件页的 draft，点击"保存"后通过 `updatePlugin` 校验路径和已启用插件的必填参数，再写回 Store；手动修改脚本路径时重新解析元数据和默认值。切换设置栏目保留草稿；切换或新增插件前提示保存或放弃未保存的编辑。
- 启用/禁用和拖拽排序**即时生效**，不走 draft。
- 语言切换弹出确认对话框，确认后通过 `AppRelauncher.relaunchCurrent()` 重启。

### 7.3 DesignSystem

`DesignSystem/` 存放共享视觉原语：

| 文件                    | 职责                                                                                  |
| ----------------------- | ------------------------------------------------------------------------------------- |
| `UBDesignTokens.swift`  | `UB.Radius`（card/bar）、`UB.Font`（各场景字体）、`UB.Canvas`（背景/卡片/分隔线颜色） |
| `AppIconSquircle.swift` | 圆角方形图标（SwiftUI 绘制）                                         |
| `BrandTile.swift`       | 品牌图标（异步加载 + `NSCache` 内存缓存）                                                                          |
| `CountdownLabel.swift`  | 下次刷新倒计时标签                                                                    |
| `PlanTag.swift`         | 套餐徽章（按套餐或插件配置着色）                                           |

规范：

- 共享 token 集中在 `UBDesignTokens.swift`，不在 feature View 中重复定义。
- 设计组件只承载展示规则，不持有业务状态。

### 7.4 AppLocalization

`AppLocalization.swift` 以 `(key, language)` 匹配返回 UI 文案，覆盖设置页标题、按钮、提示等所有固定文案。

规范：

- 新增 UI 文案必须同时添加中文和英文。
- 插件相关的动态文案（插件名、用量名等）走插件元数据的 `field@lang` 机制，不走 `AppLocalization`。

---

## 8. 数据流

```
PluginConfiguration
  → UsageBoardStore.refresh(pluginID:)
  → PluginExecutor.run()  [后台线程]
  → 插件进程 stdout JSON
  → PluginOutput 解码
  → PluginSnapshot
  → PluginStateStore 缓存写入  [后台线程]
  → UsageBoardStore.snapshots 更新  [MainActor]
  → DashboardView / OverviewView 刷新
```

启动时的初始化顺序：

```
UsageBoardStore.init()
  1. ConfigStore.loadOrCreate()           // 加载或创建配置
  2. BundledPluginInstaller.installIfNeeded()  // 安装内置插件符号链接
  3. reloadAllMetadata()                  // 重新解析所有插件元数据
  4. ConfigStore.save()                   // 一次持久化 stateID 与 metadata
  5. rebuildSnapshots()                   // 构建初始快照（idle 状态）
  6. loadCachedStates()                   // 从缓存恢复上次数据
  7. startSchedulers()                    // 为已启用插件启动定时刷新
  8. observeSystemActivity()              // 监听系统睡眠/唤醒
```

---

## 9. 插件协议

### 9.1 执行方式

```
/usr/bin/env python3 /path/to/plugin.py \
  --usageboard-param KEY=value \
  --usageboard-param USAGEBOARD_LANGUAGE=zh-Hans
```

### 9.2 stdout JSON 格式

```json
{
  "updatedAt": "2026-04-29T00:00:00Z",
  "items": [
    {
      "id": "requests",
      "name": "Requests",
      "used": 1200,
      "limit": 1500,
      "displayStyle": "ratio",
      "resetAt": "2026-04-29T05:00:00Z",
      "status": "normal",
      "color": "blue"
    }
  ],
  "badge": "PRO",
  "chart": { "kind": "line", "period": "30d", "bucketUnit": "day", "buckets": [...] }
}
```

### 9.3 错误输出

```json
{ "error": "API Key 无效" }
```

### 9.4 元数据注释块

写在脚本前 80 行的注释中，`UsageBoardPlugin:` 开始，`/UsageBoardPlugin` 结束，内容为 JSON。支持 `field@lang` 多语言后缀。

### 9.5 公共模块

`_common.py` 提供：`parse_usageboard_params`、`app_language`、`make_translator`、`utc_now_iso`、`success`/`failure`、`numeric`/`status_for`/`color_for`/`color_for_pct`、`handle_http_error`/`handle_url_error`、`load_json_cache`/`save_json_cache`（校验缓存结构、原子写入）。新建插件应从 `_common` 导入复用，不在插件内重复实现。

---

## 10. 国际化

- `AppLanguage` 枚举（`zh-Hans`、`en`）控制整个 app 的展示语言，存储在 `AppConfiguration.language`。
- UI 固定文案集中在 `AppLocalization.swift`。
- 插件元数据多语言通过 `field@lang` 后缀字段实现。
- 运行时通过 `--usageboard-param USAGEBOARD_LANGUAGE=<lang>` 传给插件。
- 语言切换需重启生效。

规范：

- 新增 UI 文案必须同时补齐中文和英文。
- 插件错误消息通过 `make_translator` 的 `COMMON_TRANSLATIONS` + 插件自定义翻译字典实现双语。
- 不在 model / store 中硬编码 UI 文案，除非是 `StoreMessage` 枚举中的内部消息。

---

## 11. 测试规范

### 11.1 Swift 单元测试

Core 测试在 `Tests/UsageBoardTests/`，App 调度、配置保存与图表布局测试在 `Tests/UsageBoardAppTests/`。Core 主要覆盖：

| 领域              | 测试                                                                                                                                        | 覆盖                                                                                                          |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| 配置 / 路径       | `testConfigurationDecodesDefaultsAndSaves`、`testPluginsDirectoryIsNextToConfigurationFile`                                                 | 配置编解码与默认值、插件目录路径计算                                                                          |
| 状态缓存          | `testPluginStateStoreSavesAndClampsRefreshInterval`、`testPluginStateStoreCacheHitsAfterDiskDelete`                                         | 磁盘读写与刷新间隔下限、磁盘文件删除后内存缓存仍命中                                                          |
| 内置插件安装      | `testBundledPluginInstaller*`                                                                                                               | 符号链接安装、失效链接替换与同名用户文件保护                                                                                    |
| PluginOutput 解码 | `testPluginOutputDecodes*`                                                                                                                  | items/进度格式化、小数秒日期、chart 解码与缓存往返                                                            |
| 插件执行器        | `testPluginExecutor*`、`testPluginParameterValuesBecomeArguments`                                                                           | chart 传播、非法/错误 JSON、解码路径定位、UTF-8 环境、超大 stdout 防 pipe 死锁、`--usageboard-param` 参数拼装 |
| 元数据解析        | `testPluginMetadataParserReadsCommentBlock`、`testGLMPluginMetadataUsesStatPeriodWithoutProvider`、`testCodexPluginMetadataReadsParameters` | 注释块解析与多语言、内置插件实际元数据                                                                        |
| 用量模型          | `testProgressHandlesBoundsAndRatio`、`testResetTextShowsStaticDateTime`                                                                     | `progress` 边界与格式化、重置时间文案                                                                         |
| 显示名            | `testDuplicatePluginNamesGetNumbered`、`testLocalizedPluginDisplayNamesUseMetadataUnlessUserCustomized`                                     | 同名去重、本地化名优先于用户自定义判定                                                                        |
| 更新              | `testUpdateVersionComparison`                                                                                                               | 语义版本号比较                                                                                                |

### 11.2 Python 插件测试

`Tests/PluginTests/` 使用 pytest，通过 `importlib.util` 加载插件模块并 mock 网络调用：

- 多数插件对应一个 `test_<name>_plugin.py`（claude/codex/deepseek/glm/minimax）；另有跨插件的 `test_bundled_plugin_interpreters.py`（多解释器兼容性）和 `test_plugin_error_classification.py`（`_common` HTTP/URL 异常分类）。
- 测试中需先将插件目录插入 `sys.path` 以找到 `_common.py`。
- 使用多解释器（系统 Python + Homebrew Python）交叉验证兼容性。

### 11.3 变更对应验证

| 改动范围                          | 验证方式                                                                                  |
| --------------------------------- | ----------------------------------------------------------------------------------------- |
| Core 模型、解析、执行器、更新逻辑 | `swift test`                                                                              |
| SwiftUI/AppKit UI                 | `swift build`；重要交互用 `bash scripts/build.sh` 手动检查                                |
| 内置插件或 `_common.py`           | `python3 -m pytest Tests/PluginTests/ -v`；需 `bash scripts/build.sh` 重建才能在 app 生效 |
| 文档                              | `git diff --check`                                                                        |

---

## 12. UI 尺寸参考

- 设置窗口：初始 800×520，最小 800×480，可调整大小。
- Menu bar popover：宽度固定 380，高度自适应内容，最大为状态栏所在屏幕可用高度的 75%。
- 进度条高度接近文字行高，数值显示在进度条中间。

---

## 13. 新功能落点指南

| 需求类型      | 首选落点                                                                                                                     |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 新插件        | `Resources/BundledPlugins/` + `Tests/PluginTests/` + `_common.py` 复用                                                       |
| 新 Model 字段 | 对应模型文件（`AppConfiguration` / `PluginConfiguration` / `PluginOutput` / `PluginSnapshot`）→ 确认 Codable 兼容 → 更新测试 |
| 新 UI 组件    | `DesignSystem/`                                                                                                              |
| 新设置项      | `SettingsView.swift` 对应 section + `AppLocalization` 文案                                                                   |
| 新 Store 能力 | `UsageBoardStore.swift` 方法 + 确认 `@Published` 对 View 的影响                                                              |
| 新参数类型    | `PluginParameterType` 枚举 + `PluginParameterField` 渲染 + 插件元数据文档                                                    |
| 新展示样式    | `UsageDisplayStyle` 枚举 + `UsageItem.displayValue()` + `UsageItemRow` 渲染                                                  |
| 新图表类型    | `PluginChart.kind` + `DashboardView` 中新建图表视图                                                                          |

---

## 14. 维护原则

1. **Core 无 UI**：`UsageBoardCore` 不得引入 SwiftUI/AppKit，保持可独立测试。
2. **Store 是唯一入口**：View 通过 `UsageBoardStore` 发起所有行为，不绕过。
3. **插件是外部进程**：app 与插件的唯一接口是 `--usageboard-param` 参数和 stdout JSON。
4. **统一编解码器**：JSON 操作只用 `UsageBoardJSON`，不自行构造。
5. **小步验证**：Core 改动必须跑测试，UI 改动至少 build，插件改动重建 app。
6. **文案不硬编码**：UI 文案走 `AppLocalization`，插件文案走 `make_translator`。
7. **draft 编辑**：设置页编辑用 draft，保存才写回，避免中间状态污染配置。
8. **不混入无关改动**：每次提交只包含当前请求相关的变更。
9. **公共模块复用**：Python 插件公共函数放 `_common.py`，不在插件内重复实现。
10. **符号链接感知**：修改内置插件源文件后必须 `bash scripts/build.sh` 重建，否则 app 仍跑旧副本。
