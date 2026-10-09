<#
    deploy.ps1 - Copy GlassMailbox (and optionally MailProbe) into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    The glass material is the embedded LibGlass-1.0. The packager fetches it
    into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev copy this script
    hands that job to the LibGlass checkout's own deploy.ps1, which checks the
    checkout, copies only the shipped files and prints its commit. The checkout
    is $env:LIBGLASS, else ..\LibGlass. (GlassChat's deploy, trimmed.)

    Usage:
        pwsh Tools/deploy.ps1               # GlassMailbox
        pwsh Tools/deploy.ps1 -Probe        # ...and MailProbe
        pwsh Tools/deploy.ps1 -ProbeOnly    # just MailProbe
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Probe,
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

. (Join-Path $PSScriptRoot "LibGlassPin.ps1")
$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }

function Deploy-Addon {
    $dest = Join-Path $AddOnsPath "GlassMailbox"
    if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
        Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
        exit 1
    }
    Write-LibGlassPinStatus $RepoRoot $LibGlass "this deploy tests a library the release won't ship"
    # The library first: its deploy checks the checkout and may refuse, and a
    # refusal must leave the deployed addon as it was.
    & pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon GlassMailbox -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE -ne 0) { Write-Error "LibGlass deploy refused; GlassMailbox was not touched"; exit 1 }
    Write-Host "Deploying GlassMailbox -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    # The TOC is the list of what ships (subfolders included, e.g. Core\).
    $lua = @(Get-Content -LiteralPath (Join-Path $RepoRoot "GlassMailbox.toc") | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" })
    $files = @("GlassMailbox.toc", "LICENSE") + $lua
    foreach ($f in $files) {
        $src = Join-Path $RepoRoot $f
        $to = Join-Path $dest $f
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
        if ($f -like "*.toc") {
            (Get-Content -LiteralPath $src -Raw) -replace '## Version: @project-version@', '## Version: dev' |
                Set-Content -LiteralPath $to -NoNewline
        } else {
            Copy-Item -LiteralPath $src -Destination $to -Force
        }
        Write-Host "  $f"
    }
    # A Lua file removed from the repo must not linger where the client finds it.
    $keep = $files | ForEach-Object { $_.Replace("/", "\") }
    Get-ChildItem -LiteralPath $dest -File -Recurse | Where-Object { $_.FullName -notlike (Join-Path $dest "Libs\*") } |
        ForEach-Object {
            $rel = $_.FullName.Substring($dest.Length + 1)
            if ($keep -notcontains $rel) {
                Write-Host "  removing stale $rel" -ForegroundColor DarkYellow
                Remove-Item -LiteralPath $_.FullName -Force
            }
        }
}

function Deploy-Probe {
    $dest = Join-Path $AddOnsPath "MailProbe"
    Write-Host "Deploying MailProbe -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools\MailProbe") -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
        Write-Host "  $($_.Name)"
    }
}

if (-not $ProbeOnly) { Deploy-Addon }
if ($Probe -or $ProbeOnly) { Deploy-Probe }

Write-Host ""
Write-Host "Changed or new files: /reload is enough. A brand-new addon folder needs a client restart." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /gmail help   (probe: /mprobe help)" -ForegroundColor Green
