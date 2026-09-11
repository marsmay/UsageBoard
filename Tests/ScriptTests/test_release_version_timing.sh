#!/usr/bin/env bash
# Tests for scripts/release.sh version-write timing (M6).
# Uses a temporary project layout and PATH command stubs; never touches the
# network or the real repository. Run with: bash Tests/ScriptTests/test_release_version_timing.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_SH="$REPO_ROOT/scripts/release.sh"

PASS=0
FAIL=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label — expected [$expected], got [$actual]"
    fi
}

# Creates a temp project with an existing bundle at version 1.2.3 / build 100.
# $1: "ok" makes the swift stub succeed, "fail" makes it exit 1.
make_project() {
    local mode="$1"
    local root
    root="$(mktemp -d)"
    mkdir -p "$root/scripts" "$root/bin" \
        "$root/dist/UsageBoard.app/Contents/MacOS" \
        "$root/dist/UsageBoard.app/Contents/Resources" \
        "$root/Resources/BundledPlugins" "$root/Resources/icons/light"
    cp "$RELEASE_SH" "$root/scripts/release.sh"

    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.2.3" \
        "$root/dist/UsageBoard.app/Contents/Info.plist" >/dev/null
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 100" \
        "$root/dist/UsageBoard.app/Contents/Info.plist" >/dev/null
    echo "old-binary" > "$root/dist/UsageBoard.app/Contents/MacOS/UsageBoard"

    echo "icns" > "$root/Resources/UsageBoard.icns"
    echo "guide" > "$root/Resources/PluginAuthoringGuide.html"
    echo "# plugin" > "$root/Resources/BundledPlugins/demo.py"
    echo "icon" > "$root/Resources/icons/light/demo.png"

    if [ "$mode" = "ok" ]; then
        cat > "$root/bin/swift" <<'EOF'
#!/usr/bin/env bash
mkdir -p .build/release
echo "new-binary" > .build/release/UsageBoard
EOF
    else
        printf '#!/usr/bin/env bash\nexit 1\n' > "$root/bin/swift"
    fi
    chmod +x "$root/bin/swift"

    for tool in codesign scp ssh; do
        printf '#!/usr/bin/env bash\necho "stub %s ok"\nexit 0\n' "$tool" > "$root/bin/$tool"
        chmod +x "$root/bin/$tool"
    done
    # The temp project is not a git repo; stub git so tag/log lookups yield
    # empty results instead of failing under set -e.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/bin/git"
    chmod +x "$root/bin/git"

    echo "$root"
}

plist_get() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

# --- Case 1: build failure must leave the existing bundle untouched ---
ROOT="$(make_project fail)"
PLIST="$ROOT/dist/UsageBoard.app/Contents/Info.plist"
set +e
(cd "$ROOT" && PATH="$ROOT/bin:$PATH" bash scripts/release.sh 9.9.9 "notes" >/dev/null 2>&1)
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); echo "FAIL: failing build should make release.sh exit non-zero"
fi
assert_eq "failed build keeps old version" "1.2.3" "$(plist_get CFBundleShortVersionString "$PLIST")"
assert_eq "failed build keeps old build number" "100" "$(plist_get CFBundleVersion "$PLIST")"
assert_eq "failed build keeps old binary" "old-binary" "$(cat "$ROOT/dist/UsageBoard.app/Contents/MacOS/UsageBoard")"
rm -rf "$ROOT"

# --- Case 2: successful build applies the explicit version ---
ROOT="$(make_project ok)"
PLIST="$ROOT/dist/UsageBoard.app/Contents/Info.plist"
(cd "$ROOT" && PATH="$ROOT/bin:$PATH" bash scripts/release.sh 2.0.0 "1. 测试；" >/dev/null 2>&1)
assert_eq "explicit version written after build" "2.0.0" "$(plist_get CFBundleShortVersionString "$PLIST")"
assert_eq "binary replaced on success" "new-binary" "$(cat "$ROOT/dist/UsageBoard.app/Contents/MacOS/UsageBoard")"
assert_eq "version.json records explicit version" '"latestVersion":"2.0.0"' \
    "$(grep '"latestVersion"' "$ROOT/dist/version.json" | tr -d ' ,')"
rm -rf "$ROOT"

# --- Case 3: no argument increments patch of the current version ---
ROOT="$(make_project ok)"
PLIST="$ROOT/dist/UsageBoard.app/Contents/Info.plist"
(cd "$ROOT" && PATH="$ROOT/bin:$PATH" bash scripts/release.sh >/dev/null 2>&1)
assert_eq "auto patch increment" "1.2.4" "$(plist_get CFBundleShortVersionString "$PLIST")"
rm -rf "$ROOT"

# --- Case 4: notes preserve option-like text, backslashes, and newlines ---
for NOTES in '-n' $'-e\npath \\literal\n第二行'; do
    ROOT="$(make_project ok)"
    (cd "$ROOT" && PATH="$ROOT/bin:$PATH" bash scripts/release.sh 2.0.0 "$NOTES" >/dev/null 2>&1)
    ACTUAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["notes"])' "$ROOT/dist/version.json")
    assert_eq "release notes round trip" "$NOTES" "$ACTUAL"
    rm -rf "$ROOT"
done

echo ""
echo "release.sh 版本写入时序测试: $PASS 通过, $FAIL 失败"
[ "$FAIL" -eq 0 ]
