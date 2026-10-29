param(
    [string]$OutputDirectory = 'build/sram_macro_adapter_2026-10-28_v1',
    [string]$IcarusBin = '.tools/iverilog/bin'
)
$ErrorActionPreference = 'Stop'
function Invoke-LoggedTool {
    param([string]$Executable, [string[]]$ToolArguments, [string]$LogPath, [switch]$ShowOutput)
    # PS 5.1 wraps native stderr in ErrorRecord; retain the actual tool text.
    $ErrorActionPreference = 'Continue'
    $toolOutput = & $Executable @ToolArguments 2>&1
    $toolExitCode = $LASTEXITCODE
    $lines = @($toolOutput | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
        else { $_.ToString() }
    })
    $lines | Out-File -LiteralPath $LogPath -Encoding UTF8
    if ($ShowOutput) { $lines | ForEach-Object { Write-Host $_ } }
    return $toolExitCode
}
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $outPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
    if (!$outPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputDirectory must resolve inside the project directory.'
    }
    New-Item -ItemType Directory -Path $outPath -Force | Out-Null
    $iverilog = Join-Path $IcarusBin 'iverilog.exe'
    $vvp = Join-Path $IcarusBin 'vvp.exe'
    if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) {
        throw 'Icarus/vvp not found. Supply -IcarusBin with their directory.'
    }
    $sources = @(
        'rtl/sram_1024x16_adapter.sv',
        'rtl/sram_fp32_cache_adapter.sv',
        'tb/support/ramsp128x16_functional_model.sv',
        'tb/sram_fp32_cache_adapter_tb.sv'
    )
    $evidenceSources = $sources + @(
        'rtl/sram_fp32_cache_adapter.f',
        'scripts/Test-SramMacroAdapter.ps1'
    )
    # Keep this script ASCII-compatible with Windows PowerShell 5.1.
    $evidenceSources += Get-ChildItem -LiteralPath 'handoff' -Filter 'SRAM*2026-10-28.md' |
        ForEach-Object { 'handoff/' + $_.Name }
    $manifest = foreach ($path in $evidenceSources) {
        $item = Get-Item -LiteralPath $path
        [pscustomobject]@{ Path = $path; Bytes = $item.Length; SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    }
    $manifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
    $null = Invoke-LoggedTool -Executable $iverilog -ToolArguments @('-V') -LogPath (Join-Path $outPath 'iverilog_version.log')
    $null = Invoke-LoggedTool -Executable $vvp -ToolArguments @('-V') -LogPath (Join-Path $outPath 'vvp_version.log')
    $imagePath = Join-Path $outPath 'sram_macro_adapter.vvp'
    $tracePath = Join-Path $outPath 'sram_access_trace.csv'
    $compileArgs = @('-g2012', '-Wall', '-s', 'sram_fp32_cache_adapter_tb', '-o', $imagePath) + $sources
    $commandRecord = @(
        ('Working directory: ' + $projectRoot),
        ('iverilog ' + ($compileArgs -join ' ')),
        ('vvp ' + $imagePath + ' +trace=' + $tracePath)
    )
    $commandRecord | Set-Content -LiteralPath (Join-Path $outPath 'commands.log') -Encoding UTF8
    $compileExit = Invoke-LoggedTool -Executable $iverilog -ToolArguments $compileArgs -LogPath (Join-Path $outPath 'compile.log') -ShowOutput
    $runExit = $null
    if ($compileExit -eq 0) {
        $runExit = Invoke-LoggedTool -Executable $vvp -ToolArguments @($imagePath, "+trace=$tracePath") -LogPath (Join-Path $outPath 'simulation.log') -ShowOutput
    }
    $passFound = $false
    if ($null -ne $runExit -and $runExit -eq 0) {
        $passFound = [bool](Select-String -LiteralPath (Join-Path $outPath 'simulation.log') -Pattern '^PASS sram_fp32_cache_adapter ' -Quiet)
    }
    $status = [ordered]@{
        Scope = 'New SRAM macro-pin adapters with project-authored functional models only'
        CompileExitCode = $compileExit
        SimulationExitCode = $runExit
        PassMarkerFound = $passFound
        ExistingComputePathIntegrated = $false
        VendorTimingModelUsed = $false
    }
    $status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
    $outputs = Get-ChildItem -LiteralPath $outPath -File | Where-Object Name -ne 'evidence_sha256.csv'
    $outputs | ForEach-Object {
        [pscustomobject]@{ File = $_.Name; Bytes = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    } | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
    if ($compileExit -ne 0 -or !$passFound) { throw "SRAM adapter test failed; inspect $outPath" }
    Write-Host "SRAM adapter targeted simulation passed. Evidence: $outPath"
} finally {
    Pop-Location
}
