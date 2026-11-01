param(
    [string]$OutputDirectory = 'build/kwt_shared_sram_loader_2026-11-01_v1',
    [string]$IcarusBin = '..\..\.tools\iverilog\bin'
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
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) { throw "Icarus/vvp missing under $IcarusBin" }
New-Item -ItemType Directory -Path $outPath | Out-Null
$image = Join-Path $outPath 'kwt_shared_sram_loader_tb.vvp'
$compileArgs = @('-g2012','-Wall','-s','kwt_shared_sram_loader_tb','-o',$image,
    '-c',(Join-Path $projectRoot 'rtl/files.f'),
    (Join-Path $projectRoot 'tb/kwt_shared_sram_loader_tb.sv'))
$compileCommand = 'iverilog ' + ($compileArgs -join ' ')
$compileCommand | Set-Content -LiteralPath (Join-Path $outPath 'commands.txt') -Encoding UTF8
$oldErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$compileOutput = & $iverilog @compileArgs 2>&1
$compileExit = $LASTEXITCODE
$compileOutput | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath (Join-Path $outPath 'compile.log') -Encoding UTF8
$ErrorActionPreference = $oldErrorAction
if ($compileExit -ne 0) { throw "Icarus compile failed with exit code $compileExit" }
('vvp ' + $image) | Add-Content -LiteralPath (Join-Path $outPath 'commands.txt') -Encoding UTF8
$ErrorActionPreference = 'Continue'
$simulationOutput = & $vvp $image 2>&1
$simulationExit = $LASTEXITCODE
$simulationOutput | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $outPath 'simulation.log')
$ErrorActionPreference = $oldErrorAction
if ($simulationExit -ne 0) { throw "vvp failed with exit code $simulationExit" }
$status = [ordered]@{
    Created = (Get-Date).ToString('o')
    CompileExitCode = $compileExit
    SimulationExitCode = $simulationExit
    Passed = $true
    Scope = 'Protocol-level platform loader model followed by 16-bit System Bus matrix load/compute/writeback'
    E203Integrated = $false
    RealSramMacro = $false
    Note = 'The loader writes the behavioral shared-memory model before START; it is not a real E203/NICE simulation.'
}
$status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
Get-ChildItem -LiteralPath $outPath -File | Where-Object Name -ne 'evidence_sha256.csv' | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ Path = $_.Name; Bytes = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
} | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Evidence: $outPath"
