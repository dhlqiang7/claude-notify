#!/bin/bash
# ============================================================
# claude-notify 安装脚本
# 自动检测 OpenClaude（~/.openclaude）或 Claude Code（~/.claude），
# 合并 hooks 配置到 settings.json
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_FILE="$SCRIPT_DIR/hooks.json"

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
  echo "错误：需要 jq 命令，请先安装（apt install jq / brew install jq）"
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
    # 都没找到，默认 openclaude
    CONF_DIR="$HOME/.openclaude"
  fi
fi

SETTINGS="$CONF_DIR/settings.json"

echo "配置目录: $CONF_DIR"
echo "配置文件: $SETTINGS"

# ── 复制脚本 ──────────────────────────────────────────────
mkdir -p "$CONF_DIR/scripts"
cp "$SCRIPT_DIR/scripts/alert-title.sh" "$CONF_DIR/scripts/"
cp "$SCRIPT_DIR/scripts/detect-title-prefix.sh" "$CONF_DIR/scripts/"
chmod +x "$CONF_DIR/scripts/alert-title.sh"
chmod +x "$CONF_DIR/scripts/detect-title-prefix.sh"

SCRIPTS_DIR_ESCAPED=$(echo "$CONF_DIR/scripts" | sed 's/\//\\\//g')
echo "脚本已安装到: $CONF_DIR/scripts/"

# ── 准备 hooks JSON（替换路径占位符）─────────────────────
HOOKS_JSON=$(sed "s/{{SCRIPTS_DIR}}/$SCRIPTS_DIR_ESCAPED/g" "$HOOKS_FILE")

# ── 初始化或合并 settings.json ──────────────────────────
if [ ! -f "$SETTINGS" ]; then
  echo "{}" > "$SETTINGS"
fi

# 备份
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
echo "已备份 settings.json"

# 读取现有 settings
SETTINGS_JSON=$(cat "$SETTINGS")

# 1. 合并 env：添加 CLAUDE_CODE_DISABLE_TERMINAL_TITLE
SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq \
  '.env = (.env // {}) | .env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"')

# 2. 合并 permissions.allow：添加 alert-title.sh 通配符
ALLOW_PATTERN="Bash(bash $CONF_DIR/scripts/alert-title.sh:*)"
# 检查是否已存在
EXISTS=$(echo "$SETTINGS_JSON" | jq -r \
  ".permissions.allow // [] | any(. == \"$ALLOW_PATTERN\")")
if [ "$EXISTS" = "true" ]; then
  echo "permissions.allow 已包含 alert-title.sh 通配符，跳过"
else
  SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq \
    ".permissions.allow = (.permissions.allow // []) + [\"$ALLOW_PATTERN\"]")
  echo "已添加 permissions.allow: $ALLOW_PATTERN"
fi

# 3. 合并 hooks：按事件类型逐个追加
# 提取 hooks.json 中的事件名
EVENTS=$(echo "$HOOKS_JSON" | jq -r '.hooks | keys[]')
while IFS= read -r event; do
  NEW_HOOKS=$(echo "$HOOKS_JSON" | jq -c ".hooks[\"$event\"]")
  # 检查该事件是否已有 claude-notify 的 hook（通过脚本路径判断）
  SCRIPT_MARKER="$CONF_DIR/scripts/alert-title.sh"
  EXISTS=$(echo "$SETTINGS_JSON" | jq -r \
    ".hooks[\"$event\"] // [] | map(select(.hooks[]?.command // \"\" | contains(\"$SCRIPT_MARKER\"))) | length")

  if [ "$EXISTS" != "0" ]; then
    echo "hooks.$event 已包含 claude-notify 条目，跳过"
  else
    SETTINGS_JSON=$(echo "$SETTINGS_JSON" | jq \
      ".hooks[\"$event\"] = (.hooks[\"$event\"] // []) + $NEW_HOOKS")
    echo "已合并 hooks.$event"
  fi
done <<< "$EVENTS"

# 4. 检查 SessionStart 是否已包含 detect-title-prefix 和 init
# 如果已有 automatic-rename off 但路径不同，替换
SESSION_INIT_MARKER="detect-title-prefix.sh"
EXISTS=$(echo "$SETTINGS_JSON" | jq -r \
  ".hooks.SessionStart // [] | map(select(.hooks[]?.command // \"\" | contains(\"$SESSION_INIT_MARKER\"))) | length")
if [ "$EXISTS" != "0" ]; then
  echo "SessionStart 已包含 detect-title-prefix，跳过"
fi

# 写回
echo "$SETTINGS_JSON" | jq '.' > "$SETTINGS"

echo ""
echo "✅ 安装完成！"
echo ""
echo "下一步："
echo "  1. 重启 OpenClaude/Claude Code（让 env 变量生效）"
echo "  2. 可选：编辑 $CONF_DIR/title-prefix 自定义标题前缀"
echo "  3. tmux 用户：建议在 tmux.conf 中添加 set-titles-string '[PREFIX] #W'"
