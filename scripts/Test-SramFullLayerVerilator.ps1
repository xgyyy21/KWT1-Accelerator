param([string]$OutputDirectory='build/sram_full_layer_verilator_2026-10-28_v1',[switch]$SecondLayer,[switch]$TwoLayers)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$outPath=[IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
if (!$outPath.StartsWith($projectRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be inside the project.'
}
if (Test-Path -LiteralPath $outPath) { throw "Refusing to overwrite evidence: $outPath" }
if ($SecondLayer -and $TwoLayers) { throw 'Choose SecondLayer or TwoLayers, not both.' }
$bash=Join-Path $projectRoot '.tools/msys64/usr/bin/bash.exe'
if (!(Test-Path -LiteralPath $bash)) { throw 'Prepared Verilator environment missing.' }
New-Item -ItemType Directory -Path $outPath | Out-Null
$snapshot=Join-Path $outPath 'sources'
$files=@(Get-Content -LiteralPath (Join-Path $projectRoot 'rtl/files.f') |
    ForEach-Object {$_.Trim()} | Where-Object {$_ -and !$_.StartsWith('//')})
$files+=@('rtl/files.f','tb/support/ramsp128x16_functional_model.sv',
    'tb/fp32_sram_accelerator_top_tb.sv','scripts/Test-SramFullLayerVerilator.ps1','scripts/run-sram-full-layer.sh')
$manifest=foreach($relative in ($files | Sort-Object -Unique)) {
    $original=Join-Path $projectRoot $relative
    $copy=Join-Path $snapshot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
    Copy-Item -LiteralPath $original -Destination $copy
    $hash=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    if((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $hash) {throw "Snapshot mismatch: $relative"}
    [pscustomobject]@{Path=$relative;Bytes=(Get-Item -LiteralPath $copy).Length;SHA256=$hash}
}
$manifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
$status=[ordered]@{
    Started=(Get-Date).ToString('o');Complete=$false;Passed=$false
    SourceIdentity='Local snapshot and source_manifest.csv, not a Git commit'
    Scope=$(if($TwoLayers){'Macro-mode continuous FFN1 99x64x256 then FFN2 99x256x64 without reset or SRAM clear'}elseif($SecondLayer){'Macro-mode full FFN2 99x256x64, nonuniform exact synthetic data, internal control/bus'}else{'Macro-mode full FFN1 99x64x256, nonuniform exact synthetic data, internal control/bus'})
    VendorTimingModelUsed=$false;E203Integrated=$false;SoftwareIndependentReview=$false
}
$status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
$oldMsystem=$env:MSYSTEM; $oldChere=$env:CHERE_INVOKING
try {
    $env:MSYSTEM='UCRT64';$env:CHERE_INVOKING='1'
    $scriptPath=(Join-Path $snapshot 'scripts/run-sram-full-layer.sh').Replace('\','/')
    $mode=if($TwoLayers){'two'}elseif($SecondLayer){'second'}else{'full'}
    $arguments=@('--login',$scriptPath,$snapshot.Replace('\','/'),$outPath.Replace('\','/'),$mode)
    $status.Command=$bash+' '+(($arguments | ForEach-Object {'"'+$_+'"'}) -join ' ')
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
    & $bash @arguments
    $exitCode=$LASTEXITCODE
    $status.ProcessExitCode=$exitCode
    $status.CompileExitCode=$(if(Test-Path -LiteralPath (Join-Path $outPath 'compile_exit_code.txt')) {
        [int](Get-Content -LiteralPath (Join-Path $outPath 'compile_exit_code.txt'))} else {$null})
    $status.SimulationExitCode=$(if(Test-Path -LiteralPath (Join-Path $outPath 'simulation_exit_code.txt')) {
        [int](Get-Content -LiteralPath (Join-Path $outPath 'simulation_exit_code.txt'))} else {$null})
    $passPattern=if($TwoLayers){'^PASS sram_accelerator_top two_layers=1 '}elseif($SecondLayer){'^PASS sram_accelerator_top second_layer=1 '}else{'^PASS sram_accelerator_top full_layer=1 '}
    $status.Passed=$exitCode -eq 0 -and $status.SimulationExitCode -eq 0 -and
        (Select-String -LiteralPath (Join-Path $outPath 'simulation.log') -Pattern $passPattern -Quiet)
    $status.Complete=$true;$status.Finished=(Get-Date).ToString('o')
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
    Get-ChildItem -LiteralPath $outPath -Recurse -File | Where-Object Name -ne 'evidence_sha256.csv' |
        Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{Path=$_.FullName.Substring($outPath.Length+1).Replace('\','/');
                Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
        } | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
    if(!$status.Passed) {throw "Full-layer verification failed; evidence retained at $outPath"}
    Write-Host "PASS full-layer evidence: $outPath"
} finally {$env:MSYSTEM=$oldMsystem;$env:CHERE_INVOKING=$oldChere}
