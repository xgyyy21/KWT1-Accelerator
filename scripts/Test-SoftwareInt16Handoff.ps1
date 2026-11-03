param(
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [string]$OutputDirectory='build/int16_software_handoff_run',
  [int[]]$Layers=(0..11),
  [switch]$Parallel,
  [string]$IcarusBin='..\..\.tools\iverilog\bin'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$zip=[IO.Path]::GetFullPath($ZipPath)
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(!(Test-Path -LiteralPath $zip -PathType Leaf)){throw "ZIP not found: $zip"}
if(Test-Path -LiteralPath $out){throw "Refusing to overwrite $out"}
New-Item -ItemType Directory -Path $out|Out-Null
$extract=Join-Path $out 'package'
New-Item -ItemType Directory -Path $extract|Out-Null
$archiveHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
  foreach($entry in $archive.Entries){
    $name=$entry.FullName.Replace('\','/')
    if($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)'){
      throw "Unsafe ZIP entry path: $($entry.FullName)"
    }
  }
  [IO.Compression.ZipFile]::ExtractToDirectory($zip,$extract)
} finally {$archive.Dispose()}

$sumPath=Join-Path $extract 'SHA256SUMS.txt'
$checked=0
foreach($line in Get-Content -LiteralPath $sumPath -Encoding UTF8){
  if([string]::IsNullOrWhiteSpace($line)){continue}
  if($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$'){throw "Invalid checksum line: $line"}
  $expectedHash=$matches[1].ToLowerInvariant();$relative=$matches[2].Trim()
  $candidate=Join-Path $extract ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
  if(!(Test-Path -LiteralPath $candidate -PathType Leaf)){throw "Checksum target missing: $relative"}
  $actualHash=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actualHash -ne $expectedHash){throw "SHA-256 mismatch: $relative"}
  $checked++
}
if($checked -ne 64){throw "Expected 64 checked files, got $checked"}

$vecRoot=Join-Path $extract 'software/precision/results/int16_vectors'
$manifestPath=Join-Path $vecRoot 'manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.layers.Count -ne 12){throw "Expected 12 layer records"}
foreach($layer in $manifest.layers){
  $dir=Join-Path $vecRoot ('layer_{0:D2}' -f [int]$layer.layer)
  foreach($key in @('x','w','bias','y_expected')){
    $file=Join-Path $dir $layer.files.$key.file
    if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "Vector missing: $file"}
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne
       $layer.files.$key.sha256.ToLowerInvariant()) {throw "Vector manifest hash mismatch: $file"}
  }
}

$toolDir=[IO.Path]::GetFullPath((Join-Path $root $IcarusBin))
$iverilog=Join-Path $toolDir 'iverilog.exe';$vvp=Join-Path $toolDir 'vvp.exe'
if(!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)){
  throw "Icarus/vvp not found under $toolDir"
}
$image=Join-Path $out 'int16_software_handoff.vvp'
$compileArgs=@('-g2012','-Wall','-s','int16_software_handoff_tb','-o',$image,'-c',
  (Join-Path $root 'rtl/files.f'),(Join-Path $root 'tb/int16_software_handoff_tb.sv'))
$oldErrorActionPreference=$ErrorActionPreference
$ErrorActionPreference='Continue'
$compileOutput=@(& $iverilog @compileArgs 2>&1)
$compileExit=$LASTEXITCODE
$compileOutput|ForEach-Object{$_.ToString()}|Set-Content -LiteralPath (Join-Path $out 'compile.log') -Encoding UTF8
if($compileExit -ne 0){$ErrorActionPreference=$oldErrorActionPreference;throw "RTL compile failed with exit code $compileExit"}

