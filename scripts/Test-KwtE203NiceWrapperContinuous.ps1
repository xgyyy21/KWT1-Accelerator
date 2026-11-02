param(
    [string]$OutputDirectory = 'build/kwt_e203_wrapper_continuous_2026-11-02_v1',
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
$sources = @((Get-Content -LiteralPath (Join-Path $projectRoot 'rtl/files.f') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and !$_.StartsWith('//') }))
$sources += @('rtl/files.f','tb/kwt1_e203_nice_wrapper_continuous_tb.sv',
              'scripts/Test-KwtE203NiceWrapperContinuous.ps1')
$sources = @($sources | Sort-Object -Unique)
$manifest = foreach ($relative in $sources) {
    $path = Join-Path $projectRoot $relative
    [pscustomobject]@{Path=$relative;Bytes=(Get-Item $path).Length;SHA256=(Get-FileHash $path -Algorithm SHA256).Hash}
}
$manifest | Export-Csv (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
$image=Join-Path $outPath 'kwt1_e203_nice_wrapper_continuous_tb.vvp'
$args=@('-g2012','-Wall','-s','kwt1_e203_nice_wrapper_continuous_tb','-o',$image,
    '-c',(Join-Path $projectRoot 'rtl/files.f'),
    (Join-Path $projectRoot 'tb/kwt1_e203_nice_wrapper_continuous_tb.sv'))
$oldErrorAction=$ErrorActionPreference; $ErrorActionPreference='Continue'
$compileOutput=& $iverilog @args 2>&1
$compileExit=$LASTEXITCODE; $simExit=$null
$compileOutput | ForEach-Object { $_.ToString() } | Out-File (Join-Path $outPath 'compile.log') -Encoding UTF8
if($compileExit -eq 0){ $simulationOutput=& $vvp $image 2>&1; $simExit=$LASTEXITCODE; $simulationOutput | ForEach-Object { $_.ToString() } | Out-File (Join-Path $outPath 'simulation.log') -Encoding UTF8 }
$ErrorActionPreference=$oldErrorAction
$text=if(Test-Path (Join-Path $outPath 'simulation.log')){Get-Content (Join-Path $outPath 'simulation.log') -Raw}else{''}
$passed=$compileExit -eq 0 -and $simExit -eq 0 -and $text -match 'PASS kwt1_e203_nice_wrapper_continuous_tb'
[ordered]@{Test='kwt1_e203_nice_wrapper_continuous_tb';Passed=$passed;CompileExitCode=$compileExit;SimulationExitCode=$simExit;CompileCommand=('iverilog '+($args -join ' '));SimulationCommand=('vvp '+$image);Scope='Standalone E203-shaped adapter, two jobs without reset or SRAM clear';NotCovered=@('real E203 CPU/SoC','server decoder','vendor SRAM timing','synthesis/STA')} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $outPath 'status.json') -Encoding UTF8
Get-ChildItem $outPath -File | Where-Object Name -ne 'evidence_sha256.csv' | Sort-Object Name | ForEach-Object {[pscustomobject]@{Path=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}} | Export-Csv (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
Get-Content (Join-Path $outPath 'simulation.log') -ErrorAction SilentlyContinue
if(!$passed){throw 'Continuous NICE wrapper test failed.'}
