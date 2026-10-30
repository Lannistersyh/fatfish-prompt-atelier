#!/usr/bin/env bash
# 安装到 /Applications、固定到 Dock，并注册为可在 Finder / Launchpad 找到的常规 App
set -e
cd "$(dirname "$0")"
APP="build/大肥鱼提示词工坊.app"
TARGET="/Applications/大肥鱼提示词工坊.app"

[ -d "$APP" ] || ./build.sh

# 先退掉正在运行的旧实例，否则新副本会被单实例锁挡住
pkill -f "大肥鱼提示词工坊.app/Contents/MacOS/FatFishPrompt" 2>/dev/null || true
sleep 0.6

echo "== 复制到 /Applications =="
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$TARGET" >/dev/null 2>&1 || true

echo "== 固定到 Dock =="
# Dock 里存的是百分号转义或字面量两种写法，直接 grep 名字会漏；统一解码后比对绝对路径，避免重复图标
COUNT=$(/usr/bin/python3 - "$TARGET" <<'PYEOF'
import plistlib, subprocess, sys
from urllib.parse import unquote
raw = subprocess.run(["/usr/bin/defaults", "export", "com.apple.dock", "-"],
                     capture_output=True).stdout
try:
    d = plistlib.loads(raw)
except Exception:
    print(0); raise SystemExit
target = sys.argv[1].rstrip("/")
n = 0
for e in d.get("persistent-apps", []):
    url = ((e.get("tile-data") or {}).get("file-data") or {}).get("_CFURLString", "")
    path = unquote(url)
    if path.startswith("file://"):
        path = path[7:]
    if path.rstrip("/") == target:
        n += 1
print(n)
PYEOF
)
if [ "${COUNT:-0}" -ge 1 ]; then
  echo "Dock 中已存在（$COUNT 个），跳过"
else
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$TARGET</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock
  sleep 1.5
fi

open "$TARGET"
echo "已安装：$TARGET"
echo "Dock 与 /Applications 均可见；单实例已开启（重复启动会唤出已有实例）"
