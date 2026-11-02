param(
    [string]$OutputDirectory = 'build/sram_adapter_functional_2026-11-02_v1',
    [string]$IcarusBin = '.tools/iverilog/bin'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
if (!$outPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory must be inside project.' }
if (Test-Path -LiteralPath $outPath) { throw "Refusing to overwrite evidence: $outPath" }
$iverilog = Join-Path $projectRoot (Join-Path $IcarusBin 'iverilog.exe')
$vvp = Join-Path $projectRoot (Join-Path $IcarusBin 'vvp.exe')
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) { throw 'Icarus/vvp missing.' }
New-Item -ItemType Directory -Path $outPath | Out-Null
$sources = @('rtl/sram_1024x16_adapter.sv','tb/support/ramsp128x16_functional_model.sv',
             'tb/sram_1024x16_adapter_functional_tb.sv','scripts/Test-SramAdapterFunctional.ps1')
$manifest = foreach ($relative in $sources) {
    $path = Join-Path $projectRoot $relative
    [pscustomobject]@{Path=$relative;Bytes=(Get-Item $path).Length;SHA256=(Get-FileHash $path -Algorithm SHA256).Hash}
}
$manifest | Export-Csv (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
$image=Join-Path $outPath 'sram_1024x16_adapter_functional_tb.vvp'
$args=@('-g2012','-Wall','-s','sram_1024x16_adapter_functional_tb','-o',$image,
    (Join-Path $projectRoot $sources[0]),(Join-Path $projectRoot $sources[1]),(Join-Path $projectRoot $sources[2]))
$oldErrorAction=$ErrorActionPreference; $ErrorActionPreference='Continue'
$compileOutput=& $iverilog @args 2>&1
$compileExit=$LASTEXITCODE; $simExit=$null
$compileOutput | ForEach-Object { $_.ToString() } | Out-File (Join-Path $outPath 'compile.log') -Encoding UTF8
if($compileExit -eq 0){ $simulationOutput=& $vvp $image 2>&1; $simExit=$LASTEXITCODE; $simulationOutput | ForEach-Object { $_.ToString() } | Out-File (Join-Path $outPath 'simulation.log') -Encoding UTF8 }
$ErrorActionPreference=$oldErrorAction
$text=if(Test-Path (Join-Path $outPath 'simulation.log')){Get-Content (Join-Path $outPath 'simulation.log') -Raw}else{''}
$passed=$compileExit -eq 0 -and $simExit -eq 0 -and $text -match 'PASS sram_1024x16_adapter_functional_tb'
[ordered]@{Test='sram_1024x16_adapter_functional_tb';Passed=$passed;CompileExitCode=$compileExit;SimulationExitCode=$simExit;CompileCommand=('iverilog '+($args -join ' '));SimulationCommand=('vvp '+$image);Scope='Behavioral SRAM macro model; no vendor timing';NotCovered=@('vendor macro timing','PPA','E203 integration')} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $outPath 'status.json') -Encoding UTF8
Get-ChildItem $outPath -File | Where-Object Name -ne 'evidence_sha256.csv' | Sort-Object Name | ForEach-Object {[pscustomobject]@{Path=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}} | Export-Csv (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
Get-Content (Join-Path $outPath 'simulation.log') -ErrorAction SilentlyContinue
if(!$passed){throw 'SRAM adapter functional test failed.'}
