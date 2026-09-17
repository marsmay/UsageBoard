# UsageBoard 架构说明与开发规范

本文以当前 `Package.swift`、`Sources/`、内置插件和构建脚本为依据。用户功能与配置示例见 [README](../README.md)，插件完整协议见 [插件编写说明](../Resources/PluginAuthoringGuide.html)。

## 1. 项目与代码组织

UsageBoard 是 macOS 菜单栏应用，通过外部插件聚合服务配额、账户余额和本地 token 统计。主程序负责配置、调度、缓存和展示，插件负责获取数据。

- 运行平台：macOS 13+；Python 插件通过可用的 `python3` 执行。
- 构建：Swift Package Manager，最低 Swift tools version 为 6.3，Swift language mode 为 6。
- App：SwiftUI + AppKit，`ObservableObject` / `@Published`，使用 `SMAppService` 管理开机启动。
- 测试：XCTest（Core、App）和 pytest（Python 插件）。

| 位置 | 职责 |
| --- | --- |
| `Sources/UsageBoardCore/` | 配置与输出模型、JSON 编解码、插件执行与元数据解析、缓存、更新和重启 |
| `Sources/UsageBoardApp/UsageBoardApp.swift` | App 入口、AppDelegate、菜单栏、popover 与设置窗口生命周期 |
| `Sources/UsageBoardApp/UsageBoardStore.swift` | 主状态、配置写入、插件调度、刷新、更新与开机启动 |
| `Sources/UsageBoardApp/AppTheme.swift` | Core 的 AppTheme 到 NSAppearance 的映射 |
| `Sources/UsageBoardApp/AppLocalization.swift` | 中英文固定文案 |
| `Sources/UsageBoardApp/Dashboard/` | 分组/标签页、用量行、统计图与滚动布局 |
| `Sources/UsageBoardApp/Settings/` | 通用、插件、关于三页，插件编辑草稿和参数表单 |
| `Sources/UsageBoardApp/DesignSystem/` | 视觉 token、应用/品牌图标、倒计时和套餐徽章 |
| `Tests/UsageBoardTests/` | Core XCTest |
| `Tests/UsageBoardAppTests/` | Store 调度、主题、语言提示、图标、popover 与图表 XCTest |
| `Tests/PluginTests/` | 内置插件、公共缓存和错误分类、解释器兼容性测试 |
| `Resources/BundledPlugins/` | 七个 Python 插件和 `_common.py` |
| `Resources/icons/` | light/dark 插件 PNG，来源与哈希见目录内 README |
| `Resources/IconSources/` | Codex 图标处理前的源图 |
| `Resources/PluginAuthoringGuide.html` | 随 app 打包的插件协议说明 |
| `Resources/UsageBoard.icns` | 应用图标 |
| `scripts/build.sh` / `scripts/release.sh` | 本地打包启动 / 服务器发布 |
| `scripts/prepare_codex_icon.py` | 用 Pillow 从源图重新生成 Codex 图标 |
| `dist/` | 生成的 app、ZIP 和更新 metadata，不手工修改 |

## 2. 依赖边界

依赖方向为 `UsageBoardApp → UsageBoardCore`。Python 插件是独立进程，通过命令行参数和 stdout JSON 与主程序交互。

| 层 | 允许依赖与边界 |
| --- | --- |
| Core | Foundation；ConfigStore、PluginExecutor 使用 Darwin 的原子替换/进程信号。不依赖 SwiftUI、AppKit 或 App 类型 |
| Store | Core、Foundation、AppKit、ServiceManagement；不依赖具体 View |
| Views | SwiftUI、Core 模型、Store、本地化与设计组件；配置持久化、插件调度和更新安装交给 Store |
| DesignSystem | SwiftUI，图标加载使用 AppKit/Foundation；不持有 Store 或业务状态 |
| 内置 Python 插件 | Python 标准库与 `_common.py`；不引用 Swift 内部状态 |

现有 UI 层直接处理文件选择器、打开目录/帮助、语言重启等系统交互；`BrandIconSource` / `BrandIconCache` 直接解析资源并读取本地或远程图标。这些展示和系统交互与业务数据持久化分开。

开发约束：

