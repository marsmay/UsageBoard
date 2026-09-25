# UsageBoard

**[中文](README.md)** · [Homepage](https://usageboard.may.ltd/)

UsageBoard is a native macOS menu bar app that aggregates quotas, balances, and local usage statistics from APIs, model services, and search services via plugins. The app periodically executes plugins, parses their stdout JSON, and renders usage as progress bars and charts.

## Screenshots

<table>
  <tr>
    <td><img src="Screenshots/tabs-claude.jpg" alt="Claude Tab" width="360" /></td>
    <td><img src="Screenshots/tabs-codex.jpg" alt="Codex Tab" width="360" /></td>
  </tr>
  <tr>
    <td align="center">Claude Tab</td>
    <td align="center">Codex Tab</td>
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

## Features

- Lives in the menu bar; click the icon to open the panel. Grouped or tabbed layouts with drag-and-drop card ordering.
- Progress bars change color with usage; supports percentage or ratio display, reset times, and subscription plan badges.
- Token usage charts switch between line and stacked bar modes.
- Manual, scheduled (per-plugin interval), and per-card refresh; scheduled refresh pauses during system sleep and resumes on wake.
- Plugin data is cached to disk by `stateID`; the last successful data is shown on launch. A plugin can report failure as `{"error": "…"}`, shown directly in the card body.
- Settings forms are generated from script metadata, including segmented controls and directory/file pickers; new plugins are disabled by default and required parameters are validated before enabling.
- Light, dark, or system theme applied immediately; bundled plugin icons work offline and follow the theme.
- Chinese and English UI; settings fields support standard editing shortcuts (⌘Z / ⇧⌘Z / ⌘X / ⌘C / ⌘V / ⌘A).
- Optional launch at login; background update checks every 6 hours, with a capsule at the top of the popover for new versions and a non-modal panel for download and installation.
- Quitting waits for pending configuration saves; if saving takes longer than 5 seconds, the quit is cancelled and can be retried once saving completes.

## Installation

Requires macOS 13.0 or later and a system-available `python3` (used to execute plugins).

```bash
brew tap marsmay/usageboard
brew install --cask usageboard
```

On first launch, macOS may show a "cannot verify developer" warning. Open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```bash
xattr -cr /Applications/UsageBoard.app
```

After installation, add and enable the plugins you need under **Settings → Plugins**.

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
| Command Code | `commandcode-usage-plugin.py` | Query subscription 5-hour, weekly, and monthly usage |

Plugin sources live in [Resources/BundledPlugins](Resources/BundledPlugins) with the shared `_common.py` module; after packaging they reside at `Contents/Resources/Plugins/`. Bundled icons live in [Resources/icons](Resources/icons) — light/dark sets that work offline and follow the theme; the `icon` field uses resource-relative paths such as `icons/light/kimi.png`.

Per-plugin notes:

- **Zhipu**: uses the domestic API endpoint and accepts both Zhipu and ZAI Coding Plan keys. `STAT_PERIOD` supports `none` / `7d` / `15d` / `30d`; `none` disables local stats.
- **Claude**: fetches subscription usage via the OAuth API. Setting `PLAN` to `none` skips the API call and returns only local JSONL stats; when both plan and stats period are `none`, the card shows a "No usage data" placeholder. Local token totals sum actual input, output, cache creation, and cache read usage. `CLAUDE_ONLY` filters out third-party models; `DATA_DIR` points at the data directory (default `~/.claude`); `STAT_PERIOD` as above.
- **Codex**: `AUTH_FILE` (default `~/.codex/auth.json`) and `DATA_DIR` (default `~/.codex`) are independent — changing the stats directory does not change the authentication path. Lists the account's currently usable rate-limit reset cards; query failures never affect quota display. `STAT_PERIOD` as above.
- **DeepSeek**: `LIMIT` sets the displayed balance cap; the progress bar is colored by the balance-to-limit ratio.
- **Kimi**: queries the 5-hour rolling window and weekly usage. Select the subscription plan manually — Go / Plus / Pro / Max (gray / indigo / blue / orange badges; defaults to Go). The API no longer reports membership level; the badge is omitted when the plan is unset or invalid.

Implementation details: GLM, Codex, and Claude chart caches each track their own cache version and rebuild the previous 30 days once when upgrading, then resume incremental updates. Claude, Codex, and Zhipu stats caches are written atomically — a failed write preserves the previous complete cache. Codex decodes UTF-8 line by line and skips corrupted lines entirely. Claude falls back to the configured plan and then pro for empty server plan names. Kimi omits reset timestamps without a known timezone. MiniMax rejects an explicit null or non-object `base_resp`; a missing field retains the compatibility behavior.

## Plugin Development

Python scripts are recommended. The app executes `.py` plugins with:

```text
/usr/bin/env python3 /path/to/plugin.py --usageboard-param KEY=value --usageboard-param USAGEBOARD_LANGUAGE=en
```

Constraints and behavior:

- Default timeout is 15 seconds; stdout is capped at 8 MiB and stderr retains at most 64 KiB. Timeout, cancellation, or excessive stdout terminates the plugin process group (SIGTERM first, then SIGKILL after at most 1 second) — plugins must not depend on descendants outliving a run.
- Python bytecode caching is disabled to keep the app bundle unchanged.
- A non-zero exit code, timeout, or invalid stdout JSON shows as a plugin error. Alternatively, output `{"error": "message"}` with exit code 0 to report a failure; the message is shown in the card body.
- `USAGEBOARD_LANGUAGE` is a reserved parameter (`zh-Hans` / `en`); scripts should read it and return display text in the corresponding language.

See the [Plugin Authoring Guide](Resources/PluginAuthoringGuide.html) (bundled with the app) for the full protocol.

### Parameter Metadata

Place the complete `UsageBoardPlugin` JSON comment block, including its closing marker, within the first 80 lines of the script. UsageBoard reads it and generates a settings form:

```python
#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "name": "Example",
#   "icon": "https://example.com/icon.png",
#   "description": "Example plugin",
#   "description@zh-Hans": "示例插件",
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

- Parameter types: `string`, `secret`, `integer`, `boolean`, `choice`, `directory`, `file`. `choice` renders as a segmented control when space permits (menu otherwise); `directory` / `file` render as a path field with the corresponding picker.
- Display fields support `@zh-Hans` / `@en` locale variants (e.g. `name@en`, `label@zh-Hans`, `placeholder@en`); when the current language's field is missing or empty, the base field is used.

### Reading Parameters

Bundled plugins reuse `_common.py` (standalone user plugins need `_common.py` alongside the script, or the standalone implementation in the authoring guide):

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

    items = []  # Call your API here and build usage items
    return success(items)

if __name__ == "__main__":
    sys.exit(main())
```

`_common.py` provides parameter parsing (`parse_usageboard_params`), language detection (`app_language`), a translation factory (`make_translator`), output helpers (`success` / `failure`), color and status helpers (`color_for` / `status_for` / `numeric`), and unified HTTP error handling (`handle_http_error` / `handle_url_error`). See its source for the full list.

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

On failure:

```json
{ "error": "Invalid API Key. Check your settings." }
```

Field summary (see the authoring guide for full field details):

- `updatedAt` and `items[]`: required. `used` / `limit` / `displayStyle` (`percent` or `ratio`) / `resetAt` / `status` / `color` control each usage row; without a color, the bar follows the usage ratio (blue below 60%, yellow from 60% to below 80%, orange from 80% to below 100%, red at 100%).
- `badge` / `badgeColor`: optional title badge. `badgeColor` supports `blue`, `orange`, `gray` (or `grey`), `indigo`, `purple`, `teal`, `green`, `red`, `yellow`; absent values fall back to a text-based preset.
- `credits`: optional array of quota reset cards; include only currently usable cards and omit the field entirely when the query fails.
- `chart`: optional token usage chart using the `kind: "line"` structure with per-bucket model segments; the global `chartMode` selects line or bar rendering, and `chart.message` can carry a hint when stats are empty.
- `error`: optional top-level error; when present and non-empty, the run is treated as failed and the text is shown in the card body.

## Runtime Directory

```text
~/Library/Application Support/UsageBoard/
```

- `config.json`: main configuration (including plugin parameters), saved with owner-only permissions (0600).
- `plugins/`: user plugin directory; the file picker defaults here when adding plugins.
- `states/`: successful plugin snapshots saved by the app.
- `plugin-caches/`: Zhipu stats cache, separated by API key hash prefix; Claude/Codex incremental stats caches live at `DATA_DIR/.usageboard-chart-cache.json` instead.

On launch, the app creates symlinks in `plugins/` for bundled plugins (excluding internal modules starting with `_`), pointing at `Contents/Resources/Plugins/` inside the app bundle (or the project's `Resources/BundledPlugins/` during development). Existing regular files with matching names are preserved; existing symlinks are refreshed when the app moves. Replace a symlink with a standalone script to customize a bundled plugin.

`icon` accepts HTTP(S) URLs, absolute file paths, `file://` URLs, and resource-relative paths. Relative paths resolve against the app bundle's `Contents/Resources/` (or the current directory's `Resources/` during development); for `icons/light/` paths, dark mode prefers a same-name `icons/dark/` file and falls back to light, and load failures show the name's initial. Remote icons are limited to 2 MiB with a 10-second inactivity timeout and a 20-second total timeout (transfer bytes only — not decoded pixel memory); oversized or failed loads keep the placeholder.

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

- `overviewDisplayMode`: `grouped` / `tabs`; `chartMode`: `line` / `bar` (older configurations default to `line`); `theme`: `light` / `dark` / `system` (missing values default to `system`) — theme changes apply immediately and persist.
- `language`: `zh-Hans` / `en`, takes effect after restart; `launchAtLogin` controls launch at login.
- `plugins[].stateID` is a persistent cache ID; editing the script path, parameters, or metadata generates a new one.
- `plugins[].executablePath` must be an actual file path; `~` and shell expressions are not expanded — use the file picker.
- `plugins[].enabled`: when `false`, the plugin is not executed. `plugins[].metadata` is typically parsed from the script header comment block; `plugins[].parameterValues` stores values from the settings UI.

## Build & Test

Development requires Xcode and the Swift 6.3 toolchain:

```bash
swift build                                 # Debug build
swift test                                  # Swift tests
python3 -m pytest Tests/PluginTests -q      # Plugin tests (requires pytest; uses temporary data and network doubles — no real credentials)
swift build -c release                      # Release build
bash scripts/build.sh                       # Build, sign, and launch dist/UsageBoard.app locally
```

`scripts/build.sh` stops any running UsageBoard instance, builds a release, copies the binary, bundled plugins, help document, and icons into `dist/UsageBoard.app`, injects the update check URL (overridable via `UB_UPDATE_CHECK_URL`), performs ad-hoc signing, and launches the app.

## Release

The release script uploads directly to the server — run it only when publishing. Check the latest tag and pass the intended version explicitly (without a version argument it increments the local bundle's patch version):

```text
bash scripts/release.sh <version> "<release notes>"
```

The script builds a release, writes the version and build number, copies resources, signs, generates `UsageBoard-<version>.zip` and `version.json` (release notes default to commits since the last tag), uploads to the server, and prunes old remote zips (keeping the latest three).

It does not create or push Git tags, publish GitHub Releases, or update the Homebrew cask — complete those steps separately and verify matching versions and zip SHA-256 values across channels. Stop the existing UsageBoard instance before publishing; unlike build.sh, release.sh does not stop or launch the app.

## Project Structure

```text
Sources/
  UsageBoardCore/       Config, models, plugin execution, cache, updates, and core logic
  UsageBoardApp/        SwiftUI + AppKit macOS app
Tests/
  UsageBoardTests/      Core XCTest
  UsageBoardAppTests/   Store, theme, language, icon, and layout XCTest
  PluginTests/          Python plugin tests
  ScriptTests/          Isolated release-script tests
Resources/
  BundledPlugins/       Bundled Python plugins
  icons/                Local light/dark plugin icons
  PluginAuthoringGuide.html
  UsageBoard.icns
scripts/
  build.sh              Local build, sign, and launch
  release.sh            Server release script
website/                Project homepage static files
dist/
  UsageBoard.app        Local test app bundle
```

See the [architecture guide](docs/architecture.md) for layering, data flow, and validation.

## License

[MIT](LICENSE)
