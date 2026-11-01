---
name: bastion-putty-window-log
description: 在已认证的 PuTTY 窗口上通过 PostMessage(WM_CHAR) 发送命令，并读取 PuTTY 的 Printable output 日志作为输出；用于拿不到口令、无法做 SSH 桥接的堡垒机环境。
whenToUse: 用户要求操作一个已经打开的 PuTTY 堡垒机会话（窗口标题形如 root@<堡垒地址>），且该会话已开启 Printable output 日志；或提到 PuTTY 窗口、putty.log、WM_CHAR、PostMessage 时。仅手动唤起。
disable-model-invocation: true
---

# PuTTY 窗口 + 日志 操作技能

## 这个技能做什么

有些堡垒机（例如启明星辰天玥）不会把目标口令放进命令行：`Putty.dll` 启动
`putty.exe` 时只传 `-pw ******`，真口令由 `AppFill.dll` 在窗口出现后带外填入。
这种情况下拿不到口令，做不了常规 SSH 桥接，但用户已经打开了一个**已认证的
PuTTY 窗口**。

本技能只做两件事：

1. 向这个窗口发命令（`PostMessage(WM_CHAR)`，**不抢前台**）；
2. 从 PuTTY 的 **Printable output** 日志读取命令输出。

> 这是兜底路径。能拿到合法密钥/服务账号时，优先走
> `ssh -i <key> -p <tunnel-port> root@127.0.0.1`，或对应的 API 桥接器技能。
> **不要**尝试抓取口令、替换 `putty.exe`、注入 DLL。

## 前置条件（缺一不可）

- 一个活着的 PuTTY 窗口：通常是
  `C:\Program Files (x86)\PuTTY\putty.exe`，标题形如 `root@<bastion-ip>`。
- 该会话已开启日志：`Session → Logging → Printable output`，路径已知，
  `LogFlush=1`。默认示例：`%USERPROFILE%\Downloads\putty.log`。
  - 如果注册表里 `LogType=0`，说明只是运行时会话开了日志，新会话要重新开。
- 窗口停在 shell 提示符：日志最后一条非空行以 `#` 或 `$` 结尾。
- 发送进程能看到该窗口：DSH 的 `workspace-write` 沙箱**看不到**它，
  需要一次 `danger-full-access`，或者在用户的交互会话里运行本技能的脚本。

## 第一步：找到窗口

```powershell
Get-Process putty |
  Where-Object { $_.Path -like '*\PuTTY\putty.exe' -and $_.MainWindowTitle -like '*<bastion-ip>*' } |
  Select-Object Id, MainWindowTitle, MainWindowHandle, Path
```

- `MainWindowHandle` 必须非 0；0 表示窗口还没建好。
- 多个 PuTTY 时用标题里的堡垒地址过滤，不要按 PID 猜。
- 如果任务管理器里明明有、`Get-Process putty` 却是空：是沙箱/会话隔离，
  不是窗口不存在；改用 full-access，或让用户在会话里跑脚本。

## 第二步：确认日志与提示符

```powershell
$log = "$env:USERPROFILE\Downloads\putty.log"
Get-Content $log -Tail 10
```

最后一条非空行必须是提示符（例如 `root@<host>:~# `）。不是的话**不要发**：
可能正在跑命令、在 `vim/top` 里，或者弹了 host key / 多行粘贴确认框。

记下当前日志长度，发送后用它判断日志有没有增长。

## 第三步：发命令（不抢前台）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$env:USERPROFILE\.dsh\skills\bastion-putty-window-log\scripts\putty_send.ps1" `
  -Command "echo __AI_TEST__" `
  -LogPath "$env:USERPROFILE\Downloads\putty.log" `
  -TitleLike "*<bastion-ip>*"
