# UsageBoard 架构说明与开发规范

本文以当前 `Package.swift`、`Sources/`、内置插件和构建脚本为依据。用户功能与配置示例见 [README](../README.md)，插件完整协议见 [插件编写说明](../Resources/PluginAuthoringGuide.html)。

## 1. 项目与代码组织

UsageBoard 是 macOS 菜单栏应用，通过外部插件聚合服务配额、账户余额和本地 token 统计。主程序负责配置、调度、缓存和展示，插件负责获取数据。

- 运行平台：macOS 13+；Python 插件通过可用的 `python3` 执行。
- 构建：Swift Package Manager，最低 Swift tools version 为 6.3，Swift language mode 为 6。
- App：SwiftUI + AppKit，`ObservableObject` / `@Published`，使用 `SMAppService` 管理开机启动。
- 测试：XCTest（Core、App）和 unittest（Python 插件）。

| 位置 | 职责 |
| --- | --- |
| `Sources/UsageBoardCore/` | 配置与输出模型、JSON 编解码、插件执行与元数据解析、缓存、更新和重启 |
| `Sources/UsageBoardApp/UsageBoardApp.swift` | App 入口、AppDelegate、菜单栏、popover 与设置窗口生命周期 |
| `Sources/UsageBoardApp/UsageBoardStore.swift` | 主状态、配置写入、插件调度、刷新、更新与开机启动 |
| `Sources/UsageBoardApp/AppTheme.swift` | Core 的 AppTheme 到 NSAppearance 的映射 |
| `Sources/UsageBoardApp/AppLocalization.swift` | 中英文固定文案 |
| `Sources/UsageBoardApp/AppMenu.swift` / `UpdatePrompt.swift` | 应用/编辑/窗口菜单；更新提示非模态面板 |
| `Sources/UsageBoardApp/Dashboard/` | 分组/标签页、用量行、统计图与滚动布局 |
| `Sources/UsageBoardApp/Settings/` | 通用、插件、关于三页，插件编辑草稿和参数表单 |
| `Sources/UsageBoardApp/DesignSystem/` | 视觉 token、应用/品牌图标、倒计时和套餐徽章 |
| `Tests/UsageBoardTests/` | Core XCTest |
| `Tests/UsageBoardAppTests/` | Store 调度、主题、语言提示、图标、popover 与图表 XCTest |
| `Tests/PluginTests/` | 内置插件、公共缓存和错误分类、解释器兼容性测试 |
| `Tests/ScriptTests/` | 打包与发布脚本的隔离 bash 测试 |
| `Resources/BundledPlugins/` | 八个 Python 插件和 `_common.py` |
| `Resources/icons/` | light/dark 插件 PNG，来源与哈希见目录内 README |
| `Resources/PluginAuthoringGuide.html` | 随 app 打包的插件协议说明 |
| `Resources/UsageBoard.icns` | 应用图标 |
| `scripts/build.sh` / `scripts/release.sh` | 本地打包启动 / 服务器发布 |
| `website/` | 项目主页静态文件（HTML、截图与图标素材） |
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

Claude/Codex 的增量统计缓存位于各自 `DATA_DIR/.usageboard-chart-cache.json`，不在 `states/`。GLM 缓存可由插件内部的 cache_dir 或 `USAGEBOARD_CACHE_DIR` 覆盖。Claude 全量重建按记录时间扫描所有日志，不以文件 mtime 排除文件；缓存版本 8 重建会话统计并收集所有记录中的绝对 `cwd`，持久化到 `classifier_dirs`，增量扫描继续补充目录。三个插件各自维护独立的图表缓存版本（见各插件 `CACHE_VERSION` 常量），首次读取旧版本会重建近 30 天数据，随后按最后缓存日起增量覆盖；GLM 曾因此纠正旧跨日漏计，Codex 曾因此纠正旧解析器遇坏字节后遗漏的历史数据。Codex 按行解码 UTF-8，损坏行整体跳过，不中断后续有效记录。Claude/Codex 的模型统计名归一化由 `_common.normalize_model_name` 完成：按 `/` 取末段并剥离代理常见的末尾思考强度括号标注（如 `gpt-5(high)`、`gpt-5（high）`），合并同名数据。

Claude classifier 使用客户端内部开关 `AUTOMODE_DECISION_LOG=1` 写出的工作目录 `.automode_decisions.jsonl`，无需服务或额外插件参数。插件仅检查缓存中已发现 cwd 下的固定文件名，不递归遍历项目；通过 device/inode 去除同一文件的路径别名。只累计 `allowlisted: false`、`classifierSource: local` 且有合法实际 token 的记录，按毫秒时间戳归属本地日期，与会话统计合并到同名模型。classifier 用量每次全量读取近 30 天，不写入会话 days 缓存，避免重复累加或删除日志后残留。无请求 ID，不对相同行做去重；损坏行、非法数值和未完成末行逐行跳过。无持久化会话无法保证发现 cwd；服务端 classifier 不追加，模型回退总量可能归到最终模型。这是 2.1.280 实测的内部日志格式，不保证其他版本或所有失败/取消路径完整覆盖。

