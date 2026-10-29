param(
    [string]$OutputDirectory = 'build/sram_compute_integration_2026-10-28_v2',
    [string]$IcarusBin = '.tools/iverilog/bin'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
if (!$outPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must resolve inside the project directory.'
}
if (Test-Path -LiteralPath $outPath) { throw "Refusing to overwrite evidence: $outPath" }
$iverilog = Join-Path $projectRoot (Join-Path $IcarusBin 'iverilog.exe')
$vvp = Join-Path $projectRoot (Join-Path $IcarusBin 'vvp.exe')
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) { throw 'Icarus/vvp missing.' }
function Invoke-LoggedTool {
    param([string]$Executable, [string[]]$ToolArguments, [string]$LogPath)
    $ErrorActionPreference = 'Continue'
    $toolOutput = & $Executable @ToolArguments 2>&1
    $toolExitCode = $LASTEXITCODE
    $lines = @($toolOutput | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
        else { $_.ToString() }
    })
    $lines | Out-File -LiteralPath $LogPath -Encoding UTF8
    [pscustomobject]@{ ExitCode = $toolExitCode; Lines = $lines }
}
$tests = @(
    'fp32_tile_cache_bridge_tb',
    'fp32_sram_compute_integration_tb',
    'fp32_tile_dma_load_engine_tb',
    'fp32_tile_cache_streamer_tb',
    'fp32_tile_load_compute_tb',
    'fp32_tile_load_compute_8x16_tb',
    'fp32_tile_kblock_load_compute_tb',
    'fp32_tile_kblock_load_compute_k256_tb',
    'fp32_accelerator_top_tb'
)
New-Item -ItemType Directory -Path $outPath | Out-Null
$snapshot = Join-Path $outPath 'sources'
$sources = @(Get-Content -LiteralPath (Join-Path $projectRoot 'rtl/files.f') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and !$_.StartsWith('//') })
$sources += @('rtl/files.f','tb/support/ramsp128x16_functional_model.sv',
              'scripts/Test-SramComputeIntegration.ps1')
$sources += $tests | ForEach-Object { "tb/$_.sv" }
$sourceManifest = foreach ($relative in ($sources | Sort-Object -Unique)) {
    $original = Join-Path $projectRoot $relative
    $copy = Join-Path $snapshot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
    Copy-Item -LiteralPath $original -Destination $copy
    $hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $hash) { throw "Snapshot mismatch: $relative" }
    [pscustomobject]@{ Path = $relative; Bytes = (Get-Item -LiteralPath $copy).Length; SHA256 = $hash }
}
$sourceManifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $snapshot 'run') | Out-Null
Push-Location $snapshot
try {
    $null = Invoke-LoggedTool $iverilog @('-V') (Join-Path $outPath 'iverilog_version.log')
    $null = Invoke-LoggedTool $vvp @('-V') (Join-Path $outPath 'vvp_version.log')
    $results = foreach ($test in $tests) {
        $image = "run/$test.vvp"
        # All options precede positional input files for this Windows build.
        $compileArgs = @('-g2012','-s',$test,'-o',$image,'-c','rtl/files.f',
                        'tb/support/ramsp128x16_functional_model.sv',"tb/$test.sv")
        $runArgs = @($image)
        if ($test -eq 'fp32_sram_compute_integration_tb') { $runArgs += "+trace_dir=$outPath" }
        $compile = Invoke-LoggedTool $iverilog $compileArgs (Join-Path $outPath "$test.compile.log")
        $simulation = $null
        if ($compile.ExitCode -eq 0) {
            $simulation = Invoke-LoggedTool $vvp $runArgs (Join-Path $outPath "$test.simulation.log")
        }
        $passed = $compile.ExitCode -eq 0 -and $null -ne $simulation -and
            $simulation.ExitCode -eq 0 -and @($simulation.Lines -match '\bPASS\b').Count -gt 0
        $result = [pscustomobject]@{
            Test = $test; Passed = $passed; CompileExitCode = $compile.ExitCode
            SimulationExitCode = $(if ($null -ne $simulation) { $simulation.ExitCode } else { $null })
            CompileCommand = ('iverilog ' + ($compileArgs -join ' '))
            SimulationCommand = ('vvp ' + ($runArgs -join ' '))
        }
        Write-Host "$test Passed=$passed"
        if ($null -ne $simulation) { $simulation.Lines | ForEach-Object { Write-Host $_ } }
        $result
    }
    $status = [ordered]@{
        Created = (Get-Date).ToString('o'); WorkingDirectory = $snapshot
        Scope = 'Macro-pin tile compute integration and affected behavioral-cache regressions'
        Tests = @($results); Passed = @($results | Where-Object Passed -eq $true).Count
        Failed = @($results | Where-Object Passed -eq $false).Count
        SourceIdentity = 'Copied local sources; source_manifest.csv fixes identity, not a Git commit'
        VendorTimingModelUsed = $false; E203Integrated = $false
        FullLayerMacroPathTested = $false; SoftwareIndependentReview = $false
    }
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
    Get-ChildItem -LiteralPath $outPath -Recurse -File | Where-Object Name -ne 'evidence_sha256.csv' |
        Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($outPath.Length+1).Replace('\','/')
                Bytes = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
    if ($status.Failed -gt 0) { throw "Regression failures: $($status.Failed). Inspect $outPath" }
    Write-Host "Evidence: $outPath; passed=$($status.Passed); failed=$($status.Failed)"
} finally { Pop-Location }