$results=[System.Collections.Generic.List[object]]::new()
if($Parallel){
  $running=[System.Collections.Generic.List[object]]::new()
  foreach($layerId in $Layers){
    if($layerId -lt 0 -or $layerId -gt 11){throw "Layer out of range: $layerId"}
    $layer=$manifest.layers | Where-Object {[int]$_.layer -eq $layerId} | Select-Object -First 1
    $shift=28-[int]$layer.format.y_frac
    $layerDir=Join-Path $vecRoot ('layer_{0:D2}' -f $layerId)
    $stdout=Join-Path $out ('layer_{0:D2}.stdout' -f $layerId)
    $stderr=Join-Path $out ('layer_{0:D2}.stderr' -f $layerId)
    $argList=@($image,"+layer=$layerId","+shift=$shift",
      "+a=$(Join-Path $layerDir $layer.files.x.file)",
      "+b=$(Join-Path $layerDir $layer.files.w.file)",
      "+bias=$(Join-Path $layerDir $layer.files.bias.file)",
      "+expected=$(Join-Path $layerDir $layer.files.y_expected.file)")
    Write-Host "Starting layer $layerId (out_shift=$shift) ..."
    $proc=Start-Process -FilePath $vvp -ArgumentList ($argList -join ' ') `
      -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $running.Add([pscustomobject]@{layer=$layerId;shift=$shift;process=$proc;
      stdout=$stdout;stderr=$stderr})
  }
  Wait-Process -Id @($running|ForEach-Object {$_.process.Id})
  foreach($job in $running){
    $job.process.Refresh()
    $simOutput=@();if(Test-Path -LiteralPath $job.stdout){$simOutput+=Get-Content -LiteralPath $job.stdout}
    if(Test-Path -LiteralPath $job.stderr){$simOutput+=Get-Content -LiteralPath $job.stderr}
    $log=Join-Path $out ('layer_{0:D2}.log' -f $job.layer)
    $simOutput|Set-Content -LiteralPath $log -Encoding UTF8
    $allText=[string]::Join([Environment]::NewLine,[string[]]$simOutput)
    $resultLine=([regex]::Match($allText,'(?m)^RESULT layer=.*$').Value).Trim()
    # Start-Process does not reliably expose ExitCode after Wait-Process on all
    # Windows PowerShell versions; the testbench PASS marker is authoritative.
    $pass=($allText -match '(?m)^PASS int16_software_handoff_tb')
    $simExit=if($pass){0}else{1}
    $results.Add([pscustomobject]@{layer=$job.layer;out_shift=$job.shift;result_status=$(if($pass){'PASS'}else{'FAIL'});
      passed=[bool]$pass;result=$resultLine;log=(Split-Path -Leaf $log)})
    Write-Host "Layer $($job.layer) exit=$simExit pass=$pass $resultLine"
  }
}else{
  foreach($layerId in $Layers){
    if($layerId -lt 0 -or $layerId -gt 11){throw "Layer out of range: $layerId"}
    $layer=$manifest.layers | Where-Object {[int]$_.layer -eq $layerId} | Select-Object -First 1
    $shift=28-[int]$layer.format.y_frac
    $layerDir=Join-Path $vecRoot ('layer_{0:D2}' -f $layerId)
    $log=Join-Path $out ('layer_{0:D2}.log' -f $layerId)
    Write-Host "Running layer $layerId (out_shift=$shift) ..."
    $simOutput=@(& $vvp $image "+layer=$layerId" "+shift=$shift" `
      "+a=$(Join-Path $layerDir $layer.files.x.file)" `
      "+b=$(Join-Path $layerDir $layer.files.w.file)" `
      "+bias=$(Join-Path $layerDir $layer.files.bias.file)" `
      "+expected=$(Join-Path $layerDir $layer.files.y_expected.file)" 2>&1)
    $simExit=$LASTEXITCODE
    $simOutput|ForEach-Object{$_.ToString()}|Set-Content -LiteralPath $log -Encoding UTF8
    $resultLine=$simOutput | ForEach-Object {$_.ToString()} |
      Where-Object {$_ -match '^RESULT layer='} | Select-Object -Last 1
    $pass=($simExit -eq 0) -and ($simOutput -match '^PASS int16_software_handoff_tb')
    $results.Add([pscustomobject]@{layer=$layerId;out_shift=$shift;result_status=$(if($pass){'PASS'}else{'FAIL'});
      passed=[bool]$pass;result=$resultLine;log=(Split-Path -Leaf $log)})
    Write-Host "Layer $layerId exit=$simExit pass=$pass $resultLine"
  }
}
$ErrorActionPreference=$oldErrorActionPreference
$results|Export-Csv -LiteralPath (Join-Path $out 'layer_results.csv') -NoTypeInformation -Encoding UTF8
$allPass=($compileExit -eq 0) -and (($results|Where-Object {-not $_.passed}).Count -eq 0)
[ordered]@{zip_path=$zip;zip_sha256=$archiveHash;baseline_head=(git -C $root rev-parse HEAD);
  checksum_files_verified=$checked;compile_exit_code=$compileExit;layers=$results;passed=$allPass;
  testbench='tb/int16_software_handoff_tb.sv';rtl_filelist='rtl/files.f'}|
  ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
if(!$allPass){Write-Warning 'One or more software candidate layers did not match active RTL; see per-layer logs and summary.'}
if(!$allPass){exit 1}
