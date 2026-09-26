# UsageBoard 全面 Review 优化计划

> **状态：已执行完毕（2026-09-26）**。批次 1–7 对应提交 `498d488` / `f1d176b` / `49d5149` / `c1241fc` / `806f14e` / `9057396` / `034eb3d`，验证与收口记录见 TASKS.md；本文档留档不再更新。

> 2026-09-25 依据四路并行代码审查（Core / App·UI / 插件 / 文档·脚本）汇总制定。
> 基线：Swift 140 项测试（Core 57 + App 83）、Python unittest 151 项全部通过；HEAD `75af930`。
> 本文档供审核，审核通过后按批次执行；每批完成后更新 TASKS.md 并验证。
>
> **修订记录（2026-09-25 二审）**：
> 1. 移除批次 4.1.2 `maintain_daily_cache` 提取——复核三插件实际代码后确认回调签名差异过大，真实去重收益仅约 30 行，引入回调抽象代价大于收益，属低收益项。
> 2. 批次 4.2.6 `~` 展开方向反转——改为代码向文档对齐（统一不展开），而非推翻文档承诺。
> 3. 批次 6.3 字号收敛收窄——只做 token 定义 + 迁移 3-5 处最明显的，不全面替换 50+ 处硬编码，避免视觉回归风险。
> 4. 批次 1.4 glm "总计" 联动——明确 App 侧过滤改为排除三个标签值，并补 TokenChartView 测试。

## 目标与原则

- 修复真实缺陷，不新增功能，不改变插件对外协议和发布流程。
- 去重以"提取到既有公共层"为限（`_common.py` / Core 模型 / DesignSystem），不新建抽象层。
- 安全修复只处理真实风险，不加推测性防护。
- 每批独立可验证、可单独提交；行为变化补回归测试。

## 批次总览

| 批次 | 内容 | 主要验证 |
| --- | --- | --- |
| 1 | 插件缺陷与安全（claude/codex/glm/kimi/minimax/deepseek） | Python unittest + py_compile |
| 2 | App 缺陷（草稿丢失、stateID 孤儿、错误横幅滞留） | swift test（App） |
| 3 | 效率（图表 hover 重算、日期 formatter、claude 全量扫描） | swift test + unittest + 行为对比 |
| 4 | 去重精简（_common 提取、Core/App 散落重复、死代码） | 全量测试 |
| 5 | 脚本合并与校验（_package_common.sh、版本格式、InTime 残留） | bash -n + ScriptTests + build.sh 实测 |
| 6 | UI 一致性（菜单、按钮样式、错误色、字号收敛、help 提示） | swift test（App）+ 构建后视觉验收 |
| 7 | 文档修正（README 缓存版本、website、Kimi Adagio、措辞） | 链接与 diff 检查 |

---

## 批次 1：插件缺陷与安全

### 1.1 claude 插件 getmtime 竞态（F1）

- **问题**：`claude-usage-plugin.py:363` 列表推导 `[f for f in all_jsonl_files(data_dir) if os.path.getmtime(f) >= cutoff_ts]`，glob 与 getmtime 之间文件被 Claude Code 轮转清理即抛 `FileNotFoundError`，插件整体失败。codex 插件（`codex-usage-plugin.py:434-438`）对同样场景有 `try/except OSError`，claude 漏了。
- **修改**：在 `_common.py` 新增 `filter_by_mtime(files, cutoff_ts)`（内部逐文件 try/except OSError 跳过），claude 改用之；codex:434-438 同时切换为该函数。
- **顺带**：删除 claude:231-235 死代码 `recent_jsonl_files`（全仓库无调用方，且同样有此竞态）。
- **测试**：`Tests/PluginTests/test_claude_plugin.py` 补用例——glob 返回的文件在 getmtime 时抛 FileNotFoundError，结果跳过该文件不抛异常。

### 1.2 claude 空 DATA_DIR 参数退化（F2）

