param(
  [Parameter(Mandatory=$true)][string]$PreparedDirectory,
  [string]$OutputDirectory='build/int16_quantized_data_run',
  [string]$IcarusBin='..\..\.tools\iverilog\bin'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$prepared=[IO.Path]::GetFullPath((Join-Path $root $PreparedDirectory))
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(!(Test-Path -LiteralPath $prepared)){throw "Prepared input directory not found: $prepared"}
if(Test-Path -LiteralPath $out){throw "Refusing to overwrite $out"}
New-Item -ItemType Directory -Path $out|Out-Null
$manifest=Get-Content -LiteralPath (Join-Path $prepared 'prepared_manifest.json') -Raw|ConvertFrom-Json
$dims=$manifest.dimensions
$iv=Join-Path $root (Join-Path $IcarusBin 'iverilog.exe')
$vvp=Join-Path $root (Join-Path $IcarusBin 'vvp.exe')
$image=Join-Path $out 'int16_quantized_data.vvp'
$args=@('-g2012','-Wall','-s','int16_quantized_data_tb','-o',$image,'-c',
  (Join-Path $root 'rtl/files.f'),(Join-Path $root 'tb/int16_quantized_data_tb.sv'))
$old=$ErrorActionPreference;$ErrorActionPreference='Continue'
&$iv @args 2>&1|ForEach-Object{$_.ToString()}|Set-Content -Encoding UTF8 (Join-Path $out 'compile.log')
$compileExit=$LASTEXITCODE
if($compileExit-eq 0){
  $plus=@("+m=$($dims.m)","+k=$($dims.k)","+n=$($dims.n)",
    "+shift=$($manifest.out_shift)",
    "+a=$(Join-Path $prepared 'a_int16.mem')",
    "+b=$(Join-Path $prepared 'b_int16.mem')",
    "+bias=$(Join-Path $prepared 'bias_int32.mem')",
    "+expected=$(Join-Path $prepared 'expected_int16.mem')")
  & $vvp $image @plus 2>&1|ForEach-Object{$_.ToString()}|Tee-Object -FilePath (Join-Path $out 'simulation.log')
  $simulationExit=$LASTEXITCODE
}else{$simulationExit=$null}
$ErrorActionPreference=$old
$pass=($compileExit-eq 0)-and($simulationExit-eq 0)-and
  (Select-String -LiteralPath (Join-Path $out 'simulation.log') -Pattern '^PASS int16_quantized_data_tb' -Quiet)
[ordered]@{CompileExitCode=$compileExit;SimulationExitCode=$simulationExit;Passed=$pass;
  PreparedManifest=(Join-Path $PreparedDirectory 'prepared_manifest.json');
  ActiveFilelist='rtl/files.f';Testbench='tb/int16_quantized_data_tb.sv'}|
  ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'status.json')
if(!$pass){throw 'INT16 quantized-data regression failed'}