配置默认值：schemaVersion 1、中文、跟随系统主题、tabs、line、不启用开机启动、插件列表为空。安装内置链接不会自动把插件加入配置；用户仍需添加和启用。

`PluginConfiguration.id` 是不持久化的运行时 UUID；`stateID` 是持久化缓存 ID。通过 Store.updatePlugin 修改脚本路径、参数或 metadata 时会换用新的 stateID，防止复用旧配置的数据，旧 stateID 的磁盘与内存缓存在旧刷新（包括已开始的缓存写入）结束后后台清理；删除插件同样清理。执行路径使用实际文件路径，不展开 `~` 或 shell 表达式，以 `~` 开头的路径直接报错拒绝；插件参数是否展开路径由插件自身决定。

文件选择器会解析符号链接返回真实路径；addPlugin 与 updatePlugin 统一经 `canonicalExecutablePath` 归一：所选文件与 `plugins/` 目录内同名链接目标一致时改存链接路径本身，app 包迁移或重建后安装器重新指向新包时配置中的执行路径保持有效。

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

- 默认执行超时 15 秒；启动后确认插件是独立进程组首领才向该组发送信号。超时、取消或 stdout 超限时向整组发送 SIGTERM，保留最多 1 秒清理宽限期，再对仍存活成员发送 SIGKILL；父进程提前退出不会缩短后代的宽限期。响应 SIGTERM 在宽限期内自行退出的进程按实际退出码报告而非超时；被 SIGKILL 强杀仍报超时，任务取消则报已取消。正常退出后仍存活的同组后代也会清理，合法父进程输出仍可成功发布。未确认独立组时只处理直接进程；自行脱离进程组的后代不在保证范围内。
- stdout 最多 8 MiB；stderr 保留前 64 KiB 并持续排空，避免管道阻塞。
- 环境设置 UTF-8，并以 `PYTHONDONTWRITEBYTECODE=1` 禁止写入 Python 字节码。
- 非零退出码先作为错误处理，优先展示 stderr；退出码 0 时先识别非空顶层 error，再解码成功对象。

Codex 在用量与本地统计完成后查询可选重置卡：最多额外等待 2 秒，且不超过 main 开始后的 12 秒截止时间；已无预算则跳过。请求在 daemon 线程执行，以限制包含 DNS 和响应读取在内的整体等待，超时省略 credits 并正常输出主数据。

Command Code 使用 API Key 查询 `/alpha/billing/credits` 的 `windowLimits.fiveHour` / `weekly`（used、cap、resetAt）及 `credits.monthlyCredits`；月上限暂按周上限两倍估算，月已用取上限减余额且下限为零，充值余额不参与。缺少周窗口或周上限不大于零时省略月项；缺失金额不伪造零用量。`subscriptions` 仅补充套餐与账期，失败不丢弃额度。两个请求分别使用 6 秒与 3 秒网络超时，不跟随携带密钥的重定向。套餐通过 badgeColor 显式映射 GO→teal、GOAT→blue、MAX→orange；插件复用现有 percent 输出、主题图标与错误处理，不改变协议。

`PluginMetadataParser` 读取 UTF-8 文件，仅扫描前 80 行。`UsageBoardPlugin:` 和结束标记 `/UsageBoardPlugin` 及整个 JSON 注释块都必须在此范围内。无效或未闭合的块不产生 metadata。

Kimi 提供 PLAN choice：Go / Plus / Pro / Max，设置默认 Go，徽标依次使用 gray / indigo / blue / orange；套餐仅来自手动配置，未配置或值无效时省略徽标，不再解析用量响应中的 `user.membership.level`（2026-09-20 实测该字段已不存在，官方控制台 GetSubscription 接口使用同一 API Key 返回 401，因此删除等级回退映射，也不根据额度或钱包 subscriptionId 猜测等级）。Kimi 对无法确认时区的可选重置时间返回 null，不猜测 UTC；MiniMax 保持缺失 base_resp 的既有兼容行为，但显式 null 或其他非对象值返回解析失败；Claude 的空套餐字段回退配置值，再回退 pro。

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

