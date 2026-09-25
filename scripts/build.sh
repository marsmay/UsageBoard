#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/UsageBoard.app"
PLIST="$APP_BUNDLE/Contents/Info.plist"
UPDATE_CHECK_URL="${UB_UPDATE_CHECK_URL:-https://usageboard.may.ltd/version.json}"
# 可选参数：强制指定版本号（用于更新流程的本地测试），如 bash scripts/build.sh 0.1.0
VERSION="${1:-}"
# build 号规则：UTC %y%j%H%M（年+年积日+时+分），单调递增
APP_BUILD="${APP_BUILD:-$(TZ=UTC date +%y%j%H%M)}"

# shellcheck source=scripts/_package_common.sh
source "$(dirname "$0")/_package_common.sh"

[ -n "$VERSION" ] && validate_version "$VERSION"
ensure_info_plist

# --- Kill running instance ---
pkill -x "UsageBoard" 2>/dev/null && echo "已关闭运行中的 UsageBoard" || true
wait_for_app_exit

if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
    echo "版本号指定为: $VERSION"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$PLIST"

# --- Build ---
echo "构建 release..."
swift build -c release

package_app_bundle

# --- Launch ---
echo "启动 UsageBoard..."
open "$APP_BUNDLE"
