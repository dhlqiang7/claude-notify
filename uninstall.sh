#!/bin/bash
# ============================================================
# claude-notify 卸载脚本
# 从 settings.json 中移除 claude-notify 相关配置
# ============================================================
set -euo pipefail

# ── 参数解析 ──────────────────────────────────────────────
FORCE_CLAUDE=false
CONF_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)   FORCE_CLAUDE=true; shift ;;
    --dir=*)    CONF_DIR="${1#--dir=}"; shift ;;
    -h|--help)
      echo "用法: $0 [--claude] [--dir=<path>]"
      echo "  --claude       强制使用 Claude Code（~/.claude/）"
      echo "  --dir=<path>   指定配置目录"
      exit 0
      ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 检测依赖 ──────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "错误：需要 jq 命令"
  exit 1
fi

# ── 确定配置目录 ──────────────────────────────────────────
if [ -z "$CONF_DIR" ]; then
  if [ "$FORCE_CLAUDE" = true ]; then
    CONF_DIR="$HOME/.claude"
  elif command -v openclaude &>/dev/null; then
    CONF_DIR="$HOME/.openclaude"
  elif command -v claude &>/dev/null; then
    CONF_DIR="$HOME/.claude"
  else
    CONF_DIR="$HOME/.openclaude"
  fi
fi

SETTINGS="$CONF_DIR/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "未找到 $SETTINGS，无需卸载"
  exit 0
fi

echo "配置目录: $CONF_DIR"
echo "配置文件: $SETTINGS"

# 备份
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

SCRIPT_MARKER="$CONF_DIR/scripts/alert-title.sh"
SETTINGS_JSON=$(cat "$SETTINGS")

# 1. 移除 hooks 中包含 alert-title.sh 的条目组
EVENTS=$(echo "$SETTINGS_JSON" | jq -r '.hooks | keys[]')
while IFS= read -r event; do
  # 过滤掉任何包含 alert-title.sh 路径的 hook 组
  BEFORE=$(echo "$SETTINGS_JSON" | jq ".hooks[\"$event\"] | length")
  SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq \
    ".hooks[\"$event\"] = [.hooks[\"$event\"][] | select(
      (.hooks // []) | map(.command // \"\") | all(contains(\"$SCRIPT_MARKER\") | not)
    )]")
  AFTER=$(echo "$SETTINGS_JSON" | jq ".hooks[\"$event\"] | length")
  if [ "$BEFORE" != "$AFTER" ]; then
    echo "已移除 hooks.$event 中的 claude-notify 条目 ($BEFORE → $AFTER)"
  fi
  # 如果事件下为空数组，删除整个事件键
  SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq \
    "if (.hooks[\"$event\"] | length) == 0 then .hooks |= del(.\"$event\") else . end")
done <<< "$EVENTS"

# 2. 移除 SessionStart 中 detect-title-prefix.sh 条目
SESSION_MARKER="$CONF_DIR/scripts/detect-title-prefix.sh"
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq '
  if .hooks.SessionStart then
    .hooks.SessionStart = [.hooks.SessionStart[] |
      .hooks = [.hooks[] | select((.command // "") | contains("'"$SESSION_MARKER"'") | not)]
    ] |
    .hooks.SessionStart = [.hooks.SessionStart[] | select((.hooks | length) > 0)]
  else . end
')

# 3. 移除 SessionStart 中 automatic-rename off 条目
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq '
  if .hooks.SessionStart then
    .hooks.SessionStart = [.hooks.SessionStart[] |
      .hooks = [.hooks[] | select((.command // "") | contains("automatic-rename") | not)]
    ] |
    .hooks.SessionStart = [.hooks.SessionStart[] | select((.hooks | length) > 0)]
  else . end
')

# 清理空的 SessionStart
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq '
  if .hooks.SessionStart then
    .hooks.SessionStart = [.hooks.SessionStart[] | select((.hooks | length) > 0)]
  | if (.hooks.SessionStart | length) == 0 then .hooks |= del(.SessionStart) else . end
  else . end
')

# 4. 如果 hooks 为空对象，删除 hooks 键
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq '
  if (.hooks | length) == 0 then del(.hooks) else . end
')

# 5. 移除 env 中的 CLAUDE_CODE_DISABLE_TERMINAL_TITLE
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq '
  if .env then .env |= del(.CLAUDE_CODE_DISABLE_TERMINAL_TITLE) else . end |
  if (.env | length) == 0 then del(.env) else . end
')

# 6. 移除 permissions.allow 中的 alert-title.sh 通配符
ALLOW_PATTERN="Bash(bash $CONF_DIR/scripts/alert-title.sh:*)"
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq '
  if .permissions then
    .permissions.allow = (.permissions.allow // [] | map(select(. != "'"$ALLOW_PATTERN"'")))
    | if (.permissions.allow | length) == 0 then .permissions |= del(.allow) else . end
    | if (.permissions | length) == 0 then del(.permissions) else . end
  else . end
')

# 写回
echo "$SETTINGS_JSON" | jq '.' > "$SETTINGS"

# 7. 删除脚本文件
rm -f "$CONF_DIR/scripts/alert-title.sh"
rm -f "$CONF_DIR/scripts/detect-title-prefix.sh"
echo "已删除 $CONF_DIR/scripts/alert-title.sh"
echo "已删除 $CONF_DIR/scripts/detect-title-prefix.sh"

# 不删除 title-prefix 文件（可能是用户自定义的）

echo ""
echo "✅ 卸载完成！settings.json 已更新（备份在 .bak 文件中）"
echo "注意：如果不再需要 CLAUDE_CODE_DISABLE_TERMINAL_TITLE，"
echo "  其他会话可能需要重启才能恢复 OpenClaude 自身标题设置。"
