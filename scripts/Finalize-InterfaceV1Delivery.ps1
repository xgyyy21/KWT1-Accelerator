param([string]$PacketDirectory='handoff/interface_v1_evidence_2026-10-20_run2')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$packetRoot=(Resolve-Path -LiteralPath (Join-Path $project $PacketDirectory)).Path
$manifest=Get-Content -LiteralPath (Join-Path $packetRoot 'manifest.json') -Raw | ConvertFrom-Json
if($manifest.failed -ne 0 -or $manifest.passed -ne 13){throw 'Expected completed 13-test successful evidence; refusing to seal'}
$driverHash=(Get-FileHash -LiteralPath (Join-Path $packetRoot 'software_snapshot/software/driver/kwt_driver.c') -Algorithm SHA256).Hash
$inputDirectory=Join-Path $packetRoot 'software_snapshot/software/examples/fp32_hand_image'
$inputChecks=@()
foreach($memFile in Get-ChildItem -LiteralPath $inputDirectory -Filter '*.mem'){
    $binFile=[IO.Path]::ChangeExtension($memFile.FullName,'.bin')
    $bytes=[IO.File]::ReadAllBytes($binFile)
    $words=@(Get-Content -LiteralPath $memFile.FullName | Where-Object {$_.Trim()})
    if($bytes.Length -ne 2*$words.Count){throw "Input byte count mismatch: $($memFile.Name)"}
    for($index=0;$index -lt $words.Count;$index++){
        $word=[Convert]::ToUInt16($words[$index].Trim(),16)
        if($bytes[2*$index] -ne ($word -band 255) -or $bytes[2*$index+1] -ne ($word -shr 8)){
            throw "Little-endian mem/bin mismatch: $($memFile.Name) word=$index"
        }
    }
    $inputChecks+=[pscustomobject]@{file=$memFile.Name;words=$words.Count;bytes=$bytes.Length;status='PASS';mem_sha256=(Get-FileHash -LiteralPath $memFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant();bin_sha256=(Get-FileHash -LiteralPath $binFile -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$inputChecks | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $packetRoot 'logs/input_mem_bin_check.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $project 'scripts/Replay-InterfaceV1Evidence.ps1') -Destination (Join-Path $packetRoot 'scripts/Replay-InterfaceV1Evidence.ps1')
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $packetRoot 'scripts/Finalize-InterfaceV1Delivery.ps1')
$hashes=Get-ChildItem -LiteralPath $packetRoot -File -Recurse | Where-Object {$_.Name -ne 'SHA256SUMS.txt' -and $_.Extension -ne '.vvp'} | Sort-Object FullName | ForEach-Object {
    $relative=$_.FullName.Substring($packetRoot.Length+1).Replace('\','/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$relative
}
$hashes | Out-File -LiteralPath (Join-Path $packetRoot 'SHA256SUMS.txt') -Encoding utf8
$stage=Join-Path $project 'build/interface_v1_delivery_2026-10-20'
$archive=Join-Path $project 'handoff/interface_v1_delivery_2026-10-20.zip'
if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $archive)){throw 'Delivery target already exists; refusing overwrite'}
New-Item -ItemType Directory -Path $stage | Out-Null
$packetName=Split-Path -Leaf $packetRoot
$stagePacket=Join-Path $stage $packetName
New-Item -ItemType Directory -Path $stagePacket | Out-Null
foreach($source in Get-ChildItem -LiteralPath $packetRoot -Force){
    if($source.Name -eq 'run'){continue}
    Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $stagePacket $source.Name) -Recurse
}
foreach($document in @('memory_layout_v1.md','control_interface_v1.md')){
    Copy-Item -LiteralPath (Join-Path $project "handoff/$document") -Destination (Join-Path $stage $document)
}
New-Item -ItemType Directory -Path (Join-Path $stage 'scripts') | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'scripts/Replay-InterfaceV1Evidence.ps1') -Destination (Join-Path $stage 'scripts/Replay-InterfaceV1Evidence.ps1')
$deliveryHashes=Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative=$_.FullName.Substring($stage.Length+1).Replace('\','/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$relative
}
$deliveryHashes | Out-File -LiteralPath (Join-Path $stage 'DELIVERY_SHA256SUMS.txt') -Encoding utf8
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive
$archiveHash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Delivery=$archive SHA256=$archiveHash"
Write-Output "Tests=$($manifest.passed)/13; source/input/log hashes=$($hashes.Count); mem/bin pairs=$($inputChecks.Count); files in delivery=$($deliveryHashes.Count)"
Write-Output "Driver SHA256=$driverHash"