启动使用纯 AppKit 生命周期，不声明 SwiftUI Settings scene。AppDelegate 在启动时安装 AppMenu 创建的中英文应用、编辑与窗口菜单；应用菜单含 Settings…（Cmd+,，沿 responder chain 调 AppDelegate.openSettings）与退出，窗口菜单提供 Cmd+W 关闭与 Cmd+M 最小化，编辑命令通过 nil target 沿 responder chain 送到当前输入框，保留撤销、重做、剪切、拷贝、粘贴和全选快捷键。

- 设置窗口初始 800×520，最小 800×480；左侧导航栏宽 120，导航项图标 15 pt、文字 14 pt；插件列表宽 210。输入框和分段控件使用 regular 尺寸，开关使用 small，插件搜索框高 32 pt。
- popover 固定宽 380，高度随内容缩放，上限为状态栏所在屏幕可用高度的 75%。OverviewView 使用纵向 fixedSize 支持收缩，MeasuredScrollView 按扣除标题等区域后的预算滚动。
- DashboardView 切换 grouped/tabs；PluginGroupView 展示图标、套餐、倒计时、用量和可折叠图表。重置卡默认收起为数量与最近到期摘要，整行点击展开按到期时间排序的两列卡片明细（每排两张，奇数张时最后一张左对齐）；常态使用次级文字色，临近到期才着色。
- 倒计时、重置时间、用量项目名称和图表统计标题/单位共用 `UB.Text.supporting`（主文字色的 75% 不透明度），保持深浅主题下的可读性。
- UsageProgressBar 显式 color 优先，status 不决定颜色；未指定时的切色阈值与文字遮罩配色、PlanTag 徽章的 badgeColor 值域与预设匹配规则以插件编写说明的协议表为准，不在此重复。

图表由 `TokenChartView.swift` 的 TokenUsageChartView 组织摘要、选择状态和模式，TokenLineChartPlot / TokenBarChartPlot 绘制：

- 派生数据在视图初始化时完整建立，chart 或 language 变化时更新；首帧即可安全读取总量，hover 复用已有数据。折线路径与柱状分段布局使用等值子视图隔离，数据/尺寸/比例不变时不随 hover 重建；指示线与柱高亮单独更新。
- 选择摘要可只展示总量或某一分项，再次选择恢复全部。
- 直方图只堆叠分项，避免把总量重复相加；仅有总量时回退总量，堆叠顺序与图例一致。
- 图表绘图区高 170 pt，支持横向滚动；纵轴刻度由共享 TokenChartAxisScale 计算，选择易读步长。
- hover 提示在滚动视口外层渲染，结合内容偏移换算桶，防止滚动后错位和长提示裁剪；未选择单项时过滤零值分项，空桶仍保留总量；选择单项时保留该项，即使当前桶为零。

设置页使用通用/插件/关于三栏。通用页的主题、显示模式、图表模式、语言与插件 choice 参数共用 SettingsSegments；显式设置 selectedSegmentBezelColor 为系统强调色，避免不同 SDK 兼容外观下选中态退回白色。插件草稿由 SettingsView 持有，切换栏目保留；关闭保护在整个设置窗口生命周期内有效，不随插件页退出而注销。切换、新增或删除插件以及关闭设置窗口前处理未保存编辑，保存校验失败会阻止继续；删除另需确认。保存通过 Store.updatePlugin 校验路径、重载路径变化后的 metadata/defaultValue，并校验已启用插件必填参数。启用/禁用与拖拽排序即时生效。插件列表使用 macOS 原生 List 选择与 onMove 排序，避免行内选择 Button 拦截拖拽；由 Store 一次更新配置、快照和持久化；搜索时仅重排可见插件所在位置，隐藏插件位置不变。choice 使用原生 NSSegmentedControl 的等宽分段与系统强调色选中态，通过 AppKit intrinsicContentSize 在首帧测量；ViewThatFits 按可用宽度选择分段或菜单，长选项回退菜单。

AppTheme 枚举定义在 Core 的 AppConfiguration.swift；App 层扩展映射 NSAppearance。主题立即持久化，并更新 NSApp、已有 popover 和 hosting view；system 清除外观覆盖以继承系统设置。

语言选择保存到 configuration.language，当前会话继续使用 activeLanguage。选择不同语言出现 SwiftUI 重启提示；“稍后重启”保留选择，“立即重启”调用 AppRelauncher.relaunchCurrent 并在退出前等待保存。切回当前语言不提示。固定 UI 文案集中在 AppLocalization，新文案同时补中英文。

BrandTile 接受 HTTP(S)、绝对文件路径、file URL 和资源相对路径。相对路径以包内 Resources（开发时当前目录 Resources）为根；仅 `icons/light/` 相对路径在深色主题下优先同名 dark，缺失回退 light。NSCache 以实际 URL 缓存，SwiftUI task 以解析后的 URL 为标识，取消任务不回写。远程图标限制为 2 MiB，请求无进展超时 10 秒、资源总时限 20 秒；超量、取消或失败均保留名称首字母占位。此限制仅针对远程传输字节，不限制本地文件或解码后像素内存。