```

脚本流程：

1. 按 `*\PuTTY\putty.exe` + 标题过滤窗口；
2. 读日志尾部，确认提示符；
3. 逐字符 `PostMessage(hwnd, WM_CHAR, ch, 1)`，间隔 20ms，再发 `0x0D` 回车；
4. 等 2 秒，读日志增量，输出 JSON：`ok`、`grew`、`post_fails`、`tail`。

**关键：用 `PostMessage`，不要用 `SendInput` / `SetForegroundWindow`。**
前者把消息直接投递给窗口，窗口可以在后台、被遮挡、最小化，用户焦点不变；
后者是全局键盘模拟，必须前台，会抢用户正在用的窗口。

手动等价代码：

```powershell
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
}
"@
$hwnd = (Get-Process -Id <PID>).MainWindowHandle
foreach ($ch in 'echo hello'.ToCharArray()) {
  [void][W]::PostMessage([IntPtr]$hwnd, 0x0102, [IntPtr][int]$ch, [IntPtr]1)
  Start-Sleep -Milliseconds 20
}
[void][W]::PostMessage([IntPtr]$hwnd, 0x0102, [IntPtr]0x0D, [IntPtr]1)
```

## 第四步：读输出

- 优先读日志**增量**：发送前记长度，发送后只取新增部分，不要每次读全文件。
- 需要精确截取时，用标记包住命令：

  ```bash
  echo __AI_BEGIN_7f3a__; df -h; echo __AI_END_7f3a__
  ```

  然后从日志里取两个标记之间的内容；标记用随机串，避免和输出撞车。
- 长输出：先重定向到目标机文件，再分段 `tail` / `sed -n`，避免日志和上下文爆炸。
- 日志编码通常是 UTF-8；中文乱码时按 GBK/系统代码页再读一次。
- 日志是明文：可能含业务敏感数据，不要外传；报告前脱敏。

## 权限与沙箱（DSH 特有）

在 DSH 里，`pwsh` 默认是 `workspace-write` 沙箱：`Get-Process putty` 看不到
用户桌面上的窗口，`FindWindow` 返回 0。发送命令需要**一次** `danger-full-access`
（命令只做窗口消息 + 读日志），或者把 `scripts/putty_send.ps1` 放到用户的
交互会话里运行（例如双击 `.vbs` 隐藏启动）。

申请 full-access 时说明：**只访问这个 PuTTY 窗口、只发这一条命令、只读这个
日志文件。** 不要默认申请；先征得用户同意。用户拒绝就停，不要绕过。

## 安全红线

1. 只操作**用户明确授权**的、已经认证的窗口；不要碰别的 PuTTY/终端。
2. 不尝试获取、记录、转发口令；不替换 `putty.exe`；不注入 DLL。
3. 危险命令（`rm -rf`、`shutdown`、`reboot`、`mkfs`、防火墙变更、生产库写入）
   逐条向用户确认。
4. 所有命令都留在堡垒机审计通道里；不绕过审计、不提权、不清理历史。
5. 日志/输出中的密码、密钥、令牌、业务数据：不外传、不写入无保护文件。

## 排错速查

| 现象 | 处理 |
|---|---|
| `NO_WINDOW` | 窗口关了/标题或路径不匹配；让用户重新打开堡垒机会话 |
| `NO_HWND` | 进程在但窗口还没建好；等 1–2 秒重试，或让用户把窗口恢复出来 |
| `NOT_AT_PROMPT` | 正在跑命令/在 `vim`/弹窗；看日志尾部，等命令结束或让用户处理弹窗 |
| `POST_FAILS>0` | UIPI：PuTTY 是提权进程；用管理员权限运行脚本 |
| `LOG_GREW=False` | 日志没开/路径不对/厂商重置了 `LogType`；让用户在 `Change Settings → Logging` 里开 Printable output |
| 发送成功但窗口没反应 | 窗口可能被模态框禁用；先处理弹窗，再发 |
| 中文乱码 | 日志按 UTF-8 读；不行再按 GBK/系统代码页 |
| 多条命令粘在一起 | 每条命令单独发送并等提示符；不要一次 `PostMessage` 多行 |

## 已验证的最小闭环

```text
PostMessage echo __AI_TEST__  ->  log 2055 -> 2104 字节
log tail:
  root@<host>:~# echo __AI_TEST__
  __AI_TEST__
  root@<host>:~#
```

窗口全程没有切到前台；用户继续用电脑不受影响。

## 与其他技能的关系

- `bastion-qizhi`：齐治堡垒机，`AccessClient\putty.exe` 桥接器 + REST API；优先用。
- `bastion-tianyue`：天玥桥接器 + REST API；能拿到桥接器端口时优先用。
- 本技能：**没有桥接器、拿不到口令、但有一个已认证 PuTTY 窗口**时的兜底。
