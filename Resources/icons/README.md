# 插件图标

来源：[Lobe Icons](https://github.com/lobehub/lobe-icons)，下载于 2026-09-06。

light 文件来自现有插件 metadata 的 URL；dark 文件仅将 URL 中的 `/light/` 替换为 `/dark/` 下载。除 Codex 外保留上游 PNG 原始内容。Codex 两套图标均由 light 原图去除外部白底、保留白色 `>_`、去除边缘白色杂边，主体裁去留白后由 480×480 px 放大至 640×640 px，输出尺寸与其他图标一致，背景为真实 alpha 透明。构建和运行时无需下载。

Codex 原图保存在 `Resources/IconSources/codex-color.png`（SHA-256：`fcea9ddbaafdca236a8380cef2ecd3342ecd9914a7b080873873cf45f415686d`）。可在安装 Pillow 的 Python 环境中运行 `python3 scripts/prepare_codex_icon.py` 重新生成；无需图像生成服务。

| 文件 | 来源 | SHA-256 |
| --- | --- | --- |
| `dark/claude-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/dark/claude-color.png) | `97b53fb85b3bf401ffeb8ee7c5ebad734ce9f6edc3038f242021c53bcc18e23d` |
| `dark/codex-color.png` | [原图，已去底放大](https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-png/light/codex-color.png) | `0c2a4ba59a8e8f797aa7ef88480fc5bb4c5d0d5d0682a8eba6fdad1dd02cf59d` |
| `dark/deepseek-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/dark/deepseek-color.png) | `f98596fd7802ca0c5290c498fec578fa823988646332ee36c43b7920dc4936eb` |
| `dark/kimi.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/dark/kimi.png) | `373db4703eb8b6e5a2e165c49708bb567ef29bb210f63ee8216f5c9ee1cb66ba` |
| `dark/minimax-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/dark/minimax-color.png) | `9e596627348deb4030938a948243cc94e96cc1548d645ce4faf1de0e51b9043a` |
| `dark/tavily-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/dark/tavily-color.png) | `dfca482550546a994d5811e89329607c35667836a7751483c9be70e432c106f9` |
| `dark/zhipu-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/dark/zhipu-color.png) | `612dca42bba94fd6e760eea79bb34ee8f40f23e24944e58075d6a9ff43b6801a` |
| `light/claude-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/claude-color.png) | `97b53fb85b3bf401ffeb8ee7c5ebad734ce9f6edc3038f242021c53bcc18e23d` |
| `light/codex-color.png` | [原图，已去底放大](https://raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-png/light/codex-color.png) | `0c2a4ba59a8e8f797aa7ef88480fc5bb4c5d0d5d0682a8eba6fdad1dd02cf59d` |
| `light/deepseek-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/deepseek-color.png) | `f98596fd7802ca0c5290c498fec578fa823988646332ee36c43b7920dc4936eb` |
| `light/kimi.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/kimi.png) | `ae68c5f479c6b92bc79f56172f2bb789c50e46c69def7a443209555086acddc3` |
| `light/minimax-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/minimax-color.png) | `9e596627348deb4030938a948243cc94e96cc1548d645ce4faf1de0e51b9043a` |
| `light/tavily-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/tavily-color.png) | `dfca482550546a994d5811e89329607c35667836a7751483c9be70e432c106f9` |
| `light/zhipu-color.png` | [原始文件](https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/zhipu-color.png) | `612dca42bba94fd6e760eea79bb34ee8f40f23e24944e58075d6a9ff43b6801a` |
