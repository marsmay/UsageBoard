# UsageBoard

**[English](README_EN.md)**

UsageBoard 是一个原生 macOS 菜单栏应用，用于聚合展示 API、模型服务、搜索服务、代理服务等各类用量配额。每个数据源都以插件形式存在，主程序负责定时执行插件、解析 stdout JSON，并以进度条展示用量。

## 功能特性

- 菜单栏常驻，点击图标打开快速预览。
- 支持分组展示和标签页展示。
- 支持手动刷新、定时刷新、单卡片刷新、退出按钮。退出时等待配置保存；超过 5 秒仍未完成会取消本次退出，待保存完成后可再次退出。
- 系统休眠时暂停定时刷新，唤醒后继续调度。
- 插件化用量查询，插件可独立配置刷新间隔和参数。
- 插件图标支持本地资源和远程图片缓存；内置图标离线可用，随明暗主题切换。
- 订阅级别徽章显示（按套餐或插件配置着色）。
- 插件设置界面从脚本元数据自动生成参数表单，支持分段选择控件和目录选择器。
- 设置输入框支持标准编辑快捷键：撤销/重做（⌘Z / ⇧⌘Z）、剪切/拷贝/粘贴（⌘X / ⌘C / ⌘V）和全选（⌘A）。
- 新增插件默认不启用，启用前会检查必填参数。
- 插件数据按 `stateID` 缓存到磁盘，启动后可展示上次成功数据。
- 每次启动检查并安装内置插件链接；在设置中添加需要的插件后再启用。
- 设置页支持浅色 / 深色 / 跟随系统主题（即时生效）、开机启动、新版本提示（默认开启，可在通用设置关闭）、插件拖拽排序、插件帮助文档、检查更新和在线更新。后台每 6 小时自动检查更新；有可用更新且开启新版本提示时，菜单栏弹层显示新版本胶囊，点击胶囊或在关于页检查更新可打开提示面板。非模态更新面板随检查结果刷新版本和说明，无可用更新时关闭；检查期间暂停操作，确认安装的版本必须与面板一致。面板按钮显示下载、安装或失败状态，详细信息可在关于页查看。
- 用量展示支持百分比或数字占比，支持重置时间、进度条颜色，以及可切换折线图/堆叠直方图的 token 统计图。
- 插件可用 `{"error": "错误信息"}` 返回失败原因，错误会直接显示在卡片内容区。
- 支持中英文切换，App UI 和插件元数据均可按语言展示。

## 截图

<table>
  <tr>
    <td><img src="Screenshots/tabs-claude.jpg" alt="Claude 标签页" width="360" /></td>
    <td><img src="Screenshots/tabs-minimax.jpg" alt="MiniMax 标签页" width="360" /></td>
  </tr>
  <tr>
    <td align="center">Claude 标签页</td>
    <td align="center">MiniMax 标签页</td>
  </tr>
  <tr>
    <td><img src="Screenshots/grouped.jpg" alt="分组展示" width="360" /></td>
    <td><img src="Screenshots/grouped-glm.jpg" alt="展开统计图" width="360" /></td>
  </tr>
  <tr>
    <td align="center">分组展示</td>
    <td align="center">分组展开统计 GLM</td>
  </tr>
  <tr>
    <td><img src="Screenshots/grouped-codex.jpg" alt="Codex 统计图" width="360" /></td>
    <td><img src="Screenshots/settings.jpg" alt="插件设置" width="360" /></td>
  </tr>
  <tr>
    <td align="center">分组展开统计 Codex</td>
    <td align="center">插件设置</td>
  </tr>
</table>

## 内置插件

