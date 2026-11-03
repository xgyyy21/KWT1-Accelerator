param([string]$OutputDirectory='build/int16_accelerator_2026-11-02_v4',[string]$IcarusBin='..\..\.tools\iverilog\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(Test-Path -LiteralPath $out){throw "Refusing to overwrite $out"}
New-Item -ItemType Directory -Path $out|Out-Null
$iv=Join-Path $root (Join-Path $IcarusBin 'iverilog.exe')
$vvp=Join-Path $root (Join-Path $IcarusBin 'vvp.exe')
$img=Join-Path $out 'int16_accelerator.vvp'
$args=@('-g2012','-Wall','-s','int16_accelerator_top_tb','-o',$img,'-c',(Join-Path $root 'rtl/files.f'),(Join-Path $root 'tb/int16_accelerator_top_tb.sv'))
$old=$ErrorActionPreference;$ErrorActionPreference='Continue'
&$iv @args 2>&1|ForEach-Object{$_.ToString()}|Set-Content -Encoding UTF8 (Join-Path $out 'compile.log');$ce=$LASTEXITCODE
if($ce -eq 0){&$vvp $img 2>&1|ForEach-Object{$_.ToString()}|Tee-Object -FilePath (Join-Path $out 'simulation.log');$se=$LASTEXITCODE}else{$se=$null}
$ErrorActionPreference=$old
$pass=($ce -eq 0)-and($se -eq 0)-and(Select-String -LiteralPath (Join-Path $out 'simulation.log') -Pattern '^PASS int16_accelerator_top_tb K64_and_K256' -Quiet)
$sources=@('rtl/files.f','rtl/int16_pe_mac.sv','rtl/int16_pe_array_16.sv','rtl/int16_system_bus_control.sv','rtl/int16_accelerator_top.sv','tb/int16_accelerator_top_tb.sv','scripts/Test-Int16Accelerator.ps1')
$sources|ForEach-Object{$p=Join-Path $root $_;[pscustomobject]@{Path=$_;Bytes=(Get-Item $p).Length;SHA256=(Get-FileHash $p -Algorithm SHA256).Hash}}|Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out 'source_manifest.csv')
[ordered]@{CompileExitCode=$ce;SimulationExitCode=$se;Passed=$pass;ActiveDatatype='INT16';PeCount=16;AccumulatorBits=48;SystemBusBits=32;KTile=32;TestedK=@(64,256);ContinuousJobs=2;Fp32InActiveFilelist=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'status.json')
if(!$pass){throw 'INT16 accelerator regression failed'}
