# UsageBoard

**[中文](README.md)**

UsageBoard is a native macOS menu bar app that aggregates and displays usage quotas for APIs, model services, search services, proxy services, and more. Each data source is a plugin; the app periodically executes plugins, parses their stdout JSON, and renders usage as progress bars.

## Features

- Resides in the menu bar; click the icon to open a quick preview.
- Supports grouped and tabbed display modes.
- Supports manual refresh, scheduled refresh, per-card refresh, and a quit button.
- Scheduled refresh pauses during system sleep and resumes on wake.
- Plugin-based usage queries with per-plugin configurable refresh intervals and parameters.
- Plugin icons support local resources and cached remote images; bundled icons work offline and follow the light/dark theme.
- Subscription badges colored by plan or plugin configuration.
- Plugin settings UI auto-generated from script metadata, including segmented controls, directory pickers, and file pickers.
- New plugins are disabled by default; required parameters are checked before enabling.
- Plugin data cached to disk by `stateID`; last successful data shown on launch.
- Bundled plugin symlinks are checked on every launch; add the desired plugins in Settings before enabling them.
- Settings supports an immediately applied light/dark/system theme, launch at login, plugin drag-and-drop reordering, plugin help docs, update checking, and in-app updates.
- Usage display supports percentage or ratio, reset time, progress bar colors, and token usage charts with line or stacked bar modes.
- Plugins can return failures as `{"error": "message"}`; the error is shown directly in the card body.
- Supports Chinese and English; both app UI and plugin metadata display in the selected language.

## Screenshots

<table>
  <tr>
    <td><img src="Screenshots/tabs-claude.jpg" alt="Claude Tab" width="360" /></td>
    <td><img src="Screenshots/tabs-minimax.jpg" alt="MiniMax Tab" width="360" /></td>
  </tr>
  <tr>
    <td align="center">Claude Tab</td>
    <td align="center">MiniMax Tab</td>
  </tr>
  <tr>
    <td><img src="Screenshots/grouped.jpg" alt="Grouped View" width="360" /></td>
    <td><img src="Screenshots/grouped-glm.jpg" alt="GLM Chart" width="360" /></td>
  </tr>
  <tr>
    <td align="center">Grouped View</td>
    <td align="center">Grouped — GLM Chart</td>
  </tr>
  <tr>
    <td><img src="Screenshots/grouped-codex.jpg" alt="Codex Chart" width="360" /></td>
    <td><img src="Screenshots/settings.jpg" alt="Settings" width="360" /></td>
  </tr>
  <tr>
    <td align="center">Grouped — Codex Chart</td>
    <td align="center">Plugin Settings</td>
  </tr>
</table>

## Bundled Plugins

| Plugin | Script | Purpose |
| --- | --- | --- |
| Zhipu | `glm-usage-plugin.py` | Query Zhipu / ZAI Coding Plan usage and stats |
| Claude | `claude-usage-plugin.py` | Query Claude subscription usage and stats |
| Codex | `codex-usage-plugin.py` | Query OpenAI Codex CLI usage and stats |
| MiniMax | `minimax-usage-plugin.py` | Query MiniMax Coding Plan usage |
| DeepSeek | `deepseek-usage-plugin.py` | Query DeepSeek account balance |
| Kimi | `kimi-usage-plugin.py` | Query Kimi Code usage |
| Tavily | `tavily-usage-plugin.py` | Query Tavily Search monthly usage |

Bundled plugin source files are in [Resources/BundledPlugins](Resources/BundledPlugins), including the shared `_common.py` helpers. After packaging, they reside in the app bundle at `Contents/Resources/Plugins/`.

Bundled icons in [Resources/icons](Resources/icons) are packaged into `Contents/Resources/icons/`. Metadata uses resource-relative paths such as `icons/light/kimi.png`; icons are available offline.

## Runtime Directory

UsageBoard uses:

```text
~/Library/Application Support/UsageBoard/
```

Contents:

- `config.json`: Main configuration file, including plugin parameters, saved with owner-only permissions (0600).
- `plugins/`: User plugin directory. The file picker defaults to this location when adding plugins.
- `states/`: Successful plugin snapshots saved by the app.
- `plugin-caches/`: Default GLM stats cache, separated by an API key hash prefix. Claude/Codex incremental stats are stored separately at `DATA_DIR/.usageboard-chart-cache.json`.