| 插件 | 脚本 | 用途 |
| --- | --- | --- |
| 智谱 | `glm-usage-plugin.py` | 查询智谱 / ZAI Coding Plan 用量和统计 |
| Claude | `claude-usage-plugin.py` | 查询 Claude 订阅用量和统计 |
| Codex | `codex-usage-plugin.py` | 查询 OpenAI Codex CLI 用量和统计 |
| MiniMax | `minimax-usage-plugin.py` | 查询 MiniMax Coding Plan 用量 |
| DeepSeek | `deepseek-usage-plugin.py` | 查询 DeepSeek 账户余额 |
| Kimi | `kimi-usage-plugin.py` | 查询 Kimi Code 用量 |
| Tavily | `tavily-usage-plugin.py` | 查询 Tavily Search 月度用量 |
| Command Code | `commandcode-usage-plugin.py` | 查询订阅的 5 小时、周和月度用量 |

内置插件源文件位于 [Resources/BundledPlugins](Resources/BundledPlugins)，其中 `_common.py` 是插件共享的公共模块，提供参数解析、翻译、HTTP 错误处理等工具函数。打包后它们会位于 app 包的 `Contents/Resources/Plugins/`。

内置插件图标位于 [Resources/icons](Resources/icons)，包含 light/dark 两套 PNG 图标，随 app 打包到 `Contents/Resources/icons/`，离线可用并随界面主题切换。配置中的 `icon` 使用资源相对路径（如 `icons/light/kimi.png`），不依赖插件符号链接或开发机器的绝对路径。

Command Code：在插件设置中填写 `API_KEY`；手动运行脚本也可使用环境变量 `COMMAND_API_KEY`（设置参数优先）。通过未公开稳定契约的 `/alpha/billing/credits` 查询额度，`/alpha/billing/subscriptions` 补充套餐和月度重置时间。月上限暂按 **周上限 × 2** 估算，月已用为 `max(月上限 − monthlyCredits, 0)`，不包含充值余额；三项以百分比显示，名称为“5 小时用量”“周用量”“月用量”。缺少周窗口或周上限不大于零时不显示月度估算；订阅查询失败仍显示额度，但省略套餐和月度重置时间。应用不会自动读取 shell 配置，请在设置中填写密钥。套餐徽标 GO / GOAT / MAX 分别使用青色 / 蓝色 / 橙色。

## 运行时目录

UsageBoard 默认使用：

```text
~/Library/Application Support/UsageBoard/
```

目录内容：

- `config.json`：主配置文件，包含插件参数，以仅当前用户可读写的权限（0600）保存。
- `plugins/`：用户插件目录。添加插件时文件选择器默认打开这里。
- `states/`：主程序保存的插件成功快照缓存。
- `plugin-caches/`：智谱插件默认统计缓存，按 API key 的哈希前缀区分。Claude/Codex 的增量统计缓存另存于各自 `DATA_DIR/.usageboard-chart-cache.json`。

当前实现会在启动时向 `plugins/` 目录创建内置插件的同名符号链接（以 `_` 开头的内部模块文件除外），来源是 app 包内的 `Contents/Resources/Plugins/`，开发运行时则 fallback 到项目的 `Resources/BundledPlugins/`。现有同名普通文件会保留，已有符号链接会随 app 位置更新；如需自定义内置插件，可将其链接替换为独立脚本文件。

`icon` 也兼容 HTTP(S) URL、绝对文件路径和 `file://` URL。相对路径以 app 的 `Contents/Resources/` 为根，开发运行时以当前工作目录的 `Resources/` 为根；`icons/light/` 路径在深色主题下优先加载同名 `icons/dark/` 文件，缺失时回退 light，加载失败时显示名称首字母占位。

远程图标限制为 2 MiB、10 秒无进展超时和 20 秒总时限；超量或失败保留占位图。这不是解码后像素内存上限。

## 配置文件

主配置 JSON 当前结构：