- **问题**：`claude-usage-plugin.py:424` `params.get("DATA_DIR", "~/.claude")`，宿主传 `DATA_DIR=""` 时 `realpath("")` 解析为进程 CWD，扫描错误目录并把缓存写进 CWD。codex:643 用 `or "~/.codex"` 处理了空串。
- **修改**：改为 `(params.get("DATA_DIR") or "").strip() or "~/.claude"`。
- **测试**：补用例——DATA_DIR="" 时解析为 `~/.claude` 的 realpath。

### 1.3 codex 重定向凭证泄漏（S1）+ 统一 fetch_json（R1 第一步）

- **问题**：codex:141-143、157-159 使用 `urllib.request.urlopen`，默认 `HTTPRedirectHandler` 重定向时跨主机原样转发 `Authorization` / `ChatGPT-Account-Id` 头。commandcode:61-64 已有 `NoRedirect` 防护。
- **修改**：`_common.py` 新增：
  ```python
  class _NoRedirect(urllib.request.HTTPRedirectHandler):
      def redirect_request(self, req, fp, code, msg, headers, newurl):
          return None

  def fetch_json(url, headers=None, timeout=10.0):
      """GET JSON；不跟随重定向（避免凭证随 302 泄漏），超时/HTTP 错误原样抛出由调用方分类。"""
      request = urllib.request.Request(url, headers=headers or {})
      opener = urllib.request.build_opener(_NoRedirect)
      with opener.open(request, timeout=timeout) as response:
          return json.loads(response.read().decode("utf-8"))
  ```
  本批只接入 codex（两处）与 commandcode（替换其本地 NoRedirect，删除重复实现）。其余 5 个插件在批次 4 统一接入。
- **注意**：codex 现有 `except` 级联保持不变；`decode("utf-8")` 的 UnicodeDecodeError 归入 parse 错误的问题（原 L3）随 fetch_json 统一时在批次 4 处理，本批不改错误分类行为。
- **测试**：`test_common_cache.py` 或新增 `test_common_fetch.py`——mock 层验证 redirect 不跟随（302 响应抛出 HTTPError 而非转发）；codex 现有测试保持通过。

### 1.4 glm "总计" 硬编码（F3）

- **问题**：`glm-usage-plugin.py:566` 回退序列标签字面量 `"总计"`，英文界面也显示中文。
- **修改**：TRANSLATIONS 增加 `"total": {"zh-Hans": "总计", "en": "Total"}`；`apply_aligned_model_series` 增加 `language` 参数，566 行改用 `translate(language, "total")`。调用点同步传参。
- **联动检查（修正后明确方案）**：App 侧 `TokenChartView.swift:67` 有 `.filter { $0.key != "总计" }` 的硬编码中文排除——glm 改为翻译键后英文环境回退序列名为 "Total"，过滤失效，回退序列会同时出现在"总量"和"模型摘要"两处重复显示。**必须同一批同步修改** App 侧：过滤条件改为排除 `strings.text(.totalTokenUsage)`、"总计"、"Total" 三个值（不改插件协议、不给回退序列加 marker——保持协议稳定优先）。
- **测试**：glm 插件测试补英文语言下回退序列名为 "Total"；`Tests/UsageBoardAppTests/`（TokenBarChartModelTests 或相邻文件）补"回退序列不在模型摘要中重复显示"的用例，覆盖中/英两种标签。

### 1.5 kimi used:null 遮蔽回退（F6）

- **问题**：`kimi-usage-plugin.py:119` `if "used" in detail:`，服务端返回 `"used": null` 时 numeric(None)=0，不再走 `limit - remaining` 回退。
- **修改**：改为 `if detail.get("used") is not None:`。
- **测试**：补用例——`used: null` + 有 remaining 时按回退计算。

### 1.6 minimax model_name 显示 "None"（F7）

