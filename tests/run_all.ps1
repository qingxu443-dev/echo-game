param(
    [string]$Godot = ""
)

# Runs every headless suite and prints one summary line.
#   .\tests\run_all.ps1
#   .\tests\run_all.ps1 -Godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
# Engine resolution order: -Godot argument, $env:ECHO_GODOT, a godot on PATH.
# Exit code is 0 only when every suite reported failures=0, none crashed and
# the assertion total did not drop below the BASELINE.md declaration.

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

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
& $Godot --headless --path . --import *> $null

$total = 0
$failures = 0
$broken = 0
$suites = 0

foreach ($file in Get-ChildItem "tests\test_*.gd" | Sort-Object Name) {
    $name = $file.BaseName
    $out = & $Godot --headless --path . --script "res://tests/$name.gd" 2>&1 | Out-String
    $match = [regex]::Match($out, "RESULT \S+ assertions=(\d+) failures=(\d+)")
    $suites++

    if (-not $match.Success) {
        Write-Host ("{0,-38} NO RESULT (crashed or failed to parse)" -f $name)
        $broken++
        continue
    }

    $assertions = [int]$match.Groups[1].Value
    $failed = [int]$match.Groups[2].Value
    $total += $assertions
    $failures += $failed

    if ($failed -eq 0) {
        Write-Host ("{0,-38} {1,3} ok" -f $name, $assertions)
    } else {
        Write-Host ("{0,-38} {1,3} FAIL({2})" -f $name, $assertions, $failed)
    }
}

Write-Host "-----"
Write-Host ("suites={0} assertions={1} failures={2} broken={3}" -f $suites, $total, $failures, $broken)

if ($failures -ne 0 -or $broken -ne 0) { exit 1 }

# Guard against silent coverage loss, mirroring run_all.sh: a suite that
# aborts part-way (a call to a removed method, for instance) still exits 0 and
# still reports failures=0 - the only evidence is that fewer assertions ran.
# Compare against the declared baseline to catch that.
$baselinePath = "docs\engineering\BASELINE.md"
if (Test-Path $baselinePath) {
    $baseline = Get-Content $baselinePath -Encoding UTF8 -Raw
    $declared = [regex]::Match($baseline, "断言总数.*?\*\*(\d+)\*\*")
    if ($declared.Success -and $total -lt [int]$declared.Groups[1].Value) {
        Write-Host ("coverage dropped: {0} assertions ran, baseline declares at least {1}" -f $total, $declared.Groups[1].Value)
        Write-Host "If the drop is intended, update docs/engineering/BASELINE.md and record why."
        exit 1
    }
}
exit 0