```json
{
  "schemaVersion": 1,
  "language": "zh-Hans",
  "theme": "system",
  "overviewDisplayMode": "tabs",
  "chartMode": "line",
  "launchAtLogin": false,
  "plugins": [
    {
      "stateID": "stable-cache-id",
      "name": "Example",
      "enabled": false,
      "executablePath": "/absolute/path/to/example-plugin.py",
      "refreshIntervalSeconds": 300,
      "metadata": {
        "name": "Example",
        "description": "示例插件",
        "description@zh-Hans": "示例插件",
        "description@en": "Example plugin",
        "parameters": [
          {
            "name": "API_KEY",
            "label": "Api Key",
            "label@zh-Hans": "Api Key",
            "label@en": "API Key",
            "type": "secret",
            "required": true,
            "placeholder": "Service API Key"
          },
          {
            "name": "STAT_PERIOD",
            "label": "统计周期",
            "label@zh-Hans": "统计周期",
            "label@en": "Stats Period",
            "type": "choice",
            "required": true,
            "defaultValue": "7d",
            "options": [
              {"label": "7 天", "label@zh-Hans": "7 天", "label@en": "7 days", "value": "7d"},
              {"label": "15 天", "label@zh-Hans": "15 天", "label@en": "15 days", "value": "15d"},
              {"label": "30 天", "label@zh-Hans": "30 天", "label@en": "30 days", "value": "30d"}
            ]
          }
        ]
      },
      "parameterValues": {
        "API_KEY": "",
        "STAT_PERIOD": "7d"
      }
    }
  ]
}
```

说明：

- `overviewDisplayMode` 支持 `grouped` 和 `tabs`。
- `chartMode` 支持 `line` 和 `bar`，旧配置缺失该字段时回退到 `line`。
- `theme` 支持 `light`、`dark` 和 `system`，默认跟随系统；在通用设置中切换后立即作用于设置窗口和菜单面板，并持久保存。旧配置缺失此字段时按 `system` 处理。
- `language` 支持 `zh-Hans` 和 `en`，修改后重启生效。
- `launchAtLogin` 控制开机启动。
- `plugins[].stateID` 是持久化缓存 ID；通过设置修改脚本路径、参数或元数据后会重新生成。
- `plugins[].executablePath` 使用实际文件路径，不支持 `~` 或 shell 表达式展开；建议通过文件选择器填写。
- `plugins[].enabled` 为 `false` 时不执行插件。
- `plugins[].metadata` 通常由插件脚本头部注释块解析生成。
- `plugins[].parameterValues` 保存设置界面填写的插件参数。

## 插件开发

插件推荐使用 Python 脚本。主程序执行 `.py` 插件时使用：

```text
/usr/bin/env python3 /path/to/plugin.py --usageboard-param KEY=value --usageboard-param USAGEBOARD_LANGUAGE=zh-Hans
```

插件必须向 stdout 输出 UsageBoard 可解析的 JSON。stdout 上限为 8 MiB，stderr 最多保留 64 KiB；默认超时 15 秒；超时、取消或 stdout 超限会终止插件进程。Python 执行禁用字节码缓存，避免修改 app 包。stderr 可用于调试；退出码非 0、超时或 stdout 非法 JSON 都会显示为插件错误。插件也可以向 stdout 输出 `{"error": "错误信息"}` 并以退出码 0 结束以报告失败，UsageBoard 会把该错误展示在插件卡片内容区。

更完整的说明见 [插件编写说明](Resources/PluginAuthoringGuide.html)。

### 参数元数据

在脚本前 80 行内放入完整的 `UsageBoardPlugin` JSON 注释块（包括结束标记），UsageBoard 会读取它并生成设置表单：