- **修改**：`minimax-usage-plugin.py:129` `str(model.get("model_name", "unknown"))` → `str(model.get("model_name") or "unknown")`。
- **测试**：补用例——`model_name: null` 时名称为 "unknown"。

### 1.7 deepseek 错误分类（F8）

- **问题**：`deepseek-usage-plugin.py:92-93` 对 `status != 200` 抛 ValueError 落入兜底 network_error；urlopen 对 4xx/5xx 本已抛 HTTPError，该检查只误伤 2xx 中非 200 的罕见情况。
- **修改**：删除 92-93 的多余 status 检查（由 urlopen 的 HTTPError 覆盖）；`decode("utf-8")` 保持现状（批次 4 接入 fetch_json 后统一）。
- **测试**：deepseek 现有测试保持通过；补用例——HTTP 201/204 不再误报（若 API 实际只返回 200，可用 mock 验证）。

### 1.8 批次 1 验证

```sh
python3 -m unittest discover -s Tests/PluginTests -q
python3 -m py_compile Resources/BundledPlugins/*.py
```

---

## 批次 2：App 缺陷

### 2.1 设置窗口关闭/删除插件时的草稿丢失（F4）

- **问题 A**：`UsageBoardApp.swift:180-182` `windowWillClose` 直接置空 controller，未保存草稿静默丢弃。`resolveUnsavedChanges()` 只挂在切换/新增路径。
- **修改 A**：SettingsView 持有 `hasUnsavedChanges: Bool` 的导出（现有 `hasChanges` 逻辑在 PluginSettingsView 内部，需上抛）。方案：SettingsView 增加 `var onHasUnsavedChanges: ((Bool) -> Void)?` 回调或把 draft 状态上移至 SettingsView 层（`SettingsView.swift:28` 已持有 draft Binding 来源，检查其实际持有方后选择最小改动）。AppDelegate 实现 `windowShouldClose(_:) -> Bool`：有未保存草稿时弹出与 `resolveUnsavedChanges` 相同的 NSAlert（保存/放弃/取消），取消返回 false。为避免重复弹窗逻辑，把 alert 构造提取为可复用方法（放在 PluginSettingsView 可达的共享处，或 AppDelegate 内独立实现同文案 alert——优先复用现有文案键 `unsavedChanges`/`save`/`discardChanges`/`cancel`）。
- **问题 B**：`PluginSettingsView.swift:101-106` "−" 按钮直接 removePlugin，无未保存检查、无删除确认。
- **修改 B**：删除前先 `resolveUnsavedChanges()`；再加一个删除确认 alert（不可逆，含参数配置）。需新增两条本地化文案（`confirmRemovePlugin` 标题与说明），AppLocalization 中英文同步补。
- **测试**：`Tests/UsageBoardAppTests/` 补——windowShouldClose 逻辑（可提取为纯函数：有草稿→返回拦截意图）；删除确认状态机。NSAlert 交互本身不做端到端自动化，列入人工验收。

### 2.2 stateID 孤儿缓存文件（F5）

- **问题**：`UsageBoardStore.swift:297` 换 stateID 后旧 `states/<old>.json` 永不删除；PluginStateStore 无删除 API。
- **修改**：`PluginStateStore.swift` 增加 `remove(stateID:)`（删磁盘文件 + 清内存条目，失败静默）。`UsageBoardStore.updatePlugin` 换 stateID 时后台 `Task.detached` 调用删除旧文件；`removePlugin` 同样清理。注意 removePlugin 当前是否已清理——审查确认没有，一并补上。
- **测试**：`Tests/UsageBoardTests/` 补 PluginStateStore.remove 用例；App 侧补 updatePlugin 换 ID 后旧文件被删的集成用例（用临时目录）。

### 2.3 错误横幅滞留（U2 前置）

