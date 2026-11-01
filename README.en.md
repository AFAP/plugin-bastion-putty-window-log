# Bastion PuTTY Window Operator

<div align="center">
  <a href="README.md">中文</a> · <b>English</b>
</div>

> **Send a command to an authenticated PuTTY window, read the output back from its Printable output log.**
> The fallback path for bastions where you cannot get the password and cannot build an SSH bridge — no focus stealing, no credential handling, every command stays in the bastion audit trail.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)](#)
[![Skill: DeepSeek Harness](https://img.shields.io/badge/skill-DeepSeek%20Harness-4D6BFE)](#)

**Two ways to use it:**

| Who you are | How to use it |
|---|---|
| 🎯 **DeepSeek Harness user** | One-line skill install; invoke `/bastion-putty-window-log` in a conversation when you need it |
| 🛠 **Any script / tool** | Call `skill/bastion-putty-window-log/scripts/putty_send.ps1` directly and read its JSON — no agent framework required |

---

## 1. What problem it solves

Some bastions (e.g. Venustech TianYue) never put the target password on the command line:
`Putty.dll` launches `putty.exe` with only `-pw ******`, and the real password is injected
out-of-band by `AppFill.dll` once the window shows up. That leaves you stuck:

- no password, so no conventional SSH bridge;
- but the user already has an **authenticated PuTTY window** on screen.

This project does exactly two things: type one command into that window, and read the output back
from the log. It types via **`PostMessage`, not `SendInput`, and never brings the window to the
foreground** — a background, occluded, or minimized window still receives the keys, and the user's
work is not interrupted.

```text
┌────────────────┐   (1) PostMessage(WM_CHAR)  ┌──────────────────────┐
│ AI / scripts    │ ─────────────────────────▶ │ Authenticated PuTTY  │
│ (DSH skill)     │                            │ putty.exe (anywhere) │
└───────┬────────┘                            └──────────┬───────────┘
        │                                                │ (2) SSH (vendor client handles auth)
        │ (3) read the delta only                        ▼
        ▼                                          ┌───────────┐   ┌──────────────┐
  putty.log (Printable output) ◀─────────────────   │  Bastion  │──▶│ Target server│
                                                   └───────────┘   └──────────────┘
```

> 💡 **Fallback, not first choice**: when you have a legitimate key or service account, prefer an
> SSH bridge such as [`plugin-bastion-bridge-qizhi`](https://github.com/AFAP/plugin-bastion-bridge-qizhi)
> or [`plugin-bastion-bridge-tianyue`](https://github.com/AFAP/plugin-bastion-bridge-tianyue).
> This skill **never harvests passwords, never replaces `putty.exe`, never injects DLLs**.

## 2. Features

- ✅ **No focus stealing**: `PostMessage(hwnd, WM_CHAR, ...)` posts to the window; no `SendInput`, no `SetForegroundWindow`
- ✅ **One command at a time**: one command line plus Enter, then wait for the prompt — no glued-together input
- ✅ **Pre-send check**: reads the log tail and refuses to send unless the session sits at a shell prompt
- ✅ **Output via the log**: reads the Printable output **delta** (byte offset), never re-reads the whole file
- ✅ **Structured result**: JSON out of the box (`ok` / `grew` / `post_fails` / `tail`), with explicit error codes on failure
- ✅ **Accurate window matching**: filters on `*\PuTTY\putty.exe` + title, so the wrong window is never targeted
- ✅ **Log-read only**: scripts and docs only — no service, no listening port, no resident process
- ✅ **DeepSeek Harness skill**: loaded only when you type `/bastion-putty-window-log`; never injected into model context automatically

## 3. Directory layout

```text
plugin-bastion-putty-window-log/
├── README.md                # Chinese main README
├── README.en.md             # English version (1:1 structure)
├── LICENSE                  # MIT
├── .gitignore               # in place before the first commit (logs/backups/keys never tracked)
├── scripts/
│   └── install.ps1          # one-line install: copies the skill into ~\.dsh\skills\
└── skill/bastion-putty-window-log/   # the skill package (installed at ~\.dsh\skills\bastion-putty-window-log)
    ├── SKILL.md             #   skill instructions (the AI's operating manual)
    ├── references/
    │   └── win32-putty.md   #   Win32 message constants, PuTTY log details, sandbox and troubleshooting
    └── scripts/
        ├── putty_send.ps1   #   send one command + read the delta, prints JSON
        └── putty_read.ps1   #   log reader (tail, or from a byte offset)
```

## 4. Quick start

### 4.1 One-line skill install (recommended)

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AFAP/plugin-bastion-putty-window-log/main/scripts/install.ps1 | iex"
```

The script installs the package into `%USERPROFILE%\.dsh\skills\bastion-putty-window-log\`
(or `%DSH_HOME%\skills\` when `DSH_HOME` is set). DeepSeek Harness watches that directory, so
**no restart is needed**: type `/bastion-putty-window-log` in a conversation.
An existing installation is renamed to `bastion-putty-window-log.bak.<timestamp>` first — nothing is
silently overwritten.

### 4.2 Install from a local clone (offline)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

### 4.3 Call the scripts without installing the skill

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skill\bastion-putty-window-log\scripts\putty_send.ps1 -Command "df -h" -TitleLike "*<bastion-ip>*"
```

### 4.4 Maintenance

```powershell
# Upgrade: re-run the install command (the old copy is backed up automatically)
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AFAP/plugin-bastion-putty-window-log/main/scripts/install.ps1 | iex"
```

```powershell
# Uninstall: remove the skill directory
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\skills\bastion-putty-window-log"
```

```powershell
# Dry run the installer (prints the plan, touches nothing)
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -WhatIf
```

## 5. Prerequisites and usage

### 5.1 Prerequisites (all required)

| Requirement | Detail |
|---|---|
| A live PuTTY window | Usually `C:\Program Files (x86)\PuTTY\putty.exe`, titled like `root@<bastion-ip>` |
| Logging enabled for that session | `Session → Logging → Printable output` with *Flush log file frequently* (`LogFlush=1`) |
| The window sits at a prompt | Last non-empty log line ends with `#` or `$` |
| The sender can see the window | A DSH `workspace-write` sandbox **cannot** see desktop windows; use one `danger-full-access` run, or run it in the user's interactive session |

> ⚠️ **Logging is a hard prerequisite**: window messages can be written but not read — with logging off, sending succeeds but you get no return value.

### 5.2 (1) Find the window

```powershell
Get-Process putty |
  Where-Object { $_.Path -like '*\PuTTY\putty.exe' -and $_.MainWindowTitle -like '*<bastion-ip>*' } |
  Select-Object Id, MainWindowTitle, MainWindowHandle, Path
```

`MainWindowHandle = 0` means the window is not ready yet. Process visible in Task Manager but nothing
from `Get-Process putty` means sandbox/session isolation, not a missing window.

### 5.3 (2) Confirm it is sitting at a prompt

```powershell
Get-Content "$env:USERPROFILE\Downloads\putty.log" -Tail 10
```

If the last non-empty line is not a prompt (a command is still running, you are in `vim`/`top`, or a
host-key / multi-line-paste dialog is open), **do not send**.

### 5.4 (3) Send one command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$env:USERPROFILE\.dsh\skills\bastion-putty-window-log\scripts\putty_send.ps1" `
  -Command "echo __AI_TEST__" `
  -LogPath "$env:USERPROFILE\Downloads\putty.log" `
  -TitleLike "*<bastion-ip>*"
```

What the script does: filter windows by path + title → check the log tail for a prompt → post each
character via `PostMessage` (20 ms apart) plus Enter → wait 2 s → read the log delta → print JSON.

`-DryRun` only finds the window and checks the prompt; it sends nothing.

### 5.5 (4) Read the output

```powershell
# Read only what arrived after the send (use the "after" value from the previous JSON)
powershell -NoProfile -ExecutionPolicy Bypass -File skill\bastion-putty-window-log\scripts\putty_read.ps1 -SinceOffset <after>
```

For exact extraction, wrap the command in random markers and cut the log between them:

```bash
echo __AI_BEGIN_7f3a__; df -h; echo __AI_END_7f3a__
```

## 6. Script output and error codes

`putty_send.ps1` on success:

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

| Field | Meaning |
|---|---|
| `ok` | `post_fails = 0` **and** the log grew (exit code 0) |
| `before` / `after` | Log size in bytes before/after; feed `after` straight into `putty_read.ps1 -SinceOffset` |
| `grew` | Whether the log grew; `false` usually means logging is off, the path is wrong, or keys were dropped by UIPI |
| `post_fails` | Number of `PostMessage` calls that returned false; if `> 0`, re-run with matching (admin) privileges |
| `tail` | The last few log lines (`-TailLines`, default 20) |

On failure it prints `{"ok": false, "error": "<code>", ...}` and exits with code 1:

| Error code | Meaning | Next step |
|---|---|---|
| `LOG_NOT_FOUND` | `-LogPath` does not exist | Fix the path, or re-enable Printable output in PuTTY |
| `NO_WINDOW` | No PuTTY window matches path + title | Check `-TitleLike` / `-ExePathLike`; confirm the window is alive |
| `MULTIPLE_WINDOWS` | More than one window matched | Narrow `-TitleLike` with the bastion address; never guess by PID |
| `NO_HWND` | Process exists but the window handle is not ready | Retry after 1–2 s, or ask the user to restore the window |
| `NOT_AT_PROMPT` | The log tail is not a shell prompt | Inspect `prompt` / `tail`; wait for the command or the dialog to finish |

## 7. Parameters

`putty_send.ps1`:

| Parameter | Default | Description |
|---|---|---|
| `-Command` | (required) | Single command line; Enter is appended |
| `-LogPath` | `%USERPROFILE%\Downloads\putty.log` | PuTTY Printable output log path |
| `-TitleLike` | `*` | Window title wildcard, e.g. `*<bastion-ip>*`; required with multiple windows |
| `-ExePathLike` | `*\PuTTY\putty.exe` | Process path wildcard |
| `-WaitSeconds` | `2` | How long to wait after Enter before reading the log |
| `-TailLines` | `20` | Number of lines returned in the JSON `tail` |
| `-DryRun` | off | Find the window and check the prompt only; send nothing |

`putty_read.ps1`:

| Parameter | Default | Description |
|---|---|---|
| `-LogPath` | `%USERPROFILE%\Downloads\putty.log` | Log path |
| `-TailLines` | `40` | Number of trailing lines when `-SinceOffset` is not used |
| `-SinceOffset` | `-1` | Read from this byte offset (pair with `after` from `putty_send.ps1`); `-1` reads the tail |

## 8. Logging and troubleshooting

| Symptom | What to check |
|---|---|
| `NO_WINDOW` | Window closed / title or path mismatch / sandbox cannot see it |
| `NO_HWND` | Process up but the window is not ready; retry after 1–2 s |
| `NOT_AT_PROMPT` | A command is running, you are in `vim`/`top`, or a dialog is open; read the log tail first |
| `post_fails > 0` | UIPI: PuTTY runs elevated, so the sender must match; re-run the script as administrator |
| `grew = false` | Logging off / wrong path / the vendor reset `LogType`; re-enable Printable output under `Change Settings → Logging` |
| Send succeeded but nothing happened | The window may be disabled by a modal dialog; handle it first, then send |
| Garbled Chinese | The log is read as UTF-8; if still garbled, read again as GBK / the system code page |
| Commands glued together | Send one line, wait for the prompt, then send the next |

PuTTY log details (`LogType` values, `LogFileClash`, log header format) live in
[references/win32-putty.md](skill/bastion-putty-window-log/references/win32-putty.md).

## 9. Security and compliance (please read)

- Only act on windows the user explicitly authorized and that are already authenticated; never touch other PuTTY/terminal windows.
- **Never obtain, record, or forward credentials**; never replace `putty.exe`, inject a DLL, or fake a window.
- Confirm dangerous commands (`rm -rf`, `shutdown`, `reboot`, `mkfs`, firewall changes, production DB writes) **one by one** with the user.
- Every command goes through the bastion, so it **stays in the audit trail**; never bypass audit, escalate privileges, or scrub history.
- PuTTY logs are **plaintext** and contain command echoes and output: never share them, never commit them (`.gitignore` already ignores `*.log`), and redact before reporting.
- In DSH, sending requires one `danger-full-access` run: **this window only, this one command only, this log file only**. If the user refuses, stop — do not work around it.
- This project is an operations aid for **authorized environments only**; compliance is the user's responsibility.

## 10. FAQ

**Q: Why not just build an SSH bridge?**
A: Because there is no password to give. A bridge needs credentials, and here the credential only exists inside the vendor client's private flow. This skill avoids credentials entirely and borrows the session the user already authenticated.

**Q: Will it steal my keyboard focus?**
A: No. It uses `PostMessage`, which posts to a specific window — foreground and focus stay where they are. The only thing that can grab the foreground is PuTTY's own modal dialog (host-key confirmation, multi-line paste confirmation).

**Q: Why is logging mandatory?**
A: Window messages can be written but not read. The only way to get output back is PuTTY's Printable output log, so logging is a hard prerequisite — without it you get no return value.

**Q: Can it send a whole script at once?**
A: Not recommended. Multiple lines trigger PuTTY's multi-line paste confirmation and easily desynchronize the log. For longer logic, write a file on the target first, or chain with `;` / `&&` inside one command.

**Q: Does it support Linux / macOS?**
A: No. `PostMessage` is a Win32 API and the log path is a Windows-side convention. On other platforms, use SSH directly.

## 11. Related documents and skills

- [skill/bastion-putty-window-log/SKILL.md](skill/bastion-putty-window-log/SKILL.md) — skill instructions (the AI's operating manual)
- [skill/bastion-putty-window-log/references/win32-putty.md](skill/bastion-putty-window-log/references/win32-putty.md) — Win32/PuTTY reference
- [README.md](README.md) — Chinese version
- Sibling projects: [plugin-bastion-bridge-qizhi](https://github.com/AFAP/plugin-bastion-bridge-qizhi), [plugin-bastion-bridge-tianyue](https://github.com/AFAP/plugin-bastion-bridge-tianyue)

## 12. License

[MIT](LICENSE) © plugin-bastion-putty-window-log contributors

> Disclaimer: this project is for **authorized operations, security testing, and research** only. Users must ensure they have legitimate access to the target server, the bastion, and that session; the maintainers are not responsible for any consequence of misuse or operational error.