```python
#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "name": "Example",
#   "icon": "https://example.com/icon.png",
#   "description": "示例插件",
#   "description@zh-Hans": "示例插件",
#   "description@en": "Example plugin",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "Api Key",
#       "label@zh-Hans": "Api Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Service API Key"
#     },
#     {
#       "name": "STAT_PERIOD",
#       "label": "统计周期",
#       "label@zh-Hans": "统计周期",
#       "label@en": "Stats Period",
#       "type": "choice",
#       "required": true,
#       "defaultValue": "7d",
#       "options": [
#         {"label": "7 天", "label@zh-Hans": "7 天", "label@en": "7 days", "value": "7d"},
#         {"label": "15 天", "label@zh-Hans": "15 天", "label@en": "15 days", "value": "15d"},
#         {"label": "30 天", "label@zh-Hans": "30 天", "label@en": "30 days", "value": "30d"}
#       ]
#     }
#   ]
# }
# /UsageBoardPlugin
```

涉及展示的插件元数据字段支持同级多语言字段，例如 `name@zh-Hans`、`name@en`、`description@zh-Hans`、`description@en`、`label@zh-Hans`、`label@en`、`placeholder@zh-Hans`、`placeholder@en`。当前语言对应字段缺失或为空时，UsageBoard 会回退到不带语言后缀的基础字段。

支持的参数类型：

- `string`
- `secret`
- `integer`
- `boolean`
- `choice`
- `directory`
- `file`

`choice` 参数在设置页优先显示为等宽分段控件，选中项使用系统强调色，宽度不足时回退菜单；`directory` 参数显示为路径输入框和文件夹选择器；`file` 参数显示为路径输入框和文件选择器。

内置插件读取参数示例（独立用户插件需在脚本同目录提供 `_common.py`，或参考插件编写说明中的独立实现）：

```python
import sys
from _common import parse_usageboard_params, app_language, make_translator, success, failure

def main():
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    translate = make_translator({
        "my_plugin_name": {"zh-Hans": "我的插件", "en": "My Plugin"},
    })

    api_key = params.get("API_KEY")
    if not api_key:
        return failure(translate(language, "missing_api_key"))

    items = []  # 在此调用 API 并构造实际用量项目
    return success(items)

if __name__ == "__main__":
    sys.exit(main())
```

`_common.py` 提供了参数解析（`parse_usageboard_params`）、语言检测（`app_language`）、翻译工厂（`make_translator`）、输出函数（`success`/`failure`）、颜色/状态计算（`color_for`/`status_for`/`numeric`）以及统一的 HTTP 错误处理（`handle_http_error`/`handle_url_error`）。新插件应直接引用这些工具，不要重复实现。完整的公共函数列表见 `_common.py` 源码。

UsageBoard 会额外传入当前 app 语言参数：`--usageboard-param USAGEBOARD_LANGUAGE=zh-Hans` 或 `--usageboard-param USAGEBOARD_LANGUAGE=en`。脚本应读取这个保留参数，并直接返回对应语言的展示文本。

插件默认执行超时 15 秒，stdout 上限 8 MiB。运行结束（含父进程正常退出）后，受确认插件进程组中的后代会收到 SIGTERM，并获得最多 1 秒清理时间，仍存活时再收到 SIGKILL。插件不能依赖后代在本次运行后继续执行。