On launch, the app creates symlinks in `plugins/` pointing to bundled plugins from `Contents/Resources/Plugins/` inside the app bundle, excluding internal modules whose names start with `_` (or `Resources/BundledPlugins/` during development). Existing regular files with matching names are preserved; existing symlinks are refreshed when the app moves. Replace a bundled symlink with a standalone script to customize it.

`icon` accepts HTTP(S) URLs, absolute file paths, `file://` URLs, and resource-relative paths. Relative paths resolve against the app bundle’s `Contents/Resources/`, or the current directory’s `Resources/` during development. For relative `icons/light/` paths, dark mode prefers a same-name `icons/dark/` file and falls back to light if missing. Load failures show the name’s initial.

## Configuration

Main configuration JSON structure:

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
        "description": "Example plugin",
        "description@zh-Hans": "示例插件",
        "description@en": "Example plugin",
        "parameters": [
          {
            "name": "API_KEY",
            "label": "API Key",
            "label@zh-Hans": "Api Key",
            "label@en": "API Key",
            "type": "secret",
            "required": true,
            "placeholder": "Service API Key"
          },
          {
            "name": "STAT_PERIOD",
            "label": "Stats Period",
            "label@zh-Hans": "统计周期",
            "label@en": "Stats Period",
            "type": "choice",
            "required": true,
            "defaultValue": "7d",
            "options": [
              {"label": "7 days", "label@zh-Hans": "7 天", "label@en": "7 days", "value": "7d"},
              {"label": "15 days", "label@zh-Hans": "15 天", "label@en": "15 days", "value": "15d"},
              {"label": "30 days", "label@zh-Hans": "30 天", "label@en": "30 days", "value": "30d"}
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

Notes:

- `overviewDisplayMode` supports `grouped` and `tabs`.
- `chartMode` supports `line` and `bar`; older configurations default to `line`.
- `theme` supports `light`, `dark`, and `system`; missing values default to `system`. Changes apply immediately and persist across launches.
- `language` supports `zh-Hans` and `en`; takes effect after restart.
- `launchAtLogin` controls launch at login.
- `plugins[].stateID` is a persistent cache ID; editing the script path, parameters, or metadata in Settings generates a new ID.
- `plugins[].executablePath` must be an actual file path; `~` and shell expressions are not expanded. Use the file picker to select it.
- `plugins[].enabled` — when `false`, the plugin is not executed.
- `plugins[].metadata` is typically parsed from the script header comment block.
- `plugins[].parameterValues` stores parameter values from the settings UI.

## Plugin Development

Plugins are recommended to use Python scripts. UsageBoard executes `.py` plugins with:

```text
/usr/bin/env python3 /path/to/plugin.py --usageboard-param KEY=value --usageboard-param USAGEBOARD_LANGUAGE=en
```

Plugins must output valid JSON to stdout. Plugin stdout is limited to 8 MiB; stderr retains at most 64 KiB. The default timeout is 15 seconds. Timeout, cancellation, or excessive stdout terminates the plugin process. Python bytecode caching is disabled to keep the app bundle unchanged. stderr can be used for debugging; non-zero exit codes, timeouts, or invalid JSON will show as plugin errors. Plugins can also write `{"error": "message"}` to stdout and exit with code 0 to report a failure, and UsageBoard shows that error in the plugin card body.

See the [Plugin Authoring Guide](Resources/PluginAuthoringGuide.html) for complete documentation.

### Parameter Metadata

Place the complete `UsageBoardPlugin` JSON comment block, including its closing marker, within the first 80 lines of the script. UsageBoard reads this block and generates a settings form:

```python
#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "name": "Example",
#   "icon": "https://example.com/icon.png",
#   "description": "Example plugin",
#   "description@zh-Hans": "示例插件",
#   "description@en": "Example plugin",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "API Key",
#       "label@zh-Hans": "Api Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Service API Key"
#     },
#     {
#       "name": "STAT_PERIOD",
#       "label": "Stats Period",
#       "label@zh-Hans": "统计周期",
#       "label@en": "Stats Period",
#       "type": "choice",
#       "required": true,
#       "defaultValue": "7d",
#       "options": [
#         {"label": "7 days", "label@zh-Hans": "7 天", "label@en": "7 days", "value": "7d"},
#         {"label": "15 days", "label@zh-Hans": "15 天", "label@en": "15 days", "value": "15d"},
#         {"label": "30 days", "label@zh-Hans": "30 天", "label@en": "30 days", "value": "30d"}
#       ]
#     }
#   ]
# }
# /UsageBoardPlugin
```

Display-related plugin metadata fields support locale-specific variants, e.g. `name@zh-Hans`, `name@en`, `description@zh-Hans`, `description@en`, `label@zh-Hans`, `label@en`, `placeholder@zh-Hans`, `placeholder@en`. If the field for the current language is missing or empty, UsageBoard falls back to the base field without a language suffix.

Supported parameter types:

- `string`
- `secret`
- `integer`
- `boolean`
- `choice`
- `directory`
- `file`

`choice` parameters use segmented controls when space permits and a menu otherwise; `directory` parameters render as a path field with a folder picker; `file` parameters render as a path field with a file picker.

Bundled plugins reuse the shared parameter helpers (standalone user plugins need `_common.py` alongside the script, or the standalone implementation in the [Plugin Authoring Guide](Resources/PluginAuthoringGuide.html)):

```python
import sys
from _common import parse_usageboard_params, app_language

params = parse_usageboard_params(sys.argv[1:])
language = app_language(params)
api_key = params.get("API_KEY", "")
```

UsageBoard also passes the current app language: `--usageboard-param USAGEBOARD_LANGUAGE=zh-Hans` or `--usageboard-param USAGEBOARD_LANGUAGE=en`. Scripts should read this reserved parameter and return display text in the corresponding language.

### Response Data Format

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

Failures can also return:

```json
{
  "error": "Invalid API Key. Check your settings."
}
```

Field descriptions:

- `updatedAt`: Plugin data update time, ISO 8601 format.
- `items[].id`: Stable item ID.
- `items[].name`: Display name.
- `items[].used` / `items[].limit`: Used amount and total quota.
- `items[].displayStyle`: `percent` shows percentage, `ratio` shows numeric ratio.
- `items[].resetAt`: Optional reset time, ISO 8601 format.
- `items[].status`: `normal`, `warning`, `critical`, or `unknown`. This field does not control the progress bar color or mark the whole plugin run as failed.
- `items[].color`: Optional progress bar color. Supports `blue`, `yellow`, `orange`, `red`, `green`. Missing or unrecognized colors follow the progress ratio: blue below 60%, yellow from 60% to below 80%, orange from 80% to below 100%, and red at 100%.
- `badge`: Optional string displayed in a rounded badge next to the plugin card title (uppercase bold text with a tinted foreground and a light matching background).
- `badgeColor`: Optional string, badge color. Supports `blue`, `orange`, `gray`, `indigo`, `purple`, `teal`, `green`, `red`, `yellow`; falls back to a text-based preset (e.g. PRO/MAX) when absent.
- `chart`: Optional token usage chart. Use the `kind: "line"` data structure; the global `chartMode` selects line or bar rendering.
- `chart.period`: Stats period identifier, e.g. `7d`, `15d`, `30d`.
- `chart.bucketUnit`: Time bucket unit, supports `hour` or `day`.
- `chart.buckets[].segments[]`: Per-bucket model segments with `model` and `tokens`.
- `chart.message`: Optional message shown when stats data is empty or unavailable.
- `error`: Optional top-level error message. When present and non-empty, the run is treated as failed and the text is shown in the card body.

The bundled Zhipu, Claude, and Codex plugins provide a `STAT_PERIOD` parameter supporting `none`, `7d`, `15d`, and `30d`; selecting none disables local stats. The Zhipu plugin uses the domestic API endpoint and is compatible with both Zhipu and ZAI Coding Plan keys. The Claude plugin fetches subscription usage via OAuth API; its `PLAN` parameter supports a `none` option that skips the API call and returns only local JSONL stats. When both the plan and the stats period are set to none, the plugin returns no data and the app hides its card. Local token totals sum actual input, output, cache creation, and cache read usage. It also supports a `CLAUDE_ONLY` toggle to filter third-party models and can use `DATA_DIR` to point at the `~/.claude` data directory. The Codex plugin reads authentication from the independent `AUTH_FILE` parameter (default `~/.codex/auth.json`) and uses `DATA_DIR` for session stats (default `~/.codex`). Changing the stats directory does not change the authentication path. Both Claude and Codex plugins use an incremental caching strategy stored in the data directory and re-scan the last cached day and subsequent days on every run. The DeepSeek plugin provides a `LIMIT` parameter for the displayed balance limit and colors the progress bar by the balance-to-limit ratio. The Codex plugin also lists the account's available rate-limit reset cards, showing the count and next expiry in a compact summary that expands into a two-column grid of cards with expiry and remaining validity; failures there never affect the quota display. The Kimi plugin queries Kimi Code's 5-hour rolling window and weekly usage and automatically displays the subscription plan mapped from the membership level returned by the API; unknown levels omit the plan badge.

Claude, Codex, and GLM share atomic cache writes; a failed write preserves the previous complete cache.

## Installation

Install via Homebrew:

```bash
brew tap marsmay/usageboard
brew install --cask usageboard
```

On first launch, macOS may show a "cannot verify developer" warning. Open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```bash
xattr -cr /Applications/UsageBoard.app
```

## System Requirements

Runtime:

- macOS 13.0 or later
- System `python3` available for executing Python plugins

Development:

- Xcode
- Swift 6.3 toolchain

## Build & Test

Debug build:

```bash
swift build
```

Run tests:

```bash
swift test
python3 -m pytest Tests/PluginTests -q
```

Python tests require pytest and use temporary data and network doubles; real account credentials are not required.

Release build:

```bash
swift build -c release
```

Build, sign, and launch `dist/UsageBoard.app` locally:

```bash
bash scripts/build.sh
```

`scripts/build.sh` stops any running UsageBoard instance, builds a release, copies the binary, bundled plugins, help document, and icons into `dist/UsageBoard.app`, injects the update check URL into Info.plist via PlistBuddy, performs ad-hoc signing, and launches the app. The `UB_UPDATE_CHECK_URL` environment variable can be used to customize the update check URL.

## Release

The release script uploads directly to the server; run it only when publishing. Without a version argument it increments the local app bundle’s patch version, not the latest release tag. For releases, check the latest tag and pass the intended version explicitly.

```bash
bash scripts/release.sh
```

Specify a version and release notes (replace the placeholders; notes can contain actual newlines):

```text
bash scripts/release.sh <version> "<release notes>"
```

The release script:

1. Reads the current version from `dist/UsageBoard.app/Contents/Info.plist`.
2. Uses the specified version or increments that local version’s patch (initializing a missing bundle at 0.1.0).
3. Auto-generates release notes from commits since the last release tag (or accepts manual notes as the second argument).
4. Builds a release.
5. Copies the binary, bundled plugins, help document, and icons.
6. Injects the update check URL into Info.plist via PlistBuddy.
7. Re-signs and verifies the app.
8. Generates `UsageBoard-<version>.zip`.
9. Generates `version.json`.
10. Uploads to the configured server path.
11. Cleans up old remote zips, retaining the latest three.

The script does not create or push Git tags, publish GitHub Releases, or update the Homebrew cask. Complete those steps separately and verify matching versions and ZIP SHA-256 values across the local artifact, server, GitHub, and cask. Stop the existing UsageBoard instance before publishing; unlike build.sh, release.sh does not stop or launch the app.

Release artifacts:

- `dist/UsageBoard-<version>.zip`
- `dist/version.json`

## Project Structure

```text
Sources/
  UsageBoardCore/       Config, models, plugin execution, cache, updates, and core logic
  UsageBoardApp/        SwiftUI + AppKit macOS app
Tests/
  UsageBoardTests/      Core XCTest
  UsageBoardAppTests/   Store, theme, language, icon, and layout XCTest
  PluginTests/          Python plugin tests
Resources/
  BundledPlugins/       Bundled Python plugins
  icons/                Local light/dark plugin icons
  PluginAuthoringGuide.html
  UsageBoard.icns
scripts/
  build.sh              Local build, sign, and launch
  release.sh            Server release script
  prepare_codex_icon.py  Regenerate Codex icons from source (requires Pillow)
dist/
  UsageBoard.app        Local test app bundle
```

See the [architecture guide](docs/architecture.md) for layering, data flow, and validation.

## License

[MIT](LICENSE)
