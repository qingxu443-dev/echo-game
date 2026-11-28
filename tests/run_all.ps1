param(
    [string]$Godot = "",
    [switch]$Fix
)

# Runs every headless suite and prints one summary line.
#   .\tests\run_all.ps1
#   .\tests\run_all.ps1 -Godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#   .\tests\run_all.ps1 -Fix          # rewrite stale line counts in the docs
# Engine resolution order: -Godot argument, $env:ECHO_GODOT, a godot on PATH.
#
# The checks themselves live in tests/run_suites.gd, which is also what run_all.sh
# starts, so both platforms run the same code. Mirroring the bash logic here is
# what let this file fall behind: it was missing the SCRIPT ERROR guard and the
# documentation check, so a Windows run could report all-green after a suite had
# aborted half way through.
#
# Exit code is 0 only when every suite reported failures=0, none aborted, the
# assertion total did not drop below the BASELINE.md declaration, and the
# documents agree with it.

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Godot resolves user:// from %APPDATA% on Windows. Point it at a throwaway
# directory so a developer's real saves cannot change assertion numbers; CI
# already starts from a clean profile, and this makes local runs match it.
$testDataRoot = Join-Path ([System.IO.Path]::GetTempPath()) "echo-test-user-data"
$env:APPDATA = Join-Path $testDataRoot "appdata"
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null

if ($Godot -eq "" -and $env:ECHO_GODOT) { $Godot = $env:ECHO_GODOT }
if ($Godot -eq "") {
    $fallback = Get-Command godot -ErrorAction SilentlyContinue
    if ($fallback) { $Godot = $fallback.Source }
}
if ($Godot -eq "" -or -not (Test-Path $Godot)) {
    Write-Host "Godot not found. Pass -Godot <path>, set `$env:ECHO_GODOT, or put godot on PATH."
    exit 2
}

# Generating the .godot cache first is what the onboarding note asks for:
# without it, suites that read .tres files report "crashed or failed to parse"
# on a fresh clone. CI runs the same step before the suites.
& $Godot --headless --path . --import
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$runnerArgs = @("--headless", "--path", ".", "--script", "res://tests/run_suites.gd")
if ($Fix) { $runnerArgs += @("--", "--fix") }
& $Godot @runnerArgs
exit $LASTEXITCODE
