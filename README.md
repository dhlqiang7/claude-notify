# claude-notify

OpenClaude / Claude Code 多通道终端通知系统。

当 AI 需要你关注时（权限确认、空闲休眠、任务完成），通过终端标题、tmux 窗口名、响铃、桌面通知 4 个通道提醒你。

## 功能

| 事件 | 标题图标 | 含义 |
|------|---------|------|
| 权限确认 | 🔔 | AI 请求执行命令，等待你确认 |
| 交互问答 | 🔔 | AI 弹出交互式问答 |
| 空闲休眠 | 💤 | 等待超过 60s，AI 进入休眠 |
| 任务完成 | ✅ | 当前 turn 结束 |

图标在用户输入时自动清除，恢复正常标题。

### 通知通道

1. **终端标题** — tmux 通过 `set-titles-string` 格式化；非 tmux 直接写 OSC SET_TITLE
2. **tmux 窗口名** — tmux 状态栏可见（非 tmux 环境自动跳过）
3. **终端响铃** — `\a` ×3，触发终端闪烁/声音
4. **OSC 9 桌面通知** — iTerm2/Kitty/WezTerm 等终端转为系统通知

## 快速安装

```bash
git clone git@github.com:<your-user>/claude-notify.git
cd claude-notify
./install.sh
```

重启 OpenClaude/Claude Code 即可生效。

### 安装选项

```bash
# 强制使用 Claude Code（~/.claude/）而非 OpenClaude
./install.sh --claude

# 指定自定义配置目录
./install.sh --dir=/path/to/config
```

### 前置依赖

- `jq` — 用于 JSON 合并（`apt install jq` / `brew install jq`）

## 卸载

```bash
./uninstall.sh
# 同样支持 --claude 和 --dir 参数
```

## 配置

### 标题前缀

安装后首次启动会自动检测并生成 `~/.openclaude/title-prefix`（或 `~/.claude/title-prefix`）：

| 环境 | 前缀 |
|------|------|
| 阿里云 ECS | `[ECS]` |
| WSL | `[WSL]` |
| 其他 | `[PC]` |

手动自定义：编辑该文件，写入任意前缀即可。

### tmux 配置（推荐）

在 `~/.tmux.conf` 中添加：

```tmux
set-titles-string "[MY] #W"
```

这会让 tmux 标题栏显示窗口名（含图标）。同时安装脚本会自动关闭当前窗口的 `automatic-rename`，防止等待期间图标被覆盖。

## 工作原理

安装脚本向 `settings.json` 注入以下 hook 配置：

- **SessionStart** — 检测标题前缀、设置初始窗口名、关闭 tmux automatic-rename
- **Notification** — 权限确认/问答弹窗触发 🔔，空闲休眠触发 💤
- **Stop** — turn 结束触发 ✅
- **PostToolUse** — 工具执行后立即清除 🔔（因为权限已处理）
- **UserPromptSubmit** — 用户输入时清除所有图标，恢复原标题

核心逻辑在 `scripts/alert-title.sh`，包含 rate-limiting（按 tty 隔离）和多通道通知。

## 支持环境

| 环境 | 终端标题 | tmux 窗口名 | 响铃 | OSC 9 |
|------|---------|------------|------|-------|
| tmux | ✓（通过 rename-window） | ✓ | ✓ | ✓ |
| 非 tmux | ✓（通过 OSC SET_TITLE） | — | ✓ | ✓ |
| SSH | ✓ | ✓（需 tmux） | ✓ | 取决于终端 |

## License

MIT
