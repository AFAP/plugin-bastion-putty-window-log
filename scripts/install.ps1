# Install the DeepSeek Harness skill "bastion-putty-window-log".
#
# 1. Copies the skill package (skill/bastion-putty-window-log) into
#    %USERPROFILE%\.dsh\skills\bastion-putty-window-log
#    (or %DSH_HOME%\skills\bastion-putty-window-log when DSH_HOME is set).
#    DeepSeek Harness watches that directory, so no restart is needed.
# 2. An existing installation is renamed to <target>.bak.<timestamp> first.
#
# Remote one-liner:
#   powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AFAP/plugin-bastion-putty-window-log/main/scripts/install.ps1 | iex"
# Local clone (offline):
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#
# Arguments are read from $args so both `irm | iex` and `-File` keep working:
#   -Owner <github-user>   default AFAP
#   -Repo  <repo-name>     default plugin-bastion-putty-window-log
#   -Ref   <branch>        default main
#   -WhatIf                print the plan, change nothing
$Owner = ""
$Repo = "plugin-bastion-putty-window-log"
$Ref = "main"
$WhatIf = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^(-|/)Owner$'  { $i++; if ($i -lt $args.Count) { $Owner = $args[$i] } }
        '^(-|/)Repo$'   { $i++; if ($i -lt $args.Count) { $Repo = $args[$i] } }
        '^(-|/)Ref$'    { $i++; if ($i -lt $args.Count) { $Ref = $args[$i] } }
        '^(-|/)WhatIf$' { $WhatIf = $true }
    }
}

$DefaultOwner = "AFAP"
if (-not $Owner) { $Owner = $DefaultOwner }

$SkillName = "bastion-putty-window-log"
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    [OK] $Message" -ForegroundColor Green }
function Write-Warn2([string]$Message) { Write-Host "    [NOTE] $Message" -ForegroundColor Yellow }

function Resolve-SkillsRoot {
    if ($env:DSH_HOME -and $env:DSH_HOME.Trim().Length -gt 0) {
        return Join-Path $env:DSH_HOME "skills"
    }
    return Join-Path $HOME ".dsh\skills"
}

$SkillsRoot = Resolve-SkillsRoot
$SkillTarget = Join-Path $SkillsRoot $SkillName

# ---------- 1. Locate the skill package (local clone first, else repository zip) ----------
$BundleSource = $null
if ($PSScriptRoot) {
    $LocalBundle = Join-Path (Join-Path $PSScriptRoot "..\skill") $SkillName
    if (Test-Path (Join-Path $LocalBundle "SKILL.md")) {
        $BundleSource = (Resolve-Path $LocalBundle).Path
        Write-Step "Using local skill package: $BundleSource"
    }
}

if (-not $BundleSource) {
    if (-not $Owner) {
        Write-Host "ERROR: no local skill package and no -Owner given." -ForegroundColor Red
        Write-Host "  Run this script inside a cloned repository, or pass -Owner <your-github-user>."
        exit 1
    }
    $ZipUrl = "https://codeload.github.com/$Owner/$Repo/zip/refs/heads/$Ref"
    $ZipPath = Join-Path $env:TEMP "$Repo-$Ref.zip"
    $ExtractDir = Join-Path $env:TEMP "$Repo-$Ref"
    $RefFolder = $Ref -replace '/', '-'
    $RemoteBundle = Join-Path (Join-Path (Join-Path $ExtractDir "$Repo-$RefFolder") "skill") $SkillName
    Write-Step "Downloading skill package: $ZipUrl"
    if (-not $WhatIf) {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
        if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
        Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
        $BundleSource = $RemoteBundle
    } else {
        Write-Warn2 "WhatIf: would download and extract $ZipUrl"
        $BundleSource = $RemoteBundle
    }
}

if (-not $WhatIf -and -not (Test-Path (Join-Path $BundleSource "SKILL.md"))) {
    Write-Host "ERROR: SKILL.md not found in $BundleSource" -ForegroundColor Red
    exit 1
}

# ---------- 2. Install the skill package ----------
Write-Step "Installing skill to: $SkillTarget"
if ($WhatIf) {
    Write-Warn2 "WhatIf: would copy $BundleSource -> $SkillTarget"
    Write-Warn2 "WhatIf: an existing installation would be renamed to $SkillTarget.bak.<timestamp>"
} else {
    New-Item -ItemType Directory -Force -Path $SkillsRoot | Out-Null
    if (Test-Path $SkillTarget) {
        $Backup = "$SkillTarget.bak." + (Get-Date -Format "yyyyMMddHHmmss")
        Move-Item -LiteralPath $SkillTarget -Destination $Backup -Force
        Write-Warn2 "Existing installation backed up to: $Backup"
    }
    Copy-Item -Path $BundleSource -Destination $SkillTarget -Recurse
    if (-not (Test-Path (Join-Path $SkillTarget "SKILL.md"))) {
        Write-Host "ERROR: copy finished but SKILL.md is missing in $SkillTarget" -ForegroundColor Red
        exit 1
    }
    Write-Ok "Installed files:"
    Get-ChildItem $SkillTarget -Recurse -File | ForEach-Object { Write-Host "      $($_.FullName)" }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "======== dry run finished, nothing changed ========" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "======== skill installed ========" -ForegroundColor Green
    Write-Host "DeepSeek Harness watches the skills directory; no restart required."
    Write-Host "How to use:"
    Write-Host "  * type /$SkillName in a DSH conversation to invoke the skill;"
    Write-Host "  * the skill is manual-invocation only and is not injected automatically."
}
Write-Host ""
Write-Host "Uninstall:"
Write-Host "  Remove-Item -Recurse -Force '$SkillTarget'"
Write-Host ""
Write-Host "Before the skill can send anything, the target session needs PuTTY logging:"
Write-Host "  Session -> Logging -> Printable output, with LogFlush=1 (flush log file frequently)."