- **问题**：只有 `saveConfiguration()` 清 `lastError`；`requestLaunchAtLogin` 等失败后的红条不被后续成功操作清除。
- **修改**：`persistConfiguration()`、`setTheme`、`setShowUpdateBadge`、`requestLaunchAtLogin` 成功路径清 `lastError`（统一在 Store 内处理，不动 View）。同时给 SettingsView 错误横幅加关闭按钮（轻量：一个 × 按钮清空 `store.lastError`）。
- **测试**：Store 层补用例——setTheme 成功后 lastError 清空。

### 2.4 批次 2 验证

```sh
swift test --filter UsageBoardAppTests
swift test --filter UsageBoardTests
```

---

## 批次 3：效率

### 3.1 图表 hover 全量重算（P1）

- **问题**：`TokenChartView.swift` 的 `series`（15-35）、`modelSummaries`（59-78）、`visibleSeries`/`visibleBarSeries`/`visibleBarTooltipSeries`、`chartMaximum`（266-273）均为计算属性，每次 body 求值重建；`chartHover` @State 在 `onContinuousHover` 每次移动写入（214-217），整个图表 body 随鼠标移动反复全量重算，`series` 单次渲染被 chartMaximum、plot、tooltip 重复计算 3 次以上。
- **修改**：
  1. 把 `series`、`modelSummaries`、`totalTokens` 改为按 `chart` 缓存的 @State，在 `.onAppear` 与 `.onChange(of: chart)` 中计算一次（PluginChart 已 Equatable）。`visibleSeries` 等仍依赖 `selectedSeries`，保留为计算属性但基于缓存的 `series`，成本降为过滤级别。
  2. hover 处理拆分：tooltip overlay 与 hover 指示线拆为只接收 `resolvedHover` 的子 View，plot 本体不随 hover 重算（检查 TokenLineChartPlot/TokenBarChartPlot 的 hoverIndex 参数是否导致整体重绘——若是，把 hover 指示线从 plot 内部移到 overlay 层）。
- **行为约束**：不改变任何视觉与交互结果；1.4 的 "总计"/"Total" 过滤修正在此处一并落地。
- **测试**：`TokenBarChartModelTests`、`TokenChartAxisScaleTests` 保持通过；补 App 测试验证 onChange(of: chart) 缓存语义（若可测）。视觉验收列入批次 6。

### 3.2 ISO8601DateFormatter 重复创建（P2）

- **问题**：`JSONCoding.swift:21-29` 每个日期字符串新建 2 个 ISO8601DateFormatter；图表缓存解码含大量日期字段。
- **修改**：ISO8601DateFormatter 非线程安全。方案：用 `NSLock` 保护的静态共享实例对（fractional + plain），decode 闭包内加锁使用。JSONDecoder 本身仍是每调用点新建（开销小，不动）。
- **测试**：Core 现有日期解码用例保持通过；补小数秒/无小数秒/非法值三路径用例（若已有则跳过）。

### 3.3 claude 全量扫描 mtime 预过滤（P3）

- **问题**：`claude-usage-plugin.py:333-335` `full_scan_and_save` 全量逐行解析所有 jsonl；增量路径已有 mtime 过滤。
- **修改**：全量路径同样以 `scan_start_utc`（含 14h 余量）做 mtime 预过滤（复用批次 1 的 `filter_by_mtime`）。`parse_records` 内的时间过滤仍是权威，不会漏数据。
- **测试**：claude 插件测试补用例——旧 mtime 文件被跳过但其内近期记录仍由权威过滤保证（构造混合内容文件验证语义不变）。

### 3.4 批次 3 验证

```sh
swift test
python3 -m unittest discover -s Tests/PluginTests -q
```

---

## 批次 4：去重精简

### 4.1 _common.py 提取（R1 剩余 + R2 + 零散）

按收益排序逐项提取，每项提取后接入对应插件并跑测试：

