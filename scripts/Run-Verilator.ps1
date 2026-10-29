[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
    [string]$Top = 'verilator_environment_smoke_tb',
    [string]$SourceRoot = '',
    [ValidateRange(1, 8)]
    [int]$Jobs = 2
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $SourceRoot) {
    if ($Top -eq 'verilator_environment_smoke_tb') {
        $SourceRoot = $projectRoot
    } else {
        throw 'Specify -SourceRoot explicitly for project tests; do not silently use an older RTL copy.'
    }
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$bash = Join-Path $projectRoot '.tools\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { throw 'Run scripts/Setup-Verilator.ps1 first.' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$buildDir = Join-Path $projectRoot "build\verilator\${Top}_$stamp"
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git -and (Test-Path -LiteralPath (Join-Path $SourceRoot '.git'))) {
    $revision = & $git.Source -c "safe.directory=$SourceRoot" -C $SourceRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record source Git revision.' }
    $status = & $git.Source -c "safe.directory=$SourceRoot" -C $SourceRoot status --porcelain
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record source Git status.' }
    [string[]]$gitLines = @("HEAD=$revision", 'STATUS:')
    if ($null -ne $status) { $gitLines += [string[]]$status }
    [System.IO.File]::WriteAllLines((Join-Path $buildDir 'source_git.txt'), $gitLines)
}
$shellScript = Join-Path $PSScriptRoot 'run-verilator.sh'
$previousMsystem = $env:MSYSTEM
$previousChere = $env:CHERE_INVOKING
try {
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    & $bash --login ($shellScript -replace '\\', '/') ($SourceRoot -replace '\\', '/') $Top ($buildDir -replace '\\', '/') $Jobs
    $result = $LASTEXITCODE
    if ($result -ne 0) { throw "Verilator build/test failed (exit $result). Evidence: $buildDir" }
}
finally {
    $env:MSYSTEM = $previousMsystem
    $env:CHERE_INVOKING = $previousChere
}
Write-Host "Verilator build/test succeeded. Evidence: $buildDir"