## 7. 更新、构建与发布

在线更新由 Store 组装三步：

1. UpdateChecker 从 Info.plist 的 UBUpdateCheckURL 获取 version.json，按点分整数比较版本（缺段补零，不是完整 SemVer 预发布规则）；版本号相同时若服务器 `latestBuild` 与本地 CFBundleVersion 均存在且更高，同样判定为有更新。
2. UpdateDownloader 用独立 URLSession 下载 ZIP，接收过程中限制为 64 MiB，请求无进展超时 60 秒、资源总时限 300 秒；失败或取消清理临时 ZIP。成功后用 ditto 解压；校验顶层唯一 UsageBoard.app、应用标识、APPL 类型、期望版本、期望 build（声明 latestBuild 时包内 CFBundleVersion 必须一致，拒绝同版本旧包被反复安装）和包内可执行普通文件。
3. AppRelauncher 在目标目录暂存并签名新 app；旧进程退出后备份旧 app、替换并启动。移动或启动命令失败恢复旧 app，成功后清理备份。

检查和下载要求 HTTPS、无 URL 用户凭据以及成功 HTTP 状态，重定向最终 URL 也校验。Store 分别维护检查/安装忙碌状态。回滚判断基于脚本命令退出状态，不等于新 app 启动后的健康检查。当前下载限制不构成解压配额；仍未实施解压过程体积上限或独立发布者认证，发布及替换继续使用 ad-hoc 签名。

`scripts/build.sh` 与 `scripts/release.sh` 的 Info.plist 创建、版本格式校验（点分整数，非法退出）、资源复制、更新 URL 注入与 codesign 签名校验共用 `scripts/_package_common.sh`。build.sh 每 0.2 秒检查旧实例是否退出，最多等待 10 秒，超时中止而不覆盖运行中的 bundle；退出后构建 release 并启动；首次创建 bundle 使用 0.1.0，已有版本保留。两脚本均可用 UB_UPDATE_CHECK_URL 覆盖检查地址。

`scripts/release.sh` 直接上传服务器：显式版本优先，否则递增本地 bundle 版本的 patch；build 号默认取 UTC `%y%j%H%M`（年+年积日+时+分），可用 APP_BUILD 覆盖。更新说明使用第二个参数，否则取最新本地 tag 到 HEAD 的提交。目标版本及 build 号在 Swift 构建成功后才写入 bundle，构建失败保留已有版本和二进制；更新说明使用 printf 传入 JSON 转义，保留选项样式文本、反斜线和换行。它生成 ZIP/version.json（含 `latestVersion`、`latestBuild`、`downloadURL`、`notes`）并保留远端最近三个 ZIP，不会创建/推送 Git tag、发布 GitHub Release 或更新 Homebrew。完整发布需另行完成这些渠道并核对同一 ZIP 的 SHA-256；操作步骤见 README 和项目指引。关于页显示 `版本 (build)` 供核对。

## 8. 验证与维护

从项目根目录运行：

```sh
swift build
swift test
python3 -m unittest discover -s Tests/PluginTests -q
python3 -m py_compile Resources/BundledPlugins/*.py
bash -n scripts/build.sh scripts/release.sh
for script in Tests/ScriptTests/*.sh; do
  bash "$script" || exit 1
done
```

按修改范围选用验证：Swift 改动运行相关 XCTest 和构建；内置插件改动运行 Python 测试，并通过 `bash scripts/build.sh` 重建才能在已打包 app 生效。只改用户独立插件时无需重建 app。纯文档修订检查代码依据、链接、示例和 `git diff --check`，无需重启应用。

测试使用临时目录、假配置及网络替身，不读取真实凭据或用户数据。解释器兼容测试使用可用的 `/usr/bin/python3`，以及设置 HOMEBREW_PREFIX 后可用的 Homebrew Python。App 测试包含原生宿主窗口断言，但不能代替系统睡眠/唤醒、登录启动、VoiceOver、真实更新和语言重启的端到端验收。

新增能力按现有职责落点：模型在 Core，调度/配置方法在 Store，设置项在对应 Settings 文件，图表在 Dashboard；仅共享视觉原语放入 DesignSystem。同步用户说明、插件协议和相关测试，避免复制实现代码到计划文档。

TASKS 只维护待办、待验收和简短收口记录。已完成实施步骤及临时代码清单清理，长期行为留在本架构文档，提交和发布历史查询 Git。TASKS.md、CLAUDE.md、AGENTS.md 当前按仓库忽略规则在本地维护。