### 返回数据格式

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
  "chart": {
    "kind": "line",
    "period": "30d",
    "bucketUnit": "day",
    "buckets": [
      {
        "id": "2026-05-01",
        "label": "05-01",
        "segments": [
          {"model": "glm-4.5", "tokens": 1200},
          {"model": "glm-4.6", "tokens": 800}
        ]
      }
    ],
    "message": null
  }
}
```

失败时也可以返回：

```json
{
  "error": "API Key 无效，请检查配置"
}
```

主要字段摘要（完整协议和字段细节见 [插件编写说明](Resources/PluginAuthoringGuide.html)）：

- `updatedAt` 与 `items[]`：必填；`items[]` 的 `used`/`limit`/`displayStyle`（`percent` 或 `ratio`）/`resetAt`/`status`/`color` 控制用量行展示，进度条颜色未指定时按进度切色（<60% 蓝、60%–<80% 黄、80%–<100% 橙、100% 红）。
- `badge` / `badgeColor`：可选卡片标题徽章；`badgeColor` 支持 `blue`、`orange`、`gray`（或 `grey`）、`indigo`、`purple`、`teal`、`green`、`red`、`yellow`，缺省时按 `badge` 文字匹配预设档位（如 PRO/MAX）。
- `credits`：可选配额重置卡数组（如 Codex 的 rate-limit reset），只应包含当前可用的卡，查询失败时省略该字段，不影响其他数据。
- `chart`：可选 token 统计图，使用 `kind: "line"` 的数据结构按时间桶给出模型分段；实际折线/直方图展示由全局 `chartMode` 决定，数据为空时可提供 `chart.message` 提示文案。
- `error`：可选顶层错误信息；存在且非空时，该插件本次运行被视为失败，错误文本显示在卡片内容区。

GLM 与 Codex 图表缓存版本 2 会在升级旧缓存时一次性重建近 30 天数据，然后恢复增量更新。Codex 整行跳过无效 UTF-8 数据并继续读取后续有效事件；Claude 空套餐名回退配置套餐再到 pro；Kimi 省略时区不明的重置时间；MiniMax 对显式 null 或非对象的 `base_resp` 返回解析失败，缺失字段维持原有兼容行为。

内置智谱、Claude 和 Codex 插件提供 `STAT_PERIOD` 参数，支持 `none`（无）、`7d`、`15d`、`30d`，选择无则关闭本地统计。智谱插件统一使用国内站 API 查询，兼容智谱和 ZAI 的 Coding Plan Key。Claude 插件通过 OAuth API 获取订阅用量，`PLAN` 参数支持 `none`（无）选项，选择后跳过 API 调用仅返回本地 JSONL 统计数据；订阅计划和统计周期均选无时插件不再返回有效数据，对应卡片显示"暂无用量数据"占位，失败时显示错误；本地 token 统计直接按 input、output、cache creation 和 cache read 的实际消耗总和计算，还支持 `CLAUDE_ONLY` 开关过滤第三方模型，并可通过 `DATA_DIR` 指定 `~/.claude` 数据目录。Codex 插件通过独立的 `AUTH_FILE` 参数读取认证文件（默认 `~/.codex/auth.json`），通过 `DATA_DIR` 指定会话统计目录（默认 `~/.codex`）。修改统计目录不会自动改变认证文件路径。Claude 和 Codex 插件使用增量缓存策略，缓存存放在数据目录中；每次运行重扫最后一个已缓存日及之后的数据。Claude、Codex 与智谱共享原子缓存读写，写入失败时保留之前的完整缓存。DeepSeek 插件提供 `LIMIT` 参数用于设置余额展示上限，并按余额占上限比例显示进度条颜色。Codex 插件还会列出账号当前可用的额度重置卡，默认以单行显示数量和最近到期信息，点击展开后以每排两张的卡片查看到期时间和剩余天数，查询最多额外等待 2 秒，并受插件整体剩余时间预算限制；超时或失败时省略重置卡，不影响用量显示。Kimi 插件查询 Kimi Code 的 5 小时滚动窗口和周用量。可在“订阅计划”中手动选择 Andante、Moderato、Allegretto、Allegro，徽标分别为灰色、靛蓝、蓝色、橙色；设置默认选中 Andante，请按实际订阅修改。有效的 `PLAN` 配置优先于接口会员等级；未配置或值无效时保留旧接口的等级映射，无法确认则省略徽标。当前 API Key 用量响应可能不再包含 `user.membership.level`，因此建议手动选择套餐。

## 安装

通过 Homebrew 安装：

```bash
brew tap marsmay/usageboard
brew install --cask usageboard
```

首次打开时，macOS 可能提示"无法验证开发者"。在"系统设置 → 隐私与安全性"中点击"仍要打开"，或在终端执行：

```bash
xattr -cr /Applications/UsageBoard.app
```

## 系统要求

运行：

- macOS 13.0 或更高版本
- 系统可用 `python3`，用于执行 Python 插件

开发：

- Xcode
- Swift 6.3 toolchain

## 构建与测试

Debug 构建：

```bash
swift build
```

运行测试：

```bash
swift test
python3 -m pytest Tests/PluginTests -q
```

Python 测试需要 pytest，使用临时数据和网络替身；不需要真实账号凭据。

Release 构建：

```bash
swift build -c release
```

本地构建、签名并启动 `dist/UsageBoard.app`：

```bash
bash scripts/build.sh
```

`scripts/build.sh` 会停止正在运行的 UsageBoard，构建 release，复制二进制、内置插件、帮助文档和图标到 `dist/UsageBoard.app`，通过 PlistBuddy 向 Info.plist 注入更新检查 URL，执行 ad-hoc 签名，然后启动 app。可通过 `UB_UPDATE_CHECK_URL` 环境变量自定义更新检查地址。

## 发布

发布脚本会直接上传服务器；仅在确定发布时运行。脚本默认递增本地 app bundle 的 patch 版本，不从 release tag 推算；正式发布建议核对最近 tag 并显式传入版本。

```bash
bash scripts/release.sh
```

指定版本及更新说明（替换下列占位符，更新说明可包含真实换行）：

```text
bash scripts/release.sh <version> "<release notes>"
```

发布脚本会：

1. 从 `dist/UsageBoard.app/Contents/Info.plist` 读取当前版本。
2. 使用指定版本，或将该本地版本的 patch 加一（bundle 不存在时从 0.1.0 初始化，因此首次自动发布为 0.1.1）。
3. 自动从上个 release tag 到 HEAD 的提交生成更新说明（也可通过第二个参数手动传入）。
4. 构建 release，成功后再写入目标版本及 build 号；构建失败保留已有 bundle 版本和二进制。
5. 复制二进制、内置插件、帮助文档和图标。
6. 通过 PlistBuddy 向 Info.plist 注入更新检查 URL。
7. 重新签名并验证 app。
8. 生成 `UsageBoard-<version>.zip`。
9. 生成 `version.json`。
10. 上传到脚本中配置的服务器路径。
11. 清理远端旧 zip，保留最近三个。

脚本不会创建或推送 Git tag、发布 GitHub Release、更新 Homebrew cask；完整发布需另外完成这些步骤，并核对本地、服务器、GitHub 下载包和 cask 的版本及 SHA-256 一致。发布前先停止旧 UsageBoard 实例；与 build.sh 不同，release.sh 不负责停止或启动应用。

发布产物：

- `dist/UsageBoard-<version>.zip`
- `dist/version.json`

更新 ZIP 下载限制为 64 MiB、60 秒无进展超时和 300 秒总时限，失败或取消会清理临时 ZIP。该限制不包含解压配额或发布者认证，现有 ad-hoc 签名流程保持不变。

## 项目结构

```text
Sources/
  UsageBoardCore/       配置、模型、插件执行、缓存、更新等核心逻辑
  UsageBoardApp/        SwiftUI + AppKit macOS app
Tests/
  UsageBoardTests/      Core XCTest
  UsageBoardAppTests/   Store、主题、语言、图标与布局 XCTest
  PluginTests/          Python 插件测试
  ScriptTests/          隔离的发布脚本测试
Resources/
  BundledPlugins/       内置 Python 插件
  icons/                插件 light/dark 本地图标
  IconSources/          保留的图标源素材
  PluginAuthoringGuide.html
  UsageBoard.icns
scripts/
  build.sh              本地构建、签名、启动
  release.sh            服务器发布脚本
  prepare_codex_icon.py  从保留源图生成 Codex 图标（需要 Pillow）
dist/
  UsageBoard.app        本地测试 app bundle
```

开发分层、数据流与验证规范见 [架构说明](docs/architecture.md)。

## 许可证

[MIT](LICENSE)
