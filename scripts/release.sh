#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/UsageBoard.app"
PLIST="$APP_BUNDLE/Contents/Info.plist"
REMOTE_HOST="root@may"
REMOTE_PATH="/data/web/usageboard"
DOWNLOAD_BASE_URL="https://may.ltd/usageboard"
UPDATE_CHECK_URL="${DOWNLOAD_BASE_URL}/version.json"

if [ ! -f "$PLIST" ]; then
    mkdir -p "$(dirname "$PLIST")"
    /usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string UsageBoard" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string UsageBoard" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ltd.may.UsageBoard" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string UsageBoard" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string 'public.app-category.productivity'" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :LSUIElement string true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$PLIST"
fi

# --- Version handling ---
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")

if [ $# -gt 0 ]; then
    NEW_VERSION="$1"
else
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
fi

echo "版本: $CURRENT_VERSION → $NEW_VERSION"

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
NOTES=$(echo "$RAW_NOTES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])')

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"

# --- Build ---
echo "构建 release..."
swift build -c release

# --- Copy binary & plugins ---
echo "打包 app..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Plugins"
cp .build/release/UsageBoard "$APP_BUNDLE/Contents/MacOS/UsageBoard"
rm -f "$APP_BUNDLE/Contents/Resources/Plugins/"*.py
rm -rf "$APP_BUNDLE/Contents/Resources/Plugins/__pycache__"
cp "$PROJECT_DIR/Resources/UsageBoard.icns" "$APP_BUNDLE/Contents/Resources/UsageBoard.icns"
cp "$PROJECT_DIR/Resources/PluginAuthoringGuide.html" "$APP_BUNDLE/Contents/Resources/PluginAuthoringGuide.html"
cp "$PROJECT_DIR/Resources/BundledPlugins/"*.py "$APP_BUNDLE/Contents/Resources/Plugins/"

# --- Inject update check URL into Info.plist ---
/usr/libexec/PlistBuddy -c "Add :UBUpdateCheckURL string ${UPDATE_CHECK_URL}" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :UBUpdateCheckURL ${UPDATE_CHECK_URL}" "$PLIST"

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -1

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
