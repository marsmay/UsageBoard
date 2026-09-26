#!/usr/bin/env bash
# build.sh 与 release.sh 的公共打包逻辑。被 source 使用，不独立执行。
# 调用方需先设置：PROJECT_DIR、DIST_DIR、APP_BUNDLE、PLIST、UPDATE_CHECK_URL、APP_BUILD。

# 版本号必须是点分整数（2-3 段），否则在线更新的点分整数比较会失效。
validate_version() {
    local version="$1"
    if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
        echo "错误: 版本号 '$version' 不是点分整数（如 1.0.0）" >&2
        exit 1
    fi
}

# 首次创建 bundle 时生成基础 Info.plist；已存在时跳过（幂等）。
ensure_info_plist() {
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
}

# 最多等待 10 秒；旧实例未退出时中止，避免覆盖仍在运行的 bundle。
wait_for_app_exit() {
    local waited=0
    while pgrep -x UsageBoard >/dev/null 2>&1; do
        if [ "$waited" -ge 50 ]; then
            echo "错误: 等待 UsageBoard 退出超时，停止构建" >&2
            return 1
        fi
        sleep 0.2
        waited=$((waited + 1))
    done
}

# swift build 成功后调用：复制二进制/插件/图标/帮助，注入更新 URL，签名并校验。
package_app_bundle() {
    echo "打包 app..."
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Plugins"
    cp "$PROJECT_DIR/.build/release/UsageBoard" "$APP_BUNDLE/Contents/MacOS/UsageBoard"
    rm -f "$APP_BUNDLE/Contents/Resources/Plugins/"*.py
    rm -rf "$APP_BUNDLE/Contents/Resources/Plugins/__pycache__"
    cp "$PROJECT_DIR/Resources/UsageBoard.icns" "$APP_BUNDLE/Contents/Resources/UsageBoard.icns"
    cp "$PROJECT_DIR/Resources/PluginAuthoringGuide.html" "$APP_BUNDLE/Contents/Resources/PluginAuthoringGuide.html"
    cp "$PROJECT_DIR/Resources/BundledPlugins/"*.py "$APP_BUNDLE/Contents/Resources/Plugins/"
    rm -rf "$APP_BUNDLE/Contents/Resources/icons"
    mkdir -p "$APP_BUNDLE/Contents/Resources/icons"
    cp -R "$PROJECT_DIR/Resources/icons/." "$APP_BUNDLE/Contents/Resources/icons/"

    /usr/libexec/PlistBuddy -c "Add :UBUpdateCheckURL string ${UPDATE_CHECK_URL}" "$PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :UBUpdateCheckURL ${UPDATE_CHECK_URL}" "$PLIST"

    codesign --force --deep --sign - "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -1
}