1. **fetch_json 全量接入**（批次 1 已建）：glm、kimi、minimax、tavily、deepseek 接入；删除各插件重复的 Request/urlopen/json.loads 块与 main 中逐字相同的 5 分支 except 级联——提取 `run_query(fetch_fn, translate, language)` 封装级联。deepseek 顺带改用它修复 UnicodeDecodeError 误分类（原 L3）。commandcode 的 `success is False` 重复校验（原 L4）删除。
2. **~~maintain_daily_cache~~（R2，已移除）**：原计划提取 claude/codex/glm 三份缓存维护骨架。复核实际代码后移除该项——三者"骨架"（load→gap 判断→merge→save）虽同构约 30 行，但回调签名完全不同（claude 本地 jsonl+mtime / codex 本地 sessions+language 二次转换 / glm 远程 API+day_window），各自扫描逻辑约 120 行无法公共化，真实去重收益仅约 30 行，引入回调抽象的代价大于收益。**保留各插件独立实现**，仅以测试保证行为一致；批次 1 的 `filter_by_mtime` 已消除其中唯一的正确性差异（claude 竞态）。
3. **小函数**：`_parse_date`/`_format_date` 三份（→ `parse_day`/`format_day`）；UTC ISO Z 格式化五处（→ `iso_z(dt)`，`utc_now_iso` 改委托）；stat_range/day_window/bucket_id/bucket_label/chart_message（codex 与 glm 重复，以 glm 超集为准提取）；语言归一化（deepseek:118-119 改用 `app_language`）；reset 时间戳归一化四处（→ `reset_time_iso`，注意 codex 阈值 1e11 与其他 1e10 的漂移，统一为 1e10 并在注释说明）；API key strip（→ `require_api_key(params)` 统一 strip + missing 检查，接入 commandcode/kimi/minimax/tavily/deepseek）。
4. **status/color 收敛**：`_common.status_for_pct(pct)`，`status_for`/`color_for` 委托 pct 版本；删除 claude 本地 `status_for`（同名不同义）与 codex/glm 的内联阈值。
5. **清理**：`_common.py:11` 未使用的 `sys` 导入；claude/tavily/deepseek 未使用的 `utc_now_iso` 导入；codex:288 的 `-> ...` 标注笔误改 `-> date`。
6. **glm 小项**：`normalize_timestamp` 加上界（< 4e12）防 OverflowError（原 L6）；glm:69-70 两端点主机不一致（open.bigmodel.cn vs bigmodel.cn）仅向用户确认，不擅自改。
7. **kimi 文档项**：代码已有 Adagio 映射，文档补在批次 7。

每项提取遵守：先加 _common 实现与单测 → 逐插件接入 → 跑全量 unittest。不改变任何插件输出格式。

### 4.2 Core 去重（R5 Core 部分）

1. `PluginOutput.swift`：`expiryText`（70-82）与 `resetText`（234-246）逐行重复，提取 fileprivate `relativeDayText(date:now:language:)`；`compactExpiryText`（109-114）复用同一格式化组合。
2. `PluginConfiguration.swift:129-135` `localizedPlaceholder` 改为调用 `CodableHelpers` 的 `localizedOptionalValue`。
3. `CodableHelpers.swift:42-54`：`localizedOptionalValue`/`localizedValue` 从 Equatable 扩展移到独立 enum 命名空间（如 `LocalizedStrings`），调用点同步改。
4. `PluginDisplayNames.swift:19,28`：返回 trim 后的 `configuredName` 而非原始 `plugin.name`。
5. `ConfigStore.swift:25-31` `pluginsDirectoryURL` 双份实现：保留实例版，静态版标注仅默认配置便捷或移除（看调用点后定）。
6. `PluginExecutor.swift`：
   - M3：区分取消与超时——取消路径返回取消态而非"超时"文案；SIGTERM 后宽限期内进程退出时更新 finished 按正常退出处理。
   - L6：存活探测 `kill(pid, 0)` 补 `errno == EPERM` 视为存活。
   - L1：`~` 展开不一致——.py 走 env python3 传原始字符串不展开（会失败），非 .py 经 `URL(fileURLWithPath:)` 被 Foundation 静默展开。**方向（已修正）：统一为不展开**，符合 architecture.md §3 "不展开 ~" 的既有承诺。实现：非 .py 路径改用不展开 tilde 的方式构造执行 URL（如 `NSString` 的 `expandingTildeInPath` 逆检查，或对 `~` 前缀直接报错提示用户改用绝对路径）。文件选择器返回的永远是绝对路径，`~` 仅出现在手改 config.json 场景，明确失败优于静默跑错脚本。architecture.md §3 声明保持不变。
