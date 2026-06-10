#!/bin/bash
# ============================================================
# OpenClaude 多通道通知 — 当需要用户关注时通知你
# ============================================================
# $1: permission | idle | stop | subagent_stop | clear
#
# 通知通道：
#   1. 终端标题 — tmux 内通过 rename-window 让 set-titles-string 自动格式化
#                 非 tmux 直接写终端设备 + TITLE_PREFIX 前缀
#   2. tmux 窗口名 — tmux 状态栏可见
#   3. 终端响铃 — 所有终端通用（闪烁/声音）
#   4. OSC 9 桌面通知 — iTerm2/Kitty/WezTerm（直接弹系统通知）
#
# 关键：Hook 的 stdout 被 OpenClaude 捕获，所以转义序列必须
# 写入真实终端设备（/dev/pts/N），不能依赖 stdout。
#
# 还原机制（v7）：UserPromptSubmit hook 调用 "clear" 事件驱动还原
# ============================================================

BACKUP_DIR="/tmp/claude-title-backups"
RATE_LIMIT_DIR="/tmp/claude-title-rate-limits"
PREFIX_FILE="${HOME}/.openclaude/title-prefix"
mkdir -p "$BACKUP_DIR" "$RATE_LIMIT_DIR"

# ── 标题前缀（可配置：~/.openclaude/title-prefix）───────────
load_title_prefix() {
  TITLE_PREFIX=""
  if [ -f "$PREFIX_FILE" ]; then
    TITLE_PREFIX=$(head -1 "$PREFIX_FILE" 2>/dev/null)
  fi
}

# ── 获取终端设备路径 ───────────────────────────────────────
get_tty() {
  if [ -n "$TMUX" ]; then
    tmux display-message -p '#{client_tty}' 2>/dev/null
  else
    # hook 进程可能没有真正的 tty（stdout 被捕获）
    # fallback 链：tty 命令 → SSH_TTY 环境变量
    local t
    t=$(tty 2>/dev/null) || true
    if [ -n "$t" ] && [ "$t" != "not a tty" ]; then
      echo "$t"
    elif [ -n "$SSH_TTY" ]; then
      echo "$SSH_TTY"
    else
      echo ""
    fi
  fi
}

# tty → 文件名安全后缀：/dev/pts/9 → _dev_pts_9
get_tty_suffix() {
  echo "${TTY_DEVICE}" | tr '/' '_'
}

# ── Rate Limiting（按 tty 隔离）────────────────────────────
is_rate_limited() {
  local event="$1"
  local cooldown="${2:-10}"
  local stamp_file="${RATE_LIMIT_DIR}/${event}_${TTY_SUFFIX}"
  local now
  now=$(date +%s)

  if [ -f "$stamp_file" ]; then
    local last
    last=$(cat "$stamp_file" 2>/dev/null)
    if [ -n "$last" ] && [ $((now - last)) -lt "$cooldown" ]; then
      return 0  # 被限频
    fi
  fi

  echo "$now" > "$stamp_file"
  return 1  # 未被限频
}

# 清理过期的限频文件（超过1小时）
find "$RATE_LIMIT_DIR" -type f -mmin +60 -delete 2>/dev/null

# ── 获取当前标题 ──────────────────────────────────────────
get_title() {
  if [ -n "$TMUX" ]; then
    tmux display-message -p '#W' 2>/dev/null
  else
    basename "$(pwd)"
  fi
}

# ── 设置标题 ──────────────────────────────────────────────
# tmux 内：只用 rename-window，set-titles-string 自动加前缀
# 非 tmux：直接写终端设备，手动加 TITLE_PREFIX
set_title() {
  local title="$1"
  if [ -n "$TMUX" ]; then
    tmux rename-window "$title" 2>/dev/null || true
  elif [ -n "$TTY_DEVICE" ] && [ -w "$TTY_DEVICE" ]; then
    local full_title="${TITLE_PREFIX:+${TITLE_PREFIX} }${title}"
    printf '\033]0;%s\007' "$full_title" > "$TTY_DEVICE" 2>/dev/null || true
  fi
}

