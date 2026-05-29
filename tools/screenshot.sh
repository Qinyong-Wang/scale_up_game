#!/usr/bin/env bash
# tools/screenshot.sh — 一行命令出截图, 验收新 sidebar / 卡片墙 UI。
#
# 用法:
#   tools/screenshot.sh                          # 默认 overview (autoplay 后默认 tab)
#   tools/screenshot.sh models                   # 切到 模型 tab 截图
#   tools/screenshot.sh infra
#   tools/screenshot.sh hiring|product|dataset|tasks|events|tech|market_rank|...
#   tools/screenshot.sh drawer:deploy_first_dc   # 抽屉验收: 切 infra + 自动打开部署抽屉
#
# 流程:
#   1. 清掉旧 screenshot.png
#   2. AGI_AUTOPLAY=1 AGI_SCREENSHOT=1 [AGI_INITIAL_NAV=<nav>] godot --path
#      autoplay 跑完一条剧本 (建 5 lead / 2 dc / 1 published model / 2 products /
#      推 8 周), 切到目标 tab, 截 viewport 存 user://screenshot.png 退出。
#   3. 输出截图的绝对路径到 stdout。
#
# 详见 docs/端到端调试.md。

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHOT_DIR="$HOME/Library/Application Support/Godot/app_userdata/Scaling Up"
SHOT_PATH="$SHOT_DIR/screenshot.png"

ARG="${1:-}"

rm -f "$SHOT_PATH"

# drawer:<scenario> 触发抽屉打开场景 (内部会先切对应 tab);
# 其余字符串作 AGI_INITIAL_NAV 用。
if [[ "$ARG" == drawer:* ]]; then
  SCENARIO="${ARG#drawer:}"
  AGI_AUTOPLAY=1 AGI_SCREENSHOT=1 AGI_OPEN_DRAWER="$SCENARIO" \
    godot --path "$REPO_DIR" 2>&1 \
    | grep -E "screenshot_saved|SCRIPT ERROR" || true
elif [ -n "$ARG" ]; then
  AGI_AUTOPLAY=1 AGI_SCREENSHOT=1 AGI_INITIAL_NAV="$ARG" \
    godot --path "$REPO_DIR" 2>&1 \
    | grep -E "screenshot_saved|SCRIPT ERROR" || true
else
  AGI_AUTOPLAY=1 AGI_SCREENSHOT=1 \
    godot --path "$REPO_DIR" 2>&1 \
    | grep -E "screenshot_saved|SCRIPT ERROR" || true
fi

if [ -f "$SHOT_PATH" ]; then
  echo "$SHOT_PATH"
else
  echo "ERROR: screenshot not produced at $SHOT_PATH" >&2
  exit 1
fi
