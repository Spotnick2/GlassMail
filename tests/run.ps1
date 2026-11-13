<#
    run.ps1 - Syntax-check the addon and the probe, and run every tests\test_*.lua
    under Lua 5.1, through WowTestKit's runner at the commit tests\kit.pin names
    (its README).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev        # the ..\WowTestKit working copy instead of the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# The tests load the library checkouts as they are; CI loads the .pkgmeta pins.
$libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
$libMailbox = if ($env:LIBMAILBOX) { $env:LIBMAILBOX } else { Join-Path (Split-Path -Parent $RepoRoot) "LibMailbox" }
. (Join-Path $RepoRoot "Tools\LibGlassPin.ps1")
if (Test-Path -LiteralPath $libGlass) { Write-LibGlassPinStatus $RepoRoot $libGlass "CI tests the pin" }
if (Test-Path -LiteralPath $libMailbox) { Write-LibGlassPinStatus $RepoRoot $libMailbox "CI tests the pin" "Libs/LibMailbox-1.0" }

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev

# The TOC's files are syntax-checked by the kit (the TOC is the list, so a new
# file cannot go unchecked); the probe's are ours. The embedded library is
# checked in its own repo.
$probe = @(Get-Content (Join-Path $RepoRoot "Tools\MailProbe\MailProbe.toc") | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" } | ForEach-Object { "Tools\MailProbe\$_" })
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassMail.toc" -Extra $probe -Lua $Lua
exit $LASTEXITCODE