- Core 共享模型保持纯值类型和 `Sendable`；Store 保持 `@MainActor`。Core 文件沿用 `@preconcurrency import Foundation` 约定。
- Swift JSON 编解码使用 `UsageBoardJSON.decoder()` / `encoder()`；日期支持带或不带小数秒的 ISO 8601，编码使用 ISO 8601、缩进和键排序。
- 插件显示名经 `PluginDisplayNames.make(for:language:)` 去重。用户自定义名称优先；名称为空或等于 metadata 基础名称时才使用本地化 metadata，同名后续项追加序号。
- Store 内的快照统一通过 `makeSnapshot` 构造；Core 的 `PluginExecutor` 自行构造执行结果快照，Store 接收后再按当前配置发布。
- 内置插件公共能力复用 `_common.py`；独立用户插件需随脚本提供该模块，或使用编写说明中的独立实现。

## 3. 配置、模型与存储

Core 模型按主题拆分：`AppConfiguration.swift`、`PluginConfiguration.swift`、`PluginOutput.swift`、`PluginSnapshot.swift`。`CodableHelpers.swift` 处理动态键及元数据翻译，`Protocols.swift` 提供 ConfigStoring、PluginStateStoring、PluginExecuting、UpdateChecking，供 Store 注入测试替身。

默认运行目录为 `~/Library/Application Support/UsageBoard/`：

| 路径 | 内容与行为 |
| --- | --- |
| `config.json` | 插件配置与参数。ConfigStore 同目录创建权限 0600 的临时文件，写入后用 rename 原子替换 |
| `plugins/` | 内置插件符号链接和用户脚本；添加插件的文件选择器默认打开这里 |
| `states/` | PluginStateStore 的成功快照缓存，包含 updatedAt、items、badge、badgeColor、chart、credits |
| `plugin-caches/` | GLM 默认统计缓存，按 API key 的哈希前缀区分；与 Store 快照缓存独立 |

Claude/Codex 的增量统计缓存位于各自 `DATA_DIR/.usageboard-chart-cache.json`，不在 `states/`。GLM 缓存可由插件内部的 cache_dir 或 `USAGEBOARD_CACHE_DIR` 覆盖。GLM 与 Codex 的图表缓存版本均为 2，首次读取旧版本会重建近 30 天数据，随后按最后缓存日起增量覆盖；GLM 因此纠正旧跨日漏计，Codex 因此纠正旧解析器遇坏字节后遗漏的历史数据。Codex 按行解码 UTF-8，损坏行整体跳过，不中断后续有效记录。

配置默认值：schemaVersion 1、中文、跟随系统主题、tabs、line、不启用开机启动、插件列表为空。安装内置链接不会自动把插件加入配置；用户仍需添加和启用。

`PluginConfiguration.id` 是不持久化的运行时 UUID；`stateID` 是持久化缓存 ID。通过 Store.updatePlugin 修改脚本路径、参数或 metadata 时会换用新的 stateID，防止复用旧配置的数据。执行路径使用实际文件路径，不展开 `~` 或 shell 表达式；插件参数是否展开路径由插件自身决定。

PluginStateStore 以 NSLock 保护的内存缓存加磁盘文件实现两级缓存。文件名由 stateID 清理不安全字符后生成；先原子写盘成功再更新内存。磁盘文件被删除时，已有内存缓存仍可命中。`needsRefresh` 按 updatedAt 判断过期，间隔下限为 5 秒；Store 自身调度使用快照和 nextRefreshAt。

`UsageItem.progress` 将有限且 limit > 0 的 used/limit 限制在 0…1；无效值返回 0。数值标签由 `displayStyle` 决定。所有已启用插件的卡片始终渲染；无内容的快照显示"暂无用量数据"占位，失败时显示错误信息。`PluginOutput` 成功对象要求 updatedAt 和 items；badge、badgeColor、chart、credits 可选。

## 4. Store 生命周期与数据流

`UsageBoardStore` 是 AppDelegate 持有的 `@MainActor ObservableObject`。配置、快照、下次刷新时间、更新状态和错误驱动 View。

初始化顺序：

1. 加载或创建配置；失败时使用内存默认配置并记录错误，跳过本次初始化的配置回写。
2. 固定当前会话的 activeLanguage，初始化 AppLocalization。
3. 安装内置插件链接，重载已配置插件的 metadata；仅在配置加载成功时持久化。
4. 重建初始快照，恢复成功缓存。
5. 启动已启用插件的调度任务，订阅系统睡眠/唤醒事件。

刷新流程：

