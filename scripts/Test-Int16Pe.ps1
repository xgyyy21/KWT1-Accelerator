param([string]$OutputDirectory='build/int16_pe_2026-11-02_v3',[string]$IcarusBin='..\..\.tools\iverilog\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(Test-Path -LiteralPath $out){throw "Refusing to overwrite $out"}
New-Item -ItemType Directory -Path $out|Out-Null
$iv=Join-Path $root (Join-Path $IcarusBin 'iverilog.exe')
$vvp=Join-Path $root (Join-Path $IcarusBin 'vvp.exe')
$img=Join-Path $out 'int16_pe.vvp'
$args=@('-g2012','-Wall','-s','int16_pe_mac_tb','-o',$img,'-c',(Join-Path $root 'rtl/int16_pe_files.f'),(Join-Path $root 'tb/int16_pe_mac_tb.sv'))
('iverilog '+($args -join ' ')),('vvp '+$img)|Set-Content -Encoding UTF8 (Join-Path $out 'commands.txt')
@('rtl/int16_pe_mac.sv','rtl/int16_pe_files.f','tb/int16_pe_mac_tb.sv','scripts/Test-Int16Pe.ps1')|ForEach-Object{$p=Join-Path $root $_;[pscustomobject]@{Path=$_;Bytes=(Get-Item $p).Length;SHA256=(Get-FileHash $p -Algorithm SHA256).Hash}}|Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out 'source_manifest.csv')
$old=$ErrorActionPreference;$ErrorActionPreference='Continue'
&$iv @args 2>&1|ForEach-Object{$_.ToString()}|Set-Content -Encoding UTF8 (Join-Path $out 'compile.log');$ce=$LASTEXITCODE
if($ce -eq 0){&$vvp $img 2>&1|ForEach-Object{$_.ToString()}|Tee-Object -FilePath (Join-Path $out 'simulation.log');$se=$LASTEXITCODE}else{$se=$null}
$ErrorActionPreference=$old
$pass=($ce -eq 0) -and ($se -eq 0) -and (Select-String -LiteralPath (Join-Path $out 'simulation.log') -Pattern '^PASS int16_pe_mac_tb' -Quiet)
[ordered]@{Created=(Get-Date).ToString('o');CompileExitCode=$ce;SimulationExitCode=$se;Passed=$pass;Contract='signed int16 A/B; signed int32 product; signed int48 accumulator; signed int32 bias; nearest-ties-away right shift; saturating int16 output';K=64;KTile=32;PeCountNextArray=16;AdapterUsed=$false}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'status.json')
Get-ChildItem $out -File|Where-Object Name -ne 'SHA256.csv'|ForEach-Object{[pscustomobject]@{Path=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}}|Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out 'SHA256.csv')
if(!$pass){throw 'INT16 PE regression failed'}
