# 堡垒机 PuTTY 窗口遥控 · Bastion PuTTY Window Operator

<div align="center">
  <b>中文</b> · <a href="README.en.md">English</a>
</div>

> **在已认证的 PuTTY 窗口上发命令，从 Printable output 日志读回输出。**
> 拿不到口令、做不了 SSH 桥接时的兜底通道——不抢前台、不碰凭证、所有命令仍留在堡垒机审计里。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)](#)
[![Skill: DeepSeek Harness](https://img.shields.io/badge/skill-DeepSeek%20Harness-4D6BFE)](#)

**两种玩法，各取所需：**

| 你的身份 | 用法 |
|---|---|
| 🎯 **DeepSeek Harness 用户** | 一行命令安装技能插件；需要操作会话时在对话中输入 `/bastion-putty-window-log` 手动唤起 |
| 🛠 **其他脚本 / 工具** | 直接调用 `skill/bastion-putty-window-log/scripts/putty_send.ps1`，读它输出的 JSON 即可，与任何 Agent 框架无关 |

---

## 1. 它解决了什么问题

有些堡垒机（例如启明星辰天玥）不会把目标口令放进命令行：`Putty.dll` 启动
`putty.exe` 时只传 `-pw ******`，真口令由 `AppFill.dll` 在窗口出现后带外填入。
于是出现一个尴尬局面——

- 拿不到口令，做不了常规 SSH 桥接；
- 但用户桌面上**已经有一个认证好的 PuTTY 窗口**，人和 AI 都能看到它。

本项目就只做这一件事：把「往窗口里敲一条命令」和「从日志里读回输出」这两步变成可调用的脚本。
**用 `PostMessage` 投递按键，不用 `SendInput`、不切前台**，窗口在后台、被遮挡、最小化都能收到，
用户手上的工作不会被打断。

```text
┌────────────────┐  ① PostMessage(WM_CHAR)   ┌──────────────────────┐
│ AI / 脚本       │ ───────────────────────▶ │ 已认证的 PuTTY 窗口    │
│ (DSH 技能)      │                          │ putty.exe（后台即可）  │
└───────┬────────┘                          └──────────┬───────────┘
        │                                              │ ② SSH（认证由厂商客户端托管）
        │ ③ 只读增量                                     ▼
        ▼                                        ┌───────────┐   ┌──────────────┐
  putty.log（Printable output）◀────────────────  │  堡垒机    │──▶│ 目标服务器    │
                                                 └───────────┘   └──────────────┘
```

> 💡 **兜底而非首选**：能拿到合法密钥/服务账号时，请优先用 SSH 桥接
> （如 [`plugin-bastion-bridge-qizhi`](https://github.com/AFAP/plugin-bastion-bridge-qizhi)、
> [`plugin-bastion-bridge-tianyue`](https://github.com/AFAP/plugin-bastion-bridge-tianyue)）。
> 本技能**不抓口令、不替换 `putty.exe`、不注入 DLL**。

## 2. 功能特性

- ✅ **不抢前台**：`PostMessage(hwnd, WM_CHAR, ...)` 直接投递窗口消息，不需要焦点，不调用 `SendInput` / `SetForegroundWindow`
- ✅ **只发一条命令**：一次一个命令行 + 回车，发完等提示符，避免多条命令粘在一起
- ✅ **发送前自检**：先读日志尾部确认停在 shell 提示符，不在提示符就拒发，不会把命令打进 `vim` / 提示框
- ✅ **输出靠日志**：读 PuTTY 的 Printable output **增量**（字节偏移），不重复读全文件，不污染上下文
- ✅ **结果结构化**：脚本输出 JSON（`ok` / `grew` / `post_fails` / `tail`），失败带明确错误码
- ✅ **窗口筛得准**：按 `*\PuTTY\putty.exe` + 标题过滤，多窗口时不会发错目标
- ✅ **只读日志**：安装包只含脚本与文档，无服务、无监听端口、无后台常驻进程
- ✅ **DeepSeek Harness 技能插件**：仅在输入 `/bastion-putty-window-log` 时加载，不自动注入模型上下文

## 3. 目录结构

```text
plugin-bastion-putty-window-log/
├── README.md                # 中文主 README（本文）
├── README.en.md             # 英文版（结构 1:1 平行）
├── LICENSE                  # MIT
├── .gitignore               # 先于首次提交（日志/备份/密钥不入库）
├── scripts/
│   └── install.ps1          # 一键安装：把技能包复制到 ~\.dsh\skills\
└── skill/bastion-putty-window-log/   # 技能包本体（安装后位于 ~\.dsh\skills\bastion-putty-window-log）
    ├── SKILL.md             #   技能指令（AI 的操作手册）
    ├── references/
    │   └── win32-putty.md   #   Win32 消息常量、PuTTY 日志细节、沙箱与排错
    └── scripts/
        ├── putty_send.ps1   #   发一条命令 + 读增量，输出 JSON
        └── putty_read.ps1   #   只读日志（tail 或从字节偏移读）
```

## 4. 快速开始

### 4.1 一行命令安装技能插件（推荐）

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AFAP/plugin-bastion-putty-window-log/main/scripts/install.ps1 | iex"
```

脚本把技能包装到 `%USERPROFILE%\.dsh\skills\bastion-putty-window-log\`（若设置了 `DSH_HOME` 则用 `%DSH_HOME%\skills\`）。
DeepSeek Harness 实时监听该目录，**安装后无需重启**：在对话里输入 `/bastion-putty-window-log` 唤起即可。
已有旧安装会先被移到 `%USERPROFILE%\.dsh\skills-backup\`（不留在 `skills\` 里，避免被当成第二个技能包），不会静默覆盖。

### 4.2 本地克隆安装（离线）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

### 4.3 不装技能，直接用脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skill\bastion-putty-window-log\scripts\putty_send.ps1 -Command "df -h" -TitleLike "*<bastion-ip>*"
```

### 4.4 维护命令

```powershell
# 升级：重跑安装命令即可（旧版本自动备份）
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AFAP/plugin-bastion-putty-window-log/main/scripts/install.ps1 | iex"
```

```powershell
# 卸载：删掉技能目录
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\skills\bastion-putty-window-log"
```

```powershell
# 预演安装过程（只看计划，不动文件）
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -WhatIf
```

## 5. 前置条件与使用步骤

### 5.1 前置条件（缺一不可）

| 条件 | 说明 |
|---|---|
| 一个活着的 PuTTY 窗口 | 通常是 `C:\Program Files (x86)\PuTTY\putty.exe`，标题形如 `root@<bastion-ip>` |
| 该会话已开日志 | `Session → Logging → Printable output`，勾选 *Flush log file frequently*（注册表 `LogFlush=1`） |
| 窗口停在提示符 | 日志最后一条非空行以 `#` 或 `$` 结尾 |
| 脚本能看见该窗口 | DSH 的 `workspace-write` 沙箱**看不见**用户桌面的窗口，需要一次 `danger-full-access`，或直接由用户在交互会话里运行 |

> ⚠️ **日志是硬前置条件**：窗口消息只能写、不能读；日志没开，发送会成功但拿不到任何返回值。

### 5.2 ① 找到窗口

```powershell
Get-Process putty |
  Where-Object { $_.Path -like '*\PuTTY\putty.exe' -and $_.MainWindowTitle -like '*<bastion-ip>*' } |
  Select-Object Id, MainWindowTitle, MainWindowHandle, Path
```

`MainWindowHandle` 为 0 表示窗口还没建好；任务管理器里有、`Get-Process putty` 却是空 = 沙箱/会话隔离，不是窗口不存在。

### 5.3 ② 确认停在提示符

```powershell
Get-Content "$env:USERPROFILE\Downloads\putty.log" -Tail 10
```

最后一条非空行不是提示符（可能正在跑命令、在 `vim`/`top` 里、或弹了 host key / 多行粘贴确认框）就**不要发**。

### 5.4 ③ 发一条命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$env:USERPROFILE\.dsh\skills\bastion-putty-window-log\scripts\putty_send.ps1" `
  -Command "echo __AI_TEST__" `
  -LogPath "$env:USERPROFILE\Downloads\putty.log" `
  -TitleLike "*<bastion-ip>*"
```

脚本流程：按路径 + 标题过滤窗口 → 读日志尾部确认提示符 → 逐字符 `PostMessage`（间隔 20ms）+ 回车
→ 等 2 秒 → 读日志增量 → 输出 JSON。

`-DryRun` 可只做「找窗口 + 查提示符」，一行都不发。

### 5.5 ④ 读输出

```powershell
# 只读发送之后新增的部分（偏移量用上一步 JSON 里的 after）
powershell -NoProfile -ExecutionPolicy Bypass -File skill\bastion-putty-window-log\scripts\putty_read.ps1 -SinceOffset <after>
```

需要精确截取时，用随机标记把命令包起来，再从日志里取两个标记之间的内容：

```bash
echo __AI_BEGIN_7f3a__; df -h; echo __AI_END_7f3a__
```

## 6. 脚本与返回字段速查

`putty_send.ps1` 成功时输出：

```json
{
  "ok": true,
  "pid": 12345,
  "hwnd": 132456,
  "title": "root@<bastion-ip>",
  "before": 2055,
  "after": 2104,
  "grew": true,
  "post_fails": 0,
  "command": "echo __AI_TEST__",
  "tail": ["root@<host>:~# echo __AI_TEST__", "__AI_TEST__", "root@<host>:~# "]
}
```

| 字段 | 含义 |
|---|---|
| `ok` | `post_fails = 0` 且日志确实增长，才算成功（退出码 0） |
| `before` / `after` | 发送前后的日志字节长度；`after` 可直接作为 `putty_read.ps1 -SinceOffset` |
| `grew` | 日志是否增长；`false` 通常意味着日志没开、路径不对，或按键被 UIPI 丢弃 |
| `post_fails` | `PostMessage` 返回 false 的次数；`>0` 时用同等（管理员）权限重跑 |
| `tail` | 日志尾部若干行（`-TailLines`，默认 20） |

失败时输出 `{"ok": false, "error": "<错误码>", ...}` 并以退出码 1 结束：

| 错误码 | 含义 | 下一步 |
|---|---|---|
| `LOG_NOT_FOUND` | `-LogPath` 指向的文件不存在 | 确认日志路径，或在 PuTTY 里重新开启 Printable output |
| `NO_WINDOW` | 没有匹配「路径 + 标题」的 PuTTY 窗口 | 检查 `-TitleLike` / `-ExePathLike`；确认窗口还活着 |
| `MULTIPLE_WINDOWS` | 匹配到多个窗口 | 用标题里的堡垒地址细分 `-TitleLike`，不要按 PID 猜 |
| `NO_HWND` | 进程在，但窗口句柄还没建好 | 等 1–2 秒重试，或让用户把窗口恢复出来 |
| `NOT_AT_PROMPT` | 日志尾部不是 shell 提示符 | 看 `prompt` / `tail` 字段；等命令结束或让用户处理弹窗 |

## 7. 参数速查

`putty_send.ps1`：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-Command` | （必填） | 单行命令；回车由脚本补发 |
| `-LogPath` | `%USERPROFILE%\Downloads\putty.log` | PuTTY Printable output 日志路径 |
| `-TitleLike` | `*` | 窗口标题通配符，如 `*<bastion-ip>*`；多窗口时必填 |
| `-ExePathLike` | `*\PuTTY\putty.exe` | 进程路径通配符 |
| `-WaitSeconds` | `2` | 回车后等多久再读日志 |
| `-TailLines` | `20` | JSON 里 `tail` 返回的行数 |
| `-DryRun` | 关 | 只找窗口 + 查提示符，不发送 |

`putty_read.ps1`：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-LogPath` | `%USERPROFILE%\Downloads\putty.log` | 日志路径 |
| `-TailLines` | `40` | 未指定 `-SinceOffset` 时返回的尾部行数 |
| `-SinceOffset` | `-1` | 从这里按字节读取（配合 `putty_send.ps1` 的 `after`）；`-1` 表示读尾部 |

## 8. 日志与排错

| 现象 | 排查方向 |
|---|---|
| `NO_WINDOW` | 窗口关了 / 标题或路径不匹配 / 沙箱看不到窗口 |
| `NO_HWND` | 进程在但窗口未建好；等 1–2 秒重试 |
| `NOT_AT_PROMPT` | 正在跑命令、在 `vim`/`top` 里、或弹了确认框；先看日志尾部 |
| `post_fails > 0` | UIPI：PuTTY 是提权进程，收发两端权限要匹配；用管理员权限重跑脚本 |
| `grew = false` | 日志没开 / 路径不对 / 厂商重置了 `LogType`；在 `Change Settings → Logging` 里重开 Printable output |
| 发送成功但窗口没反应 | 窗口可能被模态框禁用；先处理弹窗，再发 |
| 中文乱码 | 日志按 UTF-8 读；仍乱码时按 GBK / 系统代码页再读一次 |
| 多条命令粘在一起 | 一次只发一条，等提示符出现再发下一条 |

PuTTY 日志细节（`LogType` 取值、`LogFileClash`、日志头格式）见
[references/win32-putty.md](skill/bastion-putty-window-log/references/win32-putty.md)。

## 9. 安全与合规（务必阅读）

- 只操作**用户明确授权**的、已经认证的窗口；不要碰别的 PuTTY / 终端窗口。
- **不获取、不记录、不转发口令**；不替换 `putty.exe`、不注入 DLL、不伪造窗口。
- 危险命令（`rm -rf`、`shutdown`、`reboot`、`mkfs`、防火墙变更、生产库写入）**逐条向用户确认**。
- 所有命令都经堡垒机下发，**留在审计通道里**；不绕过审计、不提权、不清理历史。
- PuTTY 日志是**明文**，含命令回显与输出：不要外传、不要提交进仓库（`.gitignore` 已忽略 `*.log`），报告前脱敏。
- 在 DSH 中发送命令需要一次 `danger-full-access`：**只访问这个窗口、只发这一条命令、只读这个日志文件**；用户拒绝就停止，不要绕过。
- 本项目仅为**被授权环境**的运维辅助工具，使用者须自行确保合规。

## 10. FAQ

**Q：为什么不直接做 SSH 桥接？**
A：因为拿不到口令。桥接需要凭证，而这里的凭证只存在于厂商客户端的私有流程里；本技能绕开凭证，只借用用户已经认证好的窗口。

**Q：会抢走我的键盘焦点吗？**
A：不会。用的是 `PostMessage`，把消息投递给指定窗口，前台不变、焦点不变。唯一可能抢前台的是 PuTTY 自己的模态框（host key 确认、多行粘贴确认）。

**Q：为什么一定要开日志？**
A：窗口消息只能写、不能读。命令输出只能从 PuTTY 的 Printable output 日志里取，所以日志是硬前置条件；日志没开就等于没有返回值。

**Q：能一次发一整段脚本吗？**
A：不建议。多行会触发 PuTTY 的多行粘贴确认框，也容易让日志错位。要跑长逻辑，请先写到目标机文件再执行，或在一条命令里用 `;` / `&&` 串联。

**Q：支持 Linux / macOS 吗？**
A：不支持。`PostMessage` 是 Win32 API，PuTTY 的日志路径也是 Windows 侧约定。非 Windows 请直接走 SSH。

## 11. 相关文档与技能

- [skill/bastion-putty-window-log/SKILL.md](skill/bastion-putty-window-log/SKILL.md) —— 技能指令（AI 的操作手册）
- [skill/bastion-putty-window-log/references/win32-putty.md](skill/bastion-putty-window-log/references/win32-putty.md) —— Win32/PuTTY 细节参考
- [README.en.md](README.en.md) —— English version
- 兄弟项目：[plugin-bastion-bridge-qizhi](https://github.com/AFAP/plugin-bastion-bridge-qizhi)、[plugin-bastion-bridge-tianyue](https://github.com/AFAP/plugin-bastion-bridge-tianyue)

## 12. License

[MIT](LICENSE) © plugin-bastion-putty-window-log contributors

> 免责声明：本项目仅供**授权运维、安全测试与学习研究**使用。使用者须保证对目标服务器、堡垒机及该会话拥有合法操作权限；因滥用或误操作造成的后果与项目维护者无关。
