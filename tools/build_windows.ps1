param(
    [string]$Godot = $env:ECHO_GODOT,
    [string]$Template = "",
    [string]$OutputDir = "build/windows"
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This entry point validates a Windows executable on Windows.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$buildDir = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDir))
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$logs = Join-Path $buildDir 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$manifestPath = Join-Path $buildDir 'manifest.json'
# A failed rerun must never leave an earlier success manifest beside its output.
if (Test-Path -LiteralPath $manifestPath) { [IO.File]::Delete($manifestPath) }
if (-not $Godot) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $Godot = $command.Source }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) { throw 'Pass -Godot <Godot 4.7.2 console executable>.' }
$Godot = (Resolve-Path -LiteralPath $Godot).Path
$version = (& $Godot --headless --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $version.StartsWith('4.7.2.stable')) { throw "Wrong Godot version: $version" }
if (-not $Template) { $Template = Join-Path $repoRoot '.godot/export_templates/4.7.2.stable/windows_release_x86_64.exe' }
if (-not (Test-Path -LiteralPath $Template)) { throw 'Run python tools/fetch_windows_template.py or pass -Template <matching release template>.' }
$Template = (Resolve-Path -LiteralPath $Template).Path
$templateHash = (Get-FileHash -LiteralPath $Template -Algorithm SHA256).Hash.ToLowerInvariant()
if ($templateHash -ne 'd34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562') { throw 'Template does not match the pinned Standard Windows release build.' }
$oldAppData = $env:APPDATA
$presetPath = Join-Path $repoRoot 'export_presets.cfg'
$presetBytes = [IO.File]::ReadAllBytes($presetPath)

function Invoke-BuildStep([string]$Name, [string]$Executable, [string[]]$Arguments) {
    $log = Join-Path $logs ($Name + '.log')
    & $Executable @Arguments *> $log
    $code = $LASTEXITCODE
    if ($code -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|^ERROR:' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 30 | Write-Output
        throw "Build step $Name failed (exit $code); see $log"
    }
    Write-Output "$Name : ok"
}

try {
    $env:APPDATA = Join-Path $repoRoot '.godot/build-profile'
    Invoke-BuildStep 'import' $Godot @('--headless', '--path', $repoRoot, '--import')
    Invoke-BuildStep 'suites' $Godot @('--headless', '--path', $repoRoot, '--script', 'res://tests/run_suites.gd')
    $preset = [Text.Encoding]::UTF8.GetString($presetBytes)
    $templateLiteral = ConvertTo-Json -InputObject ($Template.Replace('\', '/')) -Compress
    $preset = [regex]::Replace($preset, '(?m)^custom_template/release=.*$', [Text.RegularExpressions.MatchEvaluator]{ param($match) 'custom_template/release=' + $templateLiteral })
    [IO.File]::WriteAllText($presetPath, $preset, [Text.UTF8Encoding]::new($false))
    $executable = Join-Path $buildDir 'ECHO_Windows_x64.exe'
    Invoke-BuildStep 'export' $Godot @('--headless', '--path', $repoRoot, '--export-release', 'Windows Desktop', $executable)
    $probe = Join-Path $repoRoot '.godot/package-probe'
    New-Item -ItemType Directory -Path $probe -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $probe 'project.godot'), "config_version=5`n[application]`nconfig/name=`"ECHO Package Inspector`"`n")
    $contentsPath = Join-Path $buildDir 'package-content.json'
    Invoke-BuildStep 'contents' $Godot @('--headless', '--path', $probe, '--script', (Join-Path $PSScriptRoot 'inspect_windows_package.gd'), '--', $executable, $contentsPath)
    Invoke-BuildStep 'smoke' $executable @('--headless', '--audio-driver', 'Dummy', '--quit-after', '30')
    [IO.File]::WriteAllBytes($presetPath, $presetBytes)
    $sourceSha = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
    $dirty = @(git status --porcelain).Count -gt 0
    $content = Get-Content -LiteralPath $contentsPath -Raw | ConvertFrom-Json
    $manifest = [ordered]@{
        source_commit = $sourceSha; source_dirty = $dirty; engine = $version
        template_sha256 = $templateHash; package_files = $content.count
        executable = 'ECHO_Windows_x64.exe'
        sha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        checks = @('import', 'all suites and guards', 'release export', 'package exclusions', 'headless executable smoke')
        manual_validation = 'pending: interaction, full runs, performance and release acceptance'
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/engineering/WINDOWS_PLAYTEST_README.txt') -Destination (Join-Path $buildDir 'README.txt') -Force
    $archive = Join-Path $buildDir 'ECHO_Windows_x64.zip'
    Compress-Archive -LiteralPath $executable, $manifestPath, $contentsPath, (Join-Path $buildDir 'README.txt'), $logs -DestinationPath $archive -Force
    Write-Output "WINDOWS_BUILD_OK $executable"
} catch {
    if (Test-Path -LiteralPath $manifestPath) { [IO.File]::Delete($manifestPath) }
    throw
} finally {
    [IO.File]::WriteAllBytes($presetPath, $presetBytes)
    $env:APPDATA = $oldAppData
}