7. `AppRelauncher.swift`：run() 抛错时删临时脚本；relaunchCurrent 脚本 `rm -f "$0"` 移入 trap。
8. `UpdateChecker.swift`：下载完成后解压前补 `Task.checkCancellation()`（L4）。
9. `PluginStateStore.swift`：load 缓存负结果（已知不存在集合，save 后失效）（L5）。stateID 文件名碰撞（L7）不修（仅手改 config 才触发），在注释中说明即可。

### 4.3 App 去重与死代码（R5/R6 App 部分）

1. 删除 `DashboardView.swift:104-111` 死 `.toolbar`（popover 无 toolbar 上下文，且与 OverviewView 头部按钮重复）。
2. 删除 `OverviewView.swift:148-152`（QuitButton）与 `DashboardView.swift:145-150`（EmptyPluginsView）从未使用的 `language` 参数及调用点传值。
3. metadata 重载三处重复（Store.reloadMetadata、Store.updatePlugin 路径分支、PluginSettingsView.reloadDraftMetadata）收敛为单一实现（PluginMetadataParser 或 Store 提供 merge 帮助方法）；删除 saveDraft 中被 updatePlugin 覆盖的预解析。

### 4.4 批次 4 验证

```sh
swift test
python3 -m unittest discover -s Tests/PluginTests -q
python3 -m py_compile Resources/BundledPlugins/*.py
```

行为一致性验证：提取前后各插件对同一 fixture 的输出 JSON 逐字节对比（测试已覆盖大部分，抽样人工 diff）。

---

## 批次 5：脚本合并与校验

### 5.1 抽公共打包逻辑（R3）

- 新建 `scripts/_package_common.sh`，被 build.sh / release.sh source。包含：Info.plist 创建块（两脚本逐行相同的 15-31/14-30）、版本号写入、资源复制块、UBUpdateCheckURL 注入、codesign。
- 统一差异：codesign 统一带 `--verify --deep --strict`（当前仅 release.sh 有）；`UB_UPDATE_CHECK_URL` 环境变量覆盖统一支持（当前仅 build.sh 有，release.sh 写死——合并后 release.sh 也支持，默认不变）。
- build.sh 保留：pkill + open 启动；release.sh 保留：版本递增、notes、zip、version.json、上传。
- pkill 后加退出等待（`while pgrep -x UsageBoard; do sleep 0.2; done`，10 秒上限）。

### 5.2 校验与清理

- release.sh 版本参数加格式校验 `^[0-9]+(\.[0-9]+){1,2}$`，不合法退出（build.sh 的 VERSION 参数同样校验）。
- 删除两脚本中 "与 InTime 一致" 残留注释，只保留 build 号规则本身。
- CLAUDE.md 发布节补注：脚本默认 notes 格式（`git log - %s`）与约定不同，发布时必须显式传 notes。

### 5.3 批次 5 验证

```sh
bash -n scripts/*.sh
bash Tests/ScriptTests/test_release_version_timing.sh
bash scripts/build.sh   # 实测构建启动，确认 app 正常运行
```

---

## 批次 6：UI 一致性

### 6.1 菜单与快捷键（U1）

