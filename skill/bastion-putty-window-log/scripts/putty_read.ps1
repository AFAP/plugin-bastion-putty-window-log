<#
.SYNOPSIS
    Read a PuTTY printable-output log: tail, or everything since a byte offset.

.PARAMETER LogPath
    PuTTY session log path. Default: %USERPROFILE%\Downloads\putty.log

.PARAMETER TailLines
    Number of lines to return when SinceOffset is not used.

.PARAMETER SinceOffset
    Byte offset to read from. Use the "after" value from putty_send.ps1 to read
    only the new output. -1 means "tail".
#>
[CmdletBinding()]
param(
    [string]$LogPath = (Join-Path $env:USERPROFILE 'Downloads\putty.log'),
    [int]$TailLines = 40,
    [long]$SinceOffset = -1
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "LOG_NOT_FOUND: $LogPath"
}

$fs = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $len = $fs.Length
    if ($SinceOffset -ge 0 -and $SinceOffset -le $len) {
        [void]$fs.Seek($SinceOffset, [System.IO.SeekOrigin]::Begin)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
        $text = $sr.ReadToEnd()
        $sr.Close()
        $text
    } else {
        $start = [Math]::Max(0, $len - 65536)
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
        $text = $sr.ReadToEnd()
        $sr.Close()
        (($text -split "`r?`n") | Select-Object -Last $TailLines) -join "`n"
    }
} finally {
    $fs.Close()
}
