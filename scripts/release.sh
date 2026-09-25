#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/UsageBoard.app"
PLIST="$APP_BUNDLE/Contents/Info.plist"
REMOTE_HOST="root@may"
REMOTE_PATH="/data/web/usageboard"
DOWNLOAD_BASE_URL="https://usageboard.may.ltd"
UPDATE_CHECK_URL="${UB_UPDATE_CHECK_URL:-${DOWNLOAD_BASE_URL}/version.json}"

# shellcheck source=scripts/_package_common.sh
source "$(dirname "$0")/_package_common.sh"

if [ ! -f "$PLIST" ]; then
    ensure_info_plist
fi

# --- Version handling ---
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")

if [ $# -gt 0 ]; then
    NEW_VERSION="$1"
else
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
fi
validate_version "$NEW_VERSION"

echo "版本: $CURRENT_VERSION → $NEW_VERSION"
# build 号规则：UTC %y%j%H%M（年+年积日+时+分），单调递增
APP_BUILD="${APP_BUILD:-$(TZ=UTC date +%y%j%H%M)}"

# --- Release notes ---
git fetch --tags -q 2>/dev/null || true
LAST_TAG=$(git tag --sort=-version:refname | head -1)
if [ $# -ge 2 ]; then
    RAW_NOTES="$2"
elif [ -n "$LAST_TAG" ]; then
    RAW_NOTES=$(git log "${LAST_TAG}..HEAD" --format="- %s" 2>/dev/null || echo "")
else
    RAW_NOTES=""
fi
# Escape newlines for JSON
NOTES=$(printf '%s' "$RAW_NOTES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])')

# --- Build ---
echo "构建 release..."
swift build -c release

# 构建成功后再写入目标版本，避免构建失败留下新版本号 + 旧二进制
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$PLIST"

package_app_bundle

# --- Zip ---
ZIP_NAME="UsageBoard-${NEW_VERSION}.zip"
cd "$DIST_DIR"
rm -f UsageBoard-*.zip
ditto -c -k --sequesterRsrc --keepParent "UsageBoard.app" "$ZIP_NAME"
cd "$PROJECT_DIR"
echo "已生成: $DIST_DIR/$ZIP_NAME"

# --- version.json ---
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/${ZIP_NAME}"

cat > "$DIST_DIR/version.json" << EOF
{
  "updatedAt" : "${UPDATED_AT}",
  "latestVersion" : "${NEW_VERSION}",
  "latestBuild" : ${APP_BUILD},
  "downloadURL" : "${DOWNLOAD_URL}",
  "notes" : "${NOTES}"
}
EOF

echo "已生成: $DIST_DIR/version.json"
echo ""
echo "version.json 内容:"
cat "$DIST_DIR/version.json"
echo ""

# --- Upload ---
echo "上传到 ${REMOTE_HOST}:${REMOTE_PATH}..."
scp "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/version.json" "${REMOTE_HOST}:${REMOTE_PATH}/"

# --- Cleanup old zips on remote ---
echo "清理服务器旧版本..."
ssh "$REMOTE_HOST" "cd ${REMOTE_PATH} && ls -1t UsageBoard-*.zip 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true"

echo ""
echo "发布完成: v${NEW_VERSION}"