```text
Store.refresh(pluginID:force:)
  → 校验启用状态、必填参数、刷新间隔和已有任务
  → 发布 loading 快照，保留已有数据
  → Task.detached 调用 PluginExecutor.run()
  → 执行进程、解析 stdout，返回 PluginSnapshot
  → MainActor 重验取消状态及当前插件配置
  → makeSnapshot 并发布到 Store.snapshots
  → 仅 ready 结果在后台写 PluginStateStore
```

缓存写入发生在快照发布之后；写盘失败记录 lastError，不撤销已展示结果。失败结果不会覆盖磁盘中的上次成功缓存。

调度与取消：

- 每个已启用插件一个 Task 循环，最小间隔 5 秒；首次执行时间按缓存 updatedAt 计算，到期或无缓存时立即刷新。
- 调度 key 为刷新间隔和 stateID，未变时复用已有调度；nextRefreshAt 供倒计时和下次等待使用。跳过刷新也会推进已到期的等待时间，避免忙等。
- 重复刷新合并，包括手动强制刷新；force 只绕过新鲜度检查，不绕过启用、必填参数和已有执行任务检查。
- 禁用、删除或修改执行配置时取消 in-flight 任务，取消传到后台执行器。修改配置后的新执行等待旧任务结束，已取消或过期结果不发布。
- 系统睡眠期间停止发起定时刷新，唤醒后检查到期插件；4 小时安全超时避免状态永久停留在非活动态。
- 更新检查由独立 Task 循环按 6 小时间隔在后台持续执行；自动检查失败静默并保留已有结果，只有手动检查向用户反馈错误。不自动弹出提示；有可用更新且 `showUpdateBadge` 开启（默认开启，通用设置可关闭）时，主界面顶部显示新版本胶囊，点击胶囊或在关于页手动检查更新才打开提示面板。关于页直接使用该次手动检查的更新结果回调，不监听后续 `availableUpdate` 变化来触发弹窗；无更新或失败后不保留提示意图。`UpdatePrompt` 使用非模态 NSPanel，订阅 `availableUpdate` 并在下一轮主线程读取最新结果，刷新版本、说明和窗口尺寸；结果为空时关闭，关闭时取消订阅，延迟展示前重新校验结果。面板操作及胶囊在检查或安装期间禁用；安装入口接收面板的 `UpdateInfo` 并验证它仍等于当前结果，避免过期确认安装其他版本。面板按钮显示下载/安装/失败状态，关于页显示详细进度和错误。

配置写入：`scheduleConfigurationWrite` 通过后台 `ConfigurationSaveCoordinator` 串行等待前一次保存，使用 generation 合并尚未执行的旧快照。`persistConfiguration` 只保存；`saveConfiguration` 还重建快照、调整调度和刷新到期插件。异步 `flushConfiguration` 持续等待保存，覆盖等待期间新增的写入；更新安装在请求退出前调用它。退出回调使用不依赖 MainActor 的同步等待，上限 5 秒；完成后返回 `.terminateNow`，超时返回 `.terminateCancel`，保留后台保存任务供完成后再次退出。

## 5. 插件执行与协议

`PluginExecutor` 对 `.py` 使用 `/usr/bin/env python3 <script>`，其他可执行文件直接运行；不经过 shell。参数为重复的 `--usageboard-param KEY=value`，并注入当前会话语言 `USAGEBOARD_LANGUAGE`。

- 默认执行超时 15 秒；启动后确认插件是独立进程组首领才向该组发送信号。超时、取消或 stdout 超限时向整组发送 SIGTERM，保留最多 1 秒清理宽限期，再对仍存活成员发送 SIGKILL；父进程提前退出不会缩短后代的宽限期。正常退出后仍存活的同组后代也会清理，合法父进程输出仍可成功发布。未确认独立组时只处理直接进程；自行脱离进程组的后代不在保证范围内。
- stdout 最多 8 MiB；stderr 保留前 64 KiB 并持续排空，避免管道阻塞。
- 环境设置 UTF-8，并以 `PYTHONDONTWRITEBYTECODE=1` 禁止写入 Python 字节码。
- 非零退出码先作为错误处理，优先展示 stderr；退出码 0 时先识别非空顶层 error，再解码成功对象。

Codex 在用量与本地统计完成后查询可选重置卡：最多额外等待 2 秒，且不超过 main 开始后的 12 秒截止时间；已无预算则跳过。请求在 daemon 线程执行，以限制包含 DNS 和响应读取在内的整体等待，超时省略 credits 并正常输出主数据。

