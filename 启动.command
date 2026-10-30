#!/usr/bin/env bash
# 双击启动
cd "$(dirname "$0")"
APP="build/大肥鱼提示词工坊.app"
if [ ! -d "$APP" ]; then
  echo "还没构建，先编译……"
  ./build.sh || exit 1
fi
open "$APP"
