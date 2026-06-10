#!/bin/bash
# ============================================================
# 自动检测终端标题前缀，写入 ~/.openclaude/title-prefix
# ============================================================
# 规则：hostname 含 ecs → [ECS]、含 wsl → [WSL]、其余 → [PC]
# 已存在且有内容时不覆盖（允许手动自定义）

PREFIX_FILE="$HOME/.openclaude/title-prefix"

# 如果用户已手动设置，尊重用户值不覆盖
if [ -f "$PREFIX_FILE" ] && [ -s "$PREFIX_FILE" ]; then
  exit 0
fi

detect_prefix() {
  # WSL 检测（内核版本含 Microsoft/microsoft）
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "[WSL]"
    return
  fi

  # hostname 特征检测
  local hostname
  hostname=$(hostname 2>/dev/null || echo "")
  case "$hostname" in
    *ecs*|*ECS*) echo "[ECS]"; return ;;
    *wsl*|*WSL*) echo "[WSL]"; return ;;
  esac

  echo "[PC]"
}

PREFIX=$(detect_prefix)
echo "$PREFIX" > "$PREFIX_FILE"