`PluginMetadataParser` 读取 UTF-8 文件，仅扫描前 80 行。`UsageBoardPlugin:` 和结束标记 `/UsageBoardPlugin` 及整个 JSON 注释块都必须在此范围内。无效或未闭合的块不产生 metadata。

Kimi 对无法确认时区的可选重置时间返回 null，不猜测 UTC；MiniMax 保持缺失 base_resp 的既有兼容行为，但显式 null 或其他非对象值返回解析失败；Claude 的空套餐字段回退配置值，再回退 pro。

元数据参数支持 string、secret、integer、boolean、choice、directory、file。展示字段通过 `field@zh-Hans` / `field@en` 提供翻译，缺失或为空时回退基础字段。用量项目名称和错误文本由插件按语言参数直接返回，不从 metadata 翻译。

成功输出最小示例：

```json
{
  "updatedAt": "2026-09-09T00:00:00Z",
  "items": []
}
```

失败输出（退出码 0）：

```json
{ "error": "API Key 无效" }
```

chart 使用 `kind: "line"` 的桶/分段数据，line/bar 的实际渲染由全局 chartMode 决定。bucketUnit 支持 hour/day，解码时其他值回退 day。完整字段见插件编写说明，避免在架构文档重复协议表。

内置安装器每次启动检查包内 `Contents/Resources/Plugins/`（开发时回退当前目录 `Resources/BundledPlugins/`），只为非 `_` 开头的 `.py` 创建链接。正确链接跳过、旧链接或失效链接替换，同名普通文件保留；`_common.py` 留在包内与脚本一起使用。

## 6. 界面、主题与本地化

App 采用 `.accessory` 激活策略，不占 Dock 位。AppDelegate 管理 NSStatusItem、NSPopover 和设置 NSWindow；popover 使用 applicationDefined 行为，配合局部/全局点击监听关闭，关闭时清理监听。

- 设置窗口初始 800×520，最小 800×480。
- popover 固定宽 380，高度随内容缩放，上限为状态栏所在屏幕可用高度的 75%。OverviewView 使用纵向 fixedSize 支持收缩，MeasuredScrollView 按扣除标题等区域后的预算滚动。
- DashboardView 切换 grouped/tabs；PluginGroupView 展示图标、套餐、倒计时、用量和可折叠图表。重置卡默认收起为数量与最近到期摘要，整行点击展开按到期时间排序的两列卡片明细（每排两张，奇数张时最后一张左对齐）；常态使用次级文字色，临近到期才着色。
- UsageProgressBar 显式 color 优先；未指定或无法识别时，按进度 <60% 蓝、60%–<80% 黄、80%–<100% 橙、100% 红。status 不决定颜色。文字按已填充区域遮罩切色，黄/橙/绿底用黑字，蓝/红底用白字。
- PlanTag 显示大写套餐名，前景色配同色淡背景；badgeColor 优先，否则按 PRO/PLUS/TEAM/FREE/MAX 等预设匹配。

图表由 `TokenChartView.swift` 的 TokenUsageChartView 组织摘要、选择状态和模式，TokenLineChartPlot / TokenBarChartPlot 绘制：

- 选择摘要可只展示总量或某一分项，再次选择恢复全部。
- 直方图只堆叠分项，避免把总量重复相加；仅有总量时回退总量，堆叠顺序与图例一致。
- 图表绘图区高 170 pt，支持横向滚动；纵轴刻度由共享 TokenChartAxisScale 计算，选择易读步长。
- hover 提示在滚动视口外层渲染，结合内容偏移换算桶，防止滚动后错位和长提示裁剪；未选择单项时过滤零值分项，空桶仍保留总量；选择单项时保留该项，即使当前桶为零。

设置页使用通用/插件/关于三栏。插件草稿由 SettingsView 持有，切换栏目保留；切换或新增插件前处理未保存编辑。保存通过 Store.updatePlugin 校验路径、重载路径变化后的 metadata/defaultValue，并校验已启用插件必填参数。启用/禁用与拖拽排序即时生效。choice 按可用宽度只实例化分段或菜单之一，长选项回退菜单。

AppTheme 枚举定义在 Core 的 AppConfiguration.swift；App 层扩展映射 NSAppearance。主题立即持久化，并更新 NSApp、已有 popover 和 hosting view；system 清除外观覆盖以继承系统设置。

语言选择保存到 configuration.language，当前会话继续使用 activeLanguage。选择不同语言出现 SwiftUI 重启提示；“稍后重启”保留选择，“立即重启”调用 AppRelauncher.relaunchCurrent 并在退出前等待保存。切回当前语言不提示。固定 UI 文案集中在 AppLocalization，新文案同时补中英文。

