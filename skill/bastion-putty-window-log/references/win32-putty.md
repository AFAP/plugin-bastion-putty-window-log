# Win32 / PuTTY 细节参考

## 窗口

- PuTTY 的窗口类名是 `PuTTY`；`FindWindow("PuTTY", title)` 或
  `Get-Process putty` 的 `MainWindowHandle` 都能拿到句柄。
- 标题通常来自 session 的 `WinTitle`（例如 `root@<bastion-ip>`），
  不一定是 `user@host - PuTTY`。

## 消息常量

| 名称 | 值 | 用途 |
|---|---|---|
| `WM_CHAR` | `0x0102` | 发送字符；PuTTY 直接进 `term_keyinputw` |
| `WM_KEYDOWN` | `0x0100` | 方向键/功能键；`WM_CHAR` 不够时用 |
| `WM_KEYUP` | `0x0101` | 与 `WM_KEYDOWN` 配对 |
| `WM_COMMAND` | `0x0111` | 触发菜单命令 |
| `IDM_COPYALL` | `0x0170` | PuTTY 0.72 的 Copy All to Clipboard |
| `IDM_PASTE` | `0x01A0` | PuTTY 0.72 的 Paste from Clipboard |
| `VK_RETURN` | `0x0D` | 回车 |

`PostMessage(hwnd, WM_CHAR, ch, 1)` 的 `lParam` 用 1 即可；PuTTY 不依赖
scan code。回车可以直接发 `WM_CHAR` + `0x0D`，也可以发
`WM_KEYDOWN`/`WM_KEYUP` 的 `VK_RETURN`。

## 为什么不抢前台

- `PostMessage` / `SendMessage` 是把消息投递给**指定窗口**，不改变前台窗口，
  不需要焦点。窗口被遮挡、最小化时仍然能收到（消息队列照常处理）。
- `SendInput` / `keybd_event` 是全局键盘模拟，必须把目标窗口切到前台；
  会抢用户正在用的窗口，不要用。
- `SetForegroundWindow` 不要调用。
- 唯一可能抢前台的是 PuTTY 自己的模态框（host key 确认、多行粘贴确认）。
  首次连接让堡垒机的 `Putty.dll`/`AppFill.dll` 处理；平时避免多行粘贴。

## 窗口消息的边界

- **UIPI**：如果 PuTTY 以管理员权限运行，普通权限进程的 `WM_CHAR` 会被静默
  丢弃，`PostMessage` 可能返回 true 但日志不增长。发送端要以同等权限运行。
- **模态框**：主窗口被禁用时，`WM_CHAR` 可能不进入终端；先处理弹窗。
- **全屏程序**：`vim`/`top`/清屏会让 Printable output 日志很乱；避免或改用
  一次性命令（`--no-pager`、`-y`、`batch` 模式）。
- **字符集**：`PostMessageW` + UTF-16；中文命令可用，但远端 locale 要匹配。

## PuTTY 日志

- `Session → Logging` 的 “Printable output” 对应注册表 `LogType=1`；
  “All session output” 是 `2`；SSH packets 是 `3`/`4`。
- `LogFileName` 可以是绝对路径；`LogFlush=1` 表示逐行刷新，便于 tail。
- `LogFileClash` 建议设为 `1`（覆盖），否则文件已存在时 PuTTY 可能弹框询问。
- 日志开头有 `=~=~=~=...= PuTTY log YYYY.MM.DD HH:MM:SS =~=~=~=...` 头。
- 日志是明文，包含命令回显和输出；注意敏感信息。
- 厂商（天玥）可能在启动时重写 session 的 `LogType`；如果每次新会话日志
  都不写，让用户在 `Change Settings → Logging` 里开，或考虑用 wrapper 在
  启动前设置（不在本技能范围内）。

## 天玥的 `-pw ******`

`C:\Program Files (x86)\Bastion\Putty.dll` 里的启动模板是：

```text
-t -ssh -load %s  -pw ****** %s@%s -P %d
-t -ssh -load %s -i "%s" %s@%s -P %d
```

`******` 是字面量占位符；真口令由 `AppFill.dll` 在窗口出现后校验签名/版本
再填入。**不要**试图从 argv 抓口令、伪造窗口或替换 `putty.exe`。本技能
利用的是用户已经认证好的窗口，不碰凭证。

## DSH 沙箱

- `workspace-write` 下 `Get-Process putty` 可能看不到用户桌面的窗口，
  `FindWindow` 返回 0；这是沙箱/会话隔离，不是窗口不存在。
- 发送命令需要一次 `danger-full-access`，或在用户的交互会话里运行脚本。
- `danger-full-access` 只用于“找窗口 + 发一条命令 + 读日志”，不要扩大用途。
- 用户拒绝授权就停止，不要用计划任务/注入等方式绕过。

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| `NO_WINDOW` | 窗口关闭、路径/标题不匹配、沙箱看不到 | 确认 `\PuTTY\putty.exe`；full-access 或用户会话运行 |
| `NO_HWND` | 进程在但窗口未建好 | 等 1–2 秒重试 |
| `NOT_AT_PROMPT` | 正在跑命令/弹窗/全屏程序 | 看日志尾部，等结束或处理弹窗 |
| `POST_FAILS>0` | UIPI/句柄失效 | 同权限运行；重新取句柄 |
| `LOG_GREW=False` | 日志没开/路径错/被重置 | 开 Printable output；确认路径 |
| 日志乱码 | 编码不是 UTF-8 | 按 GBK/系统代码页读 |
| 命令粘在一起 | 一次发了多行 | 一条一条发，等提示符 |
