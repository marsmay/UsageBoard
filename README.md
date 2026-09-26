# UsageBoard

**[English](README_EN.md)** · [项目主页](https://usageboard.may.ltd/)

UsageBoard 是原生 macOS 菜单栏应用，以插件方式聚合 API、模型、搜索等服务的配额、余额和本地用量统计。主程序定时执行插件、解析 stdout JSON，用进度条和图表展示用量。

## 截图

<table>
  <tr>
    <td><img src="Screenshots/tabs-claude.jpg" alt="Claude 标签页" width="360" /></td>
    <td><img src="Screenshots/tabs-codex.jpg" alt="Codex 标签页" width="360" /></td>
  </tr>
  <tr>
    <td align="center">Claude 标签页</td>
    <td align="center">Codex 标签页</td>
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

## 功能特性

- 菜单栏常驻，点击图标打开面板；分组 / 标签页两种布局，卡片可拖拽排序。
- 进度条按用量自动切色；支持百分比或数字占比、重置时间和订阅套餐徽章。
- Token 统计图支持折线 / 堆叠直方图切换。
- 手动刷新、定时刷新（每个插件独立间隔）和单卡片刷新；系统休眠时暂停定时刷新，唤醒后继续。
- 插件数据按 `stateID` 缓存到磁盘，启动即展示上次成功数据；插件返回 `{"error": "…"}` 时错误直接显示在卡片内容区。
- 插件参数表单由脚本元数据自动生成，支持分段控件、目录和文件选择器；新插件默认不启用，启用前校验必填参数；切换设置栏目保留插件草稿，关闭设置窗口时询问保存、放弃或取消，移除插件需确认。
- 浅色 / 深色 / 跟随系统主题，切换即时生效；内置插件图标离线可用并随主题切换。
- 中英文界面；设置输入框支持标准编辑快捷键（⌘Z / ⇧⌘Z / ⌘X / ⌘C / ⌘V / ⌘A）。
- 支持开机启动；后台每 6 小时检查更新，新版本在弹层顶部以胶囊提示，在非模态面板中下载安装。
- 退出时等待配置保存，超过 5 秒取消本次退出，保存完成后可再次退出。

## 安装

需要 macOS 13.0 或更高版本，以及系统可用的 `python3`（用于执行插件）。

```bash
brew tap marsmay/usageboard
brew install --cask usageboard
```

首次打开如提示"无法验证开发者"，在"系统设置 → 隐私与安全性"中点击"仍要打开"，或执行：

```bash
xattr -cr /Applications/UsageBoard.app
```

安装后在"设置 → 插件"中添加需要的插件并启用。

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

插件源码见 [Resources/BundledPlugins](Resources/BundledPlugins)，共享公共模块 `_common.py`，打包后位于 `Contents/Resources/Plugins/`。内置图标见 [Resources/icons](Resources/icons)，light/dark 两套离线可用并随主题切换，配置中的 `icon` 使用资源相对路径（如 `icons/light/kimi.png`）。

各插件说明：

- **智谱**：使用国内站 API，兼容智谱和 ZAI 的 Coding Plan Key；`STAT_PERIOD` 支持 `none` / `7d` / `15d` / `30d`，选 `none` 关闭本地统计。
- **Claude**：通过 OAuth API 查询订阅用量；`PLAN` 选 `none` 时跳过 API 仅返回本地 JSONL 统计，与统计周期均选 `none` 时卡片显示"暂无用量数据"；本地 token 统计按 input、output、cache creation、cache read 实际消耗求和；`CLAUDE_ONLY` 过滤第三方模型；`DATA_DIR` 指定数据目录（默认 `~/.claude`）；`STAT_PERIOD` 同上。
- **Codex**：`AUTH_FILE`（默认 `~/.codex/auth.json`）与 `DATA_DIR`（默认 `~/.codex`）相互独立，修改统计目录不影响认证路径；列出账号当前可用的额度重置卡，查询失败不影响用量显示；`STAT_PERIOD` 同上。
- **DeepSeek**：`LIMIT` 设置余额展示上限，进度条按余额占上限比例着色。
- **Kimi**：查询 5 小时滚动窗口和周用量；订阅计划在设置中手动选择 Go / Plus / Pro / Max（徽标灰 / 靛蓝 / 蓝 / 橙，默认 Go），接口不再提供会员等级，未选择或值无效时省略徽标。

实现细节：GLM、Codex 与 Claude 的图表缓存各自维护版本号，升级旧缓存时一次性重建近 30 天数据，随后恢复增量更新；Claude、Codex 与智谱统计缓存原子写入，失败保留旧缓存；Codex 按行解码 UTF-8，损坏行整行跳过；Claude 空套餐名回退配置值再到 pro；Kimi 省略时区不明的重置时间；MiniMax 对显式 null 或非对象 `base_resp` 返回解析失败，缺失字段保持兼容。


Claude classifier 统计无需接收服务：使用 `AUTOMODE_DECISION_LOG=1 claude` 启动 Claude Code，或在用户级 `~/.claude/settings.json` 的 `env` 中加入 `"AUTOMODE_DECISION_LOG": "1"` 后启动新会话。Claude 会向首次写日志时的工作目录追加 `.automode_decisions.jsonl`；插件从 `DATA_DIR/projects` 会话记录的 `cwd` 自动发现这些文件，读取本地 classifier 的实际四类 token，并合并到同名模型，不增加图表后缀。无需单独指定日志目录；依赖正常保存的会话记录，`--no-session-persistence` 会话的目录可能无法自动发现。不要提交决策日志，可加入项目的本地 Git 排除规则。

该开关已在 Claude Code 2.1.280 实测，但属于内部接口，升级后可能变化。只能统计启用后的记录；服务端 classifier、缺少实际 usage 的记录不追加，避免与主请求重复计数。两阶段及部分重试已包含在决策总量中，不再重复相加；模型回退时总量可能归到最终模型。日志无请求 ID，不按相同内容去重，只对指向同一文件的路径去重；不要在扫描范围保留日志副本。读取时跳过损坏行及尚未追加完成的末行。classifier 每次独立汇总近 30 天，删除日志后对应统计会消失。

## 插件开发

推荐使用 Python 脚本。主程序执行 `.py` 插件时使用：

```text
/usr/bin/env python3 /path/to/plugin.py --usageboard-param KEY=value --usageboard-param USAGEBOARD_LANGUAGE=zh-Hans
```

约束与行为：

- 默认超时 15 秒；stdout 上限 8 MiB，stderr 保留前 64 KiB；超时、取消或超限终止插件进程组（先 SIGTERM，最多 1 秒清理后 SIGKILL），插件不能依赖后代在运行结束后存活。
- 禁用 Python 字节码缓存，避免修改 app 包。
- 退出码非 0、超时或 stdout 非法 JSON 显示为插件错误；也可以退出码 0 输出 `{"error": "错误信息"}` 报告失败，错误显示在卡片内容区。
- `USAGEBOARD_LANGUAGE` 为保留参数（`zh-Hans` / `en`），插件应按它直接返回对应语言的展示文本。

完整协议见随 app 打包的 [插件编写说明](Resources/PluginAuthoringGuide.html)。

### 参数元数据

在脚本前 80 行内放入完整的 `UsageBoardPlugin` JSON 注释块（含结束标记），UsageBoard 据此生成设置表单：

```python
#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "name": "Example",
#   "icon": "https://example.com/icon.png",
#   "description": "示例插件",
#   "description@en": "Example plugin",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Service API Key"
#     }
#   ]
# }
# /UsageBoardPlugin
```

- 参数类型：`string`、`secret`、`integer`、`boolean`、`choice`、`directory`、`file`。`choice` 优先显示为分段控件（宽度不足回退菜单）；`directory` / `file` 显示路径输入框和对应选择器。
- 展示字段支持 `@zh-Hans` / `@en` 多语言后缀（如 `name@en`、`label@zh-Hans`、`placeholder@en`），当前语言对应字段缺失或为空时回退基础字段。

### 读取参数

内置插件复用 `_common.py`（独立用户插件需在脚本同目录提供该模块，或参考编写说明中的独立实现）：

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

`_common.py` 提供参数解析（`parse_usageboard_params`）、语言检测（`app_language`）、翻译工厂（`make_translator`）、输出函数（`success` / `failure`）、颜色与状态计算（`color_for` / `status_for` / `numeric`）、不跟随重定向的 JSON 请求（`fetch_json`）、统一错误分类（`run_query` / `handle_http_error` / `handle_url_error`）与 API Key 清洗（`require_api_key`），完整函数列表见源码。

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

失败时：

```json
{ "error": "API Key 无效，请检查配置" }
```

字段摘要（完整字段细节见插件编写说明）：

- `updatedAt` 与 `items[]`：必填；`used` / `limit` / `displayStyle`（`percent` 或 `ratio`）/ `resetAt` / `status` / `color` 控制用量行展示，未指定颜色时按进度切色（<60% 蓝、60%–<80% 黄、80%–<100% 橙、100% 红）。
- `badge` / `badgeColor`：可选标题徽章；`badgeColor` 支持 `blue`、`orange`、`gray`（或 `grey`）、`indigo`、`purple`、`teal`、`green`、`red`、`yellow`，缺省时按徽章文字匹配预设档位。
- `credits`：可选配额重置卡数组，只应包含当前可用的卡，查询失败时省略该字段。
- `chart`：可选 token 统计图，`kind: "line"` 按时间桶给出模型分段；折线 / 直方图展示由全局 `chartMode` 决定，数据为空时可用 `chart.message` 提示。
- `error`：可选顶层错误；存在且非空时本次运行视为失败，错误文本显示在卡片内容区。

## 运行时目录

```text
~/Library/Application Support/UsageBoard/
```

- `config.json`：主配置文件（含插件参数），以仅当前用户可读写权限（0600）保存。
- `plugins/`：用户插件目录，添加插件时文件选择器默认打开这里。
- `states/`：主程序保存的插件成功快照缓存。
- `plugin-caches/`：智谱统计缓存，按 API key 的哈希前缀区分；Claude / Codex 的增量统计缓存另存于各自 `DATA_DIR/.usageboard-chart-cache.json`。

启动时向 `plugins/` 创建内置插件的同名符号链接（`_` 开头的内部模块除外），来源为 app 包内 `Contents/Resources/Plugins/`（开发时回退项目 `Resources/BundledPlugins/`）；同名普通文件保留，已有链接随 app 位置更新。将链接替换为独立脚本即可自定义内置插件。

`icon` 兼容 HTTP(S) URL、绝对路径、`file://` URL 和资源相对路径；相对路径以 app 的 `Contents/Resources/` 为根（开发时以当前目录 `Resources/` 为根），`icons/light/` 路径在深色主题下优先加载同名 `icons/dark/` 文件，缺失回退 light，加载失败显示名称首字母占位。远程图标限制为 2 MiB、10 秒无进展超时和 20 秒总时限（仅传输字节，不含解码后像素内存），超量或失败保留占位图。

## 配置文件

主配置 JSON 结构：

```json
{
  "schemaVersion": 1,
  "language": "zh-Hans",
  "theme": "system",
  "overviewDisplayMode": "tabs",
  "chartMode": "line",
  "launchAtLogin": false,
  "showUpdateBadge": true,
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
        "parameters": [
          {
            "name": "API_KEY",
            "label": "API Key",
            "type": "secret",
            "required": true
          }
        ]
      },
      "parameterValues": {
        "API_KEY": ""
      }
    }
  ]
}
```

- `overviewDisplayMode`：`grouped` / `tabs`；`chartMode`：`line` / `bar`（旧配置缺失回退 `line`）；`theme`：`light` / `dark` / `system`（缺失按 `system`），切换立即生效并持久保存。
- `language`：`zh-Hans` / `en`，重启后生效；`launchAtLogin` 控制开机启动；`showUpdateBadge` 控制主界面是否显示新版本胶囊提示（缺失按 `true`）。
- `plugins[].stateID` 是持久化缓存 ID；修改脚本路径、参数或 metadata 后重新生成。
- `plugins[].executablePath` 使用实际文件路径，不展开 `~` 或 shell 表达式，建议通过文件选择器填写。
- `plugins[].enabled` 为 `false` 时不执行插件；`plugins[].metadata` 通常由脚本头部注释块解析生成；`plugins[].parameterValues` 保存设置页填写的参数。

## 构建与测试

开发需要 Xcode 和 Swift 6.3 toolchain：

```bash
swift build                                 # Debug 构建
swift test                                  # Swift 测试
python3 -m unittest discover -s Tests/PluginTests -q      # 插件测试（使用临时数据与网络替身，不需要真实凭据）
swift build -c release                      # Release 构建
bash scripts/build.sh                       # 本地构建、签名并启动 dist/UsageBoard.app
```

`scripts/build.sh` 会停止运行中的 UsageBoard，构建 release，复制二进制、内置插件、帮助文档和图标到 `dist/UsageBoard.app`，注入更新检查 URL（可用 `UB_UPDATE_CHECK_URL` 覆盖），ad-hoc 签名后启动。

## 发布

发布脚本直接上传服务器，仅在确定发布时运行。建议核对最近 tag 并显式传入版本（省略时递增本地 bundle 的 patch）：

```text
bash scripts/release.sh <version> "<release notes>"
```

脚本完成 release 构建、写入版本与 build 号、复制资源、签名、生成 `UsageBoard-<version>.zip` 和 `version.json`（含 `updatedAt`、`latestVersion`、`latestBuild`、`downloadURL`、`notes`；更新说明缺省时取最近 tag 到 HEAD 的提交），上传服务器并清理远端旧 zip（保留最近三个）。

脚本不创建或推送 Git tag、不发布 GitHub Release、不更新 Homebrew cask；完整发布需另行完成这些步骤，并核对各渠道版本与 zip SHA-256 一致。发布前先停止旧 UsageBoard 实例；与 build.sh 不同，release.sh 不负责停止或启动应用。

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
  PluginAuthoringGuide.html
  UsageBoard.icns
scripts/
  build.sh              本地构建、签名、启动
  release.sh            服务器发布脚本
  _package_common.sh    build/release 共用打包逻辑
website/                项目主页静态文件
dist/
  UsageBoard.app        本地测试 app bundle
```

开发分层、数据流与验证规范见 [架构说明](docs/architecture.md)。

## 许可证

[MIT](LICENSE)