BrandTile 接受 HTTP(S)、绝对文件路径、file URL 和资源相对路径。相对路径以包内 Resources（开发时当前目录 Resources）为根；仅 `icons/light/` 相对路径在深色主题下优先同名 dark，缺失回退 light。NSCache 以实际 URL 缓存，SwiftUI task 以解析后的 URL 为标识，取消任务不回写。远程图标限制为 2 MiB，请求无进展超时 10 秒、资源总时限 20 秒；超量、取消或失败均保留名称首字母占位。此限制仅针对远程传输字节，不限制本地文件或解码后像素内存。

## 7. 更新、构建与发布

在线更新由 Store 组装三步：

1. UpdateChecker 从 Info.plist 的 UBUpdateCheckURL 获取 version.json，按点分整数比较版本（缺段补零，不是完整 SemVer 预发布规则）。
2. UpdateDownloader 用独立 URLSession 下载 ZIP，接收过程中限制为 64 MiB，请求无进展超时 60 秒、资源总时限 300 秒；失败或取消清理临时 ZIP。成功后用 ditto 解压；校验顶层唯一 UsageBoard.app、应用标识、APPL 类型、期望版本和包内可执行普通文件。
3. AppRelauncher 在目标目录暂存并签名新 app；旧进程退出后备份旧 app、替换并启动。移动或启动命令失败恢复旧 app，成功后清理备份。

检查和下载要求 HTTPS、无 URL 用户凭据以及成功 HTTP 状态，重定向最终 URL 也校验。Store 分别维护检查/安装忙碌状态。回滚判断基于脚本命令退出状态，不等于新 app 启动后的健康检查。当前下载限制不构成解压配额；仍未实施解压过程体积上限或独立发布者认证，发布及替换继续使用 ad-hoc 签名。

`scripts/build.sh` 停止现有 UsageBoard，构建 release，打包二进制、插件、帮助和图标，注入更新 URL、ad-hoc 签名并启动。首次创建 bundle 使用 0.1.0，已有版本保留；可用 UB_UPDATE_CHECK_URL 覆盖检查地址。

`scripts/release.sh` 直接上传服务器：显式版本优先，否则递增本地 bundle 版本的 patch；更新说明使用第二个参数，否则取最新本地 tag 到 HEAD 的提交。目标版本及 build 号在 Swift 构建成功后才写入 bundle，构建失败保留已有版本和二进制；更新说明使用 printf 传入 JSON 转义，保留选项样式文本、反斜线和换行。它生成 ZIP/version.json 并保留远端最近三个 ZIP，不会创建/推送 Git tag、发布 GitHub Release 或更新 Homebrew。完整发布需另行完成这些渠道并核对同一 ZIP 的 SHA-256；操作步骤见 README 和项目指引。

## 8. 验证与维护

从项目根目录运行：

```sh
swift build
swift test
python3 -m pytest Tests/PluginTests -q
python3 -m py_compile Resources/BundledPlugins/*.py
bash -n scripts/build.sh scripts/release.sh
bash Tests/ScriptTests/test_release_version_timing.sh
```

按修改范围选用验证：Swift 改动运行相关 XCTest 和构建；内置插件改动运行 Python 测试，并通过 `bash scripts/build.sh` 重建才能在已打包 app 生效。只改用户独立插件时无需重建 app。纯文档修订检查代码依据、链接、示例和 `git diff --check`，无需重启应用。

测试使用临时目录、假配置及网络替身，不读取真实凭据或用户数据。解释器兼容测试使用可用的 `/usr/bin/python3`，以及设置 HOMEBREW_PREFIX 后可用的 Homebrew Python。App 测试包含原生宿主窗口断言，但不能代替系统睡眠/唤醒、登录启动、VoiceOver、真实更新和语言重启的端到端验收。

新增能力按现有职责落点：模型在 Core，调度/配置方法在 Store，设置项在对应 Settings 文件，图表在 Dashboard；仅共享视觉原语放入 DesignSystem。同步用户说明、插件协议和相关测试，避免复制实现代码到计划文档。

TASKS 只维护待办、待验收和简短收口记录。已完成实施步骤及临时代码清单清理，长期行为留在本架构文档，提交和发布历史查询 Git。TASKS.md、CLAUDE.md、AGENTS.md 当前按仓库忽略规则在本地维护。
