param(
    [string]$OutputDirectory = 'build/sram_adapter_pin_contract_2026-10-30_v1',
    [string]$IcarusBin = '.tools/iverilog/bin'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
if (!$outPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must resolve inside the project directory.'
}
if (Test-Path -LiteralPath $outPath) { throw "Refusing to overwrite evidence: $outPath" }
$iverilog = Join-Path $projectRoot (Join-Path $IcarusBin 'iverilog.exe')
$vvp = Join-Path $projectRoot (Join-Path $IcarusBin 'vvp.exe')
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) {
    throw 'Icarus/vvp missing.'
}
New-Item -ItemType Directory -Path $outPath | Out-Null
$sources = @('rtl/sram_1024x16_adapter.sv', 'tb/sram_1024x16_adapter_pin_tb.sv')
$sourceManifest = foreach ($relative in $sources) {
    $path = Join-Path $projectRoot $relative
    [pscustomobject]@{ Path = $relative; Bytes = (Get-Item -LiteralPath $path).Length;
        SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$sourceManifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') `
    -NoTypeInformation -Encoding UTF8
$toolVersion = (& $iverilog -V 2>&1 | Select-Object -First 1).ToString()
$image = Join-Path $outPath 'sram_1024x16_adapter_pin_tb.vvp'
$compileLog = Join-Path $outPath 'compile.log'
$simulationLog = Join-Path $outPath 'simulation.log'
$compileArgs = @('-g2012', '-Wall', '-s', 'sram_1024x16_adapter_pin_tb',
    '-o', $image, (Join-Path $projectRoot $sources[0]),
    (Join-Path $projectRoot $sources[1]))
& $iverilog @compileArgs 2>&1 | Out-File -LiteralPath $compileLog -Encoding UTF8
$compileExit = $LASTEXITCODE
$simulationExit = $null
if ($compileExit -eq 0) {
    & $vvp $image 2>&1 | Out-File -LiteralPath $simulationLog -Encoding UTF8
    $simulationExit = $LASTEXITCODE
}
$logText = if (Test-Path -LiteralPath $simulationLog) {
    Get-Content -LiteralPath $simulationLog -Raw
} else { '' }
$passed = ($compileExit -eq 0 -and $simulationExit -eq 0 -and
    $logText -match 'PASS sram_1024x16_adapter_pin_tb')
$status = [ordered]@{
    Test = 'sram_1024x16_adapter_pin_tb'
    Passed = $passed
    CompileExitCode = $compileExit
    SimulationExitCode = $simulationExit
    IcarusVersion = $toolVersion
    CompileCommand = ('iverilog ' + ($compileArgs -join ' '))
    SimulationCommand = ('vvp ' + $image)
    Scope = 'Address decode, macro control pins, request gating and control protocol only'
    NotCovered = @('Vendor SRAM timing/model behavior', 'Q update/hold/data correctness',
                   'EMAW encoding legality', 'Retention transitions', 'E203 integration')
}
$status | ConvertTo-Json -Depth 5 | Set-Content `
    -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
Get-ChildItem -LiteralPath $outPath -File | Where-Object Name -ne 'evidence_sha256.csv' |
    Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Path = $_.Name; Bytes = $_.Length;
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    } | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') `
        -NoTypeInformation -Encoding UTF8
Get-Content -LiteralPath $compileLog
Get-Content -LiteralPath $simulationLog -ErrorAction SilentlyContinue
if (!$passed) { throw 'SRAM adapter pin/control contract test failed.' }
