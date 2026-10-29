[CmdletBinding()]
param(
    [switch]$DownloadOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $projectRoot '.tools'
$msysRoot = Join-Path $toolsDir 'msys64'
$archive = Join-Path $toolsDir 'msys2-base-x86_64-20260927.tar.xz'
$downloadUrl = 'https://mirrors.bfsu.edu.cn/msys2/distrib/x86_64/msys2-base-x86_64-20260927.tar.xz'
# Published SHA-256 and byte size from the official GitHub asset metadata.
# Official release tag: 2026-09-27. Do not silently accept a new hash.
$expectedHash = 'ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322'
$expectedBytes = 42860696L

New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
$drive = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($projectRoot))
if ($drive.AvailableFreeSpace -lt 6GB) {
    throw 'Less than 6 GiB free. Stop before downloading or installing.'
}

if (-not (Test-Path -LiteralPath $archive)) {
    $partial = "$archive.$([guid]::NewGuid().ToString('N')).partial"
    & curl.exe -fL --connect-timeout 20 --max-time 600 --retry 2 --output $partial $downloadUrl
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 download failed: exit $LASTEXITCODE" }
    if ((Get-Item -LiteralPath $partial).Length -ne $expectedBytes) {
        throw 'Downloaded archive size differs from the reviewed official asset.'
    }
    if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        throw 'Downloaded archive SHA-256 differs from the reviewed official asset.'
    }
    Move-Item -LiteralPath $partial -Destination $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw "Archive verification failed: $archive"
}
Write-Host "Verified MSYS2 archive: $archive"
if ($DownloadOnly) { return }

if (-not (Test-Path -LiteralPath $msysRoot)) {
    & tar.exe -xJf $archive -C $toolsDir
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 extraction failed: exit $LASTEXITCODE" }
}
$bash = Join-Path $msysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) { throw 'MSYS2 extraction is incomplete.' }
$pacmanConfig = (Join-Path $PSScriptRoot 'verilator-pacman.conf') -replace '\\', '/'

$previousMsystem = $env:MSYSTEM
$previousChere = $env:CHERE_INVOKING
try {
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    & $bash --login -c 'exit 0'
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 initialization failed: exit $LASTEXITCODE" }
    # Use separate shell invocations so core runtime updates can take effect.
    & $bash --login -c 'pacman --config "$1" -Syu --noconfirm' setup $pacmanConfig
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 system update failed: exit $LASTEXITCODE" }
    & $bash --login -c 'pacman --config "$1" -Syu --noconfirm' setup $pacmanConfig
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 second update failed: exit $LASTEXITCODE" }
    & $bash --login -c 'pacman --config "$1" -S --needed --noconfirm mingw-w64-ucrt-x86_64-verilator mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-python make' setup $pacmanConfig
    if ($LASTEXITCODE -ne 0) { throw "Verilator dependency installation failed: exit $LASTEXITCODE" }
    & $bash --login -c 'set -e; verilator --version; g++ --version; make --version; python3 --version'
    if ($LASTEXITCODE -ne 0) { throw "Toolchain check failed: exit $LASTEXITCODE" }
}
finally {
    $env:MSYSTEM = $previousMsystem
    $env:CHERE_INVOKING = $previousChere
}
Write-Host 'Local toolchain installed. No system PATH or Windows installation registry changes requested.'
