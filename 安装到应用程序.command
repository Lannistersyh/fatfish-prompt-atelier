#!/usr/bin/env bash
# 安装到 /Applications 并注册开机可用（可选）
set -e
cd "$(dirname "$0")"
APP="build/大肥鱼提示词工坊.app"
[ -d "$APP" ] || ./build.sh
rm -rf "/Applications/大肥鱼提示词工坊.app"
cp -R "$APP" "/Applications/"
xattr -dr com.apple.quarantine "/Applications/大肥鱼提示词工坊.app" 2>/dev/null || true
open "/Applications/大肥鱼提示词工坊.app"
echo "已安装到 /Applications/大肥鱼提示词工坊.app（菜单栏出现 🐟 图标）"
