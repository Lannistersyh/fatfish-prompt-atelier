#!/usr/bin/env bash
# 构建「大肥鱼提示词工坊」：桌宠 + 提示词工坊面板
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="大肥鱼"
APP="$ROOT/build/$APP_NAME.app"
EXE="FatFishPrompt"

echo "== 1/4 清理 =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "== 2/4 编译 Swift =="
swiftc -O -swift-version 5 \
  -framework Cocoa -framework WebKit -framework Carbon \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/$EXE"

echo "== 3/4 组装 bundle =="
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "== 4/4 签名 =="
/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "构建完成：$APP"
if [ "${1:-}" = "--run" ]; then open "$APP"; fi
exit 0
