param(
    [string]$OutputDirectory = 'build/sram_top_exceptions_2026-10-30_v1',
    [string]$IcarusBin = '.tools/iverilog/bin'
)
$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
if (!$outPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory must be inside project.' }
if (Test-Path -LiteralPath $outPath) { throw "Refusing to overwrite evidence: $outPath" }
$iverilog = Join-Path $projectRoot (Join-Path $IcarusBin 'iverilog.exe')
$vvp = Join-Path $projectRoot (Join-Path $IcarusBin 'vvp.exe')
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) { throw 'Icarus/vvp missing.' }
New-Item -ItemType Directory -Path $outPath | Out-Null
$sources = @('rtl/files.f', 'tb/support/ramsp128x16_functional_model.sv',
             'tb/fp32_sram_top_exception_tb.sv')
$manifest = foreach ($relative in $sources) {
    $source = Join-Path $projectRoot $relative
    [pscustomobject]@{ Path = $relative; Bytes = (Get-Item -LiteralPath $source).Length;
        SHA256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash }
}
$manifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
$image = Join-Path $outPath 'fp32_sram_top_exception_tb.vvp'
$compileArgs = @('-g2012', '-Wall', '-s', 'fp32_sram_top_exception_tb', '-o', $image,
                '-c', (Join-Path $projectRoot 'rtl/files.f'),
                (Join-Path $projectRoot 'tb/support/ramsp128x16_functional_model.sv'),
                (Join-Path $projectRoot 'tb/fp32_sram_top_exception_tb.sv'))
& $iverilog @compileArgs 2>&1 | Out-File -LiteralPath (Join-Path $outPath 'compile.log') -Encoding UTF8
$compileExit = $LASTEXITCODE
$simExit = $null
if ($compileExit -eq 0) {
    & $vvp $image 2>&1 | Out-File -LiteralPath (Join-Path $outPath 'simulation.log') -Encoding UTF8
    $simExit = $LASTEXITCODE
}
$simText = if (Test-Path -LiteralPath (Join-Path $outPath 'simulation.log')) {
    Get-Content -LiteralPath (Join-Path $outPath 'simulation.log') -Raw
} else { '' }
$passed = ($compileExit -eq 0 -and $simExit -eq 0 -and $simText -match 'PASS fp32_sram_top_exception')
$status = [ordered]@{ Test = 'fp32_sram_top_exception_tb'; Passed = $passed;
    CompileExitCode = $compileExit; SimulationExitCode = $simExit;
    CompileCommand = ('iverilog ' + ($compileArgs -join ' '));
    SimulationCommand = ('vvp ' + $image);
    Scope = 'Top-level functional SRAM/bus exception behavior; no E203 or vendor timing';
    PEChanged = $false }
$status | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
Get-ChildItem -LiteralPath $outPath -File | Where-Object Name -ne 'evidence_sha256.csv' |
    Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ Path = $_.Name; Bytes = $_.Length;
        SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
} | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
Get-Content -LiteralPath (Join-Path $outPath 'simulation.log') -ErrorAction SilentlyContinue
if (!$passed) { throw 'Top-level SRAM exception test failed.' }