# ── 终端响铃 ─────────────────────────────────────────────
send_bell() {
  if [ -n "$TTY_DEVICE" ] && [ -w "$TTY_DEVICE" ]; then
    printf '\a\a\a' > "$TTY_DEVICE" 2>/dev/null || true
  fi
}

# ── OSC 9 桌面通知（iTerm2 / Kitty / WezTerm）──────────────
send_osc9_notification() {
  local title="$1"
  local body="$2"
  if [ -n "$TTY_DEVICE" ] && [ -w "$TTY_DEVICE" ]; then
    printf '\033]9;%s;%s\007' "$title" "$body" > "$TTY_DEVICE" 2>/dev/null || true
  fi
}

# ── 保存原标题 + 加前缀（由 clear 事件驱动还原）──────────
alert_with_prefix() {
  local prefix="$1"
  local old_title raw_title
  raw_title=$(get_title)

  # 剥掉所有已知前缀，防止多事件叠加（如 ⚠ ⏳ project）
  old_title="$raw_title"
  local stripped=1
  while [ "$stripped" -eq 1 ]; do
    stripped=0
    case "$old_title" in
      "🔔 "*) old_title="${old_title#🔔 }"; stripped=1 ;;
      "✅ "*) old_title="${old_title#✅ }"; stripped=1 ;;
      "💤 "*) old_title="${old_title#💤 }"; stripped=1 ;;
    esac
  done

  local new_title="${prefix} ${old_title:-CLAUDE}"
  local backup_file="${BACKUP_DIR}/backup_${TTY_SUFFIX}"

  # 只在首次备份（保留原始标题，多次叠加不覆盖原始值）
  if [ ! -f "$backup_file" ]; then
    echo "${old_title:-CLAUDE}" > "$backup_file"
  fi

  # tmux：关闭自动重命名，防止等待期间 automatic-rename 覆盖图标
  if [ -n "$TMUX" ]; then
    tmux set-option -w automatic-rename off 2>/dev/null || true
  fi

  set_title "$new_title"
  # 强制刷新 tmux 状态栏，避免 status-interval 延迟
  [ -n "$TMUX" ] && tmux refresh-client -S 2>/dev/null || true
}

# ── 还原标题（由 clear 事件触发）──────────────────────────
restore_title() {
  local backup_file="${BACKUP_DIR}/backup_${TTY_SUFFIX}"

  if [ -f "$backup_file" ]; then
    local saved
    saved=$(cat "$backup_file")
    if [ -n "$saved" ]; then
      set_title "$saved"
    fi
    rm -f "$backup_file"
  elif [ -z "$TMUX" ]; then
    # 非 tmux：直接用当前目录名还原
    set_title "$(basename "$(pwd)")"
  fi
  # 强制刷新 tmux 状态栏
  [ -n "$TMUX" ] && tmux refresh-client -S 2>/dev/null || true
}

# ── 主入口 ─────────────────────────────────────────────────
TTY_DEVICE=$(get_tty)
TTY_SUFFIX=$(get_tty_suffix)
load_title_prefix

case "$1" in
  permission)
    is_rate_limited "permission" 2 && exit 0
    alert_with_prefix "🔔"
    send_bell
    send_osc9_notification "OpenClaude 需要确认" "工具执行需要你的授权"
    ;;

  idle)
    is_rate_limited "idle" 5 && exit 0
    alert_with_prefix "💤"
    send_bell
    ;;

  stop)
    is_rate_limited "stop" 5 && exit 0
    alert_with_prefix "✅"
    send_bell
    ;;

  subagent_stop)
    is_rate_limited "subagent_stop" 15 && exit 0
    alert_with_prefix "🔔"
    send_bell
    send_osc9_notification "OpenClaude 子任务完成" "一个子 Agent 已完成工作"
    ;;

  clear)
    restore_title
    ;;

  init)
    # 非 tmux 时设置初始终端标题为项目名
    if [ -z "$TMUX" ]; then
      set_title "$(basename "$(pwd)")"
    fi
    ;;
esac