- AppMenu.swift：App 菜单加 "Settings…"（Cmd+,，action 调 `openSettings`）；新增标准 Window 菜单（Cmd+W close、Cmd+M minimize，target 为 nil 沿 responder chain）。注意 accessory 模式下菜单生效路径，用现有 AppMenuTests 模式补测试。

### 6.2 按钮与错误样式统一（U3 部分）

- 三处主按钮统一为一种胶囊样式（AboutView 检查更新、UpdatePrompt 立即更新/次要按钮），提取到 DesignSystem 的按钮 Style。
- AboutView 更新失败信息改红色，与 SettingsView 横幅、PluginGroupView 错误一致。

### 6.3 字号收敛（U3 字号部分，已收窄）

- 现状分布：12(13 处)、11(12)、13(10)、10(4)、11.5(3)、14(2)、12.5(2)、18(2)、15(2) 及零散，散落在 20+ View 中。
- **本批只做**：扩展 UB.Font，补 `body`(13)、`label`(12)、`caption`(11)、`caption2`(10)、`metricTitle`(11.5) 五个语义 token；迁移**语义最明显**的 3-5 处（如 TokenMetricView 的 11.5、倒计时相关 11、表单标签 12.5）。
- **不做**：不全面替换 50+ 处硬编码——逐屏视觉回归风险大于一致性收益。旧代码在下次触碰对应文件时渐进迁移，新代码一律用 token。图标装饰性尺寸（40/28/23/20）保留。

### 6.4 细节（U4/U5）

- `UsageItemRow.swift:10-15` 名称列加 `.help(item.name)`；resetText 列同理。
- `PluginSettingsCard.swift:74-82` 刷新间隔 hint 文案注明下限 5 秒（文案键补中英文）。

### 6.5 批次 6 验证

```sh
swift test --filter UsageBoardAppTests
bash scripts/build.sh   # 视觉验收：popover、设置三页、图表 hover、更新提示
```

视觉验收清单：Settings… 菜单与 Cmd+,、Cmd+W；未保存草稿关窗拦截；删除插件确认；错误横幅关闭；按钮样式一致；长名称悬浮提示；图表 hover 流畅度。

---

## 批次 7：文档修正

1. README.md:89 / README_EN.md:89：删"（版本 2）"，对齐为"三个插件各自维护缓存版本，升级旧缓存时重建近 30 天"。
2. README.md:46 / README_EN.md:46 / website/index.html:285："菜单栏胶囊"改为"面板顶部胶囊提示"（英文对应调整）。
3. website/index.html：hero 区与安装区统一为一种 brew 命令写法。
4. architecture.md：~~§5 Kimi 段补 Adagio（免费档）映射~~（已随 2026-09-25 Kimi 套餐更名任务完成，现为 Free 映射）；删除 §6 168-169 重复的切色阈值/徽章预设（遵守 154 行自己的约定，以 PluginAuthoringGuide 为准）。§3"不展开 ~"声明保持不变（批次 4.2.6 已修正为代码向文档对齐）。
5. README.md:210/228 等协议细节段：加"以 PluginAuthoringGuide.html 为准"指引，保留用户向摘要。
6. TASKS.md：记录本次 review 与执行进度。

验证：`git diff --check`、文档内链接与命令人工核对。

---

## 风险与回滚

- 批次 4 的去重改动面最大，每项提取独立提交，输出格式对比失败即回滚单项。
- 批次 5 脚本合并后用 build.sh 实测一次再视为完成；release.sh 不实际执行上传（仅 bash -n + ScriptTests）。
- 批次 1.4 的 glm 标签改动联动 App 侧过滤逻辑，两处必须同一批提交，避免中间态图表重复显示。
- 全部改动不触碰：插件对外 JSON 协议、更新流程行为、发布渠道配置、用户运行时数据目录结构。

## 执行顺序与提交策略

按批次 1→7 顺序执行；每批次 1-3 个 conventional commit（fix/perf/refactor/style/docs 分开），不 push。全部完成后统一更新 TASKS.md 并汇总验证结果。
