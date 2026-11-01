<#
.SYNOPSIS
    Send one command to an authenticated PuTTY window via PostMessage(WM_CHAR)
    and read the PuTTY printable-output log as the response.

.DESCRIPTION
    Does NOT use SendInput / SetForegroundWindow, so the window stays in the
    background and the user's focus is not stolen.

    Requires a live PuTTY window. Under the DSH workspace-write sandbox the
    window is not visible; run this script with danger-full-access, or from the
    user's interactive session.

.PARAMETER Command
    The single command line to type (Enter is appended automatically).

.PARAMETER LogPath
    PuTTY session log path (Printable output). Default: %USERPROFILE%\Downloads\putty.log

.PARAMETER TitleLike
    MainWindowTitle wildcard filter, e.g. *<bastion-ip>*. Default * (all).

.PARAMETER ExePathLike
    Process path wildcard filter. Default *\PuTTY\putty.exe.

.PARAMETER WaitSeconds
    Seconds to wait after pressing Enter before reading the log.

.PARAMETER TailLines
    Number of log lines to return in the JSON tail.

.PARAMETER DryRun
    Find the window and check the prompt, but do not send anything.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$LogPath = (Join-Path $env:USERPROFILE 'Downloads\putty.log'),
    [string]$TitleLike = '*',
    [string]$ExePathLike = '*\PuTTY\putty.exe',
    [int]$WaitSeconds = 2,
    [int]$TailLines = 20,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
}
"@

function Read-LogTail {
    param([string]$Path, [int]$Lines)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $len = $fs.Length
        $start = [Math]::Max(0, $len - 65536)
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
        $text = $sr.ReadToEnd()
        $sr.Close()
    } finally {
        $fs.Close()
    }
    $arr = $text -split "`r?`n"
    return @($arr | Select-Object -Last $Lines)
}

if (-not (Test-Path -LiteralPath $LogPath)) {
    [pscustomobject]@{ ok = $false; error = "LOG_NOT_FOUND: $LogPath" } | ConvertTo-Json
    exit 1
}

$candidates = @(Get-Process putty -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like $ExePathLike -and $_.MainWindowTitle -like $TitleLike })

if ($candidates.Count -eq 0) {
    [pscustomobject]@{
        ok = $false; error = 'NO_WINDOW'; exe = $ExePathLike; title = $TitleLike
    } | ConvertTo-Json
    exit 1
}
if ($candidates.Count -gt 1) {
    [pscustomobject]@{
        ok = $false; error = 'MULTIPLE_WINDOWS'
        windows = @($candidates | ForEach-Object { @{ pid = $_.Id; title = $_.MainWindowTitle } })
    } | ConvertTo-Json -Depth 5
    exit 1
}

$p = $candidates[0]
$hwnd = [IntPtr]$p.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) {
    [pscustomobject]@{ ok = $false; error = 'NO_HWND'; pid = $p.Id } | ConvertTo-Json
    exit 1
}

$tailBefore = Read-LogTail -Path $LogPath -Lines $TailLines
$last = ($tailBefore | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
$before = (Get-Item -LiteralPath $LogPath).Length

if ($last -notmatch '[#$]\s*$') {
    [pscustomobject]@{
        ok = $false; error = 'NOT_AT_PROMPT'; pid = $p.Id; hwnd = $hwnd.ToInt64()
        prompt = $last; tail = $tailBefore
    } | ConvertTo-Json -Depth 5
    exit 1
}

if ($DryRun) {
    [pscustomobject]@{
        ok = $true; dry_run = $true; pid = $p.Id; hwnd = $hwnd.ToInt64()
        title = $p.MainWindowTitle; before = $before; prompt = $last; tail = $tailBefore
    } | ConvertTo-Json -Depth 5
    exit 0
}

$fails = 0
foreach ($ch in $Command.ToCharArray()) {
    if (-not [W]::PostMessage($hwnd, 0x0102, [IntPtr][int]$ch, [IntPtr]1)) { $fails++ }
    Start-Sleep -Milliseconds 20
}
if (-not [W]::PostMessage($hwnd, 0x0102, [IntPtr]0x0D, [IntPtr]1)) { $fails++ }

Start-Sleep -Seconds $WaitSeconds

$tailAfter = Read-LogTail -Path $LogPath -Lines $TailLines
$after = (Get-Item -LiteralPath $LogPath).Length
$grew = $after -gt $before
$ok = ($fails -eq 0 -and $grew)

[pscustomobject]@{
    ok = $ok
    pid = $p.Id
    hwnd = $hwnd.ToInt64()
    title = $p.MainWindowTitle
    before = $before
    after = $after
    grew = $grew
    post_fails = $fails
    command = $Command
    tail = $tailAfter
} | ConvertTo-Json -Depth 5

if (-not $ok) { exit 1 }
