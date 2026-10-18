param(
    [Parameter(Mandatory=$true)][string]$Iverilog,
    [Parameter(Mandatory=$true)][string]$Vvp,
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path -Parent (Split-Path -Parent $packageRoot)) 'build/readback_replay'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$Iverilog = (Resolve-Path -LiteralPath $Iverilog).Path
$Vvp = (Resolve-Path -LiteralPath $Vvp).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Invoke-Checked {
    param([string]$Tool, [string[]]$ToolArguments, [string]$Log)
    $ErrorActionPreference = 'Continue'
    $messages = @(& $Tool @ToolArguments 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $logText = if ($messages.Count) { ($messages -join "`n") + "`n" } else { '' }
    [IO.File]::WriteAllText($Log, $logText, (New-Object Text.UTF8Encoding($false)))
    if ($code -ne 0) { throw "Tool failed ($code): $Tool; see $Log" }
    return $messages
}
Push-Location $packageRoot
try {
    $provenance = Get-Content -LiteralPath 'provenance.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $provenance.files) {
        $actual = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $entry.sha256) { throw "Evidence file SHA-256 mismatch: $($entry.path)" }
    }
    $manifest = Get-Content -LiteralPath 'inputs/manifest.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @('x','w','bias','rounding_x','rounding_w','rounding_bias','tile_x','tile_w','tile_bias')
    $hashes = @{}
    foreach ($name in $names) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $packageRoot "inputs/$name.bin"))
        $words = @(Get-Content -LiteralPath "inputs/$name.mem")
        $digest = (Get-FileHash -LiteralPath "inputs/$name.bin" -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($digest -cne $manifest.tensors.$name.sha256_bin) { throw "Manifest disagrees: $name" }
        if ($bytes.Length -ne $words.Count * 2) { throw "Word count disagrees: $name" }
        for ($i=0; $i -lt $words.Count; $i++) {
            if ($words[$i] -notmatch '^[0-9a-fA-F]{4}$') { throw "Invalid mem word: $name/$i" }
            $word = [Convert]::ToUInt16($words[$i],16)
            if ($bytes[2*$i] -ne ($word -band 255) -or $bytes[2*$i+1] -ne ($word -shr 8)) {
                throw "Binary and mem disagree: $name/$i"
            }
        }
        $hashes[$name] = $digest
    }
    $image = Join-Path $OutputDirectory 'word_readback_tb.vvp'
    $csvPath = Join-Path $OutputDirectory 'word_readback.csv'
    $compilerVersion = @(Invoke-Checked $Iverilog @('-V') (Join-Path $OutputDirectory 'iverilog_version.log'))
    $runtimeVersion = @(Invoke-Checked $Vvp @('-V') (Join-Path $OutputDirectory 'vvp_version.log'))
    $compileArguments = @('-g2012','-s','word_readback_tb','-o',$image,'-f','readback.f')
    $null = Invoke-Checked $Iverilog $compileArguments (Join-Path $OutputDirectory 'compile.log')
    $simArguments = @($image,"+output=$($csvPath.Replace('\','/'))",'+data_dir=inputs',
        "+rtl_revision=$($provenance.rtl_commit)","+rtl_snapshot=$($provenance.compiled_snapshot_sha256)")
    $plusargNames = @('hand_x','hand_w','hand_bias','round_x','round_w','round_bias','tile_x','tile_w','tile_bias')
    for($i=0; $i -lt $names.Count; $i++) { $simArguments += "+$($plusargNames[$i])_sha=$($hashes[$names[$i]])" }
    $simulation = @(Invoke-Checked $Vvp $simArguments (Join-Path $OutputDirectory 'simulation.log'))
    if (-not ($simulation -match 'word_readback_tb PASS')) { throw 'Missing simulation PASS marker' }
    $rows = @(Import-Csv -LiteralPath $csvPath)
    if ($rows.Count -ne 144) { throw "Wrong number of records: $($rows.Count)" }
    $covered = @{}
    foreach ($row in $rows) {
        $name = [IO.Path]::GetFileNameWithoutExtension($row.input_bin)
        if ($name -notin $names -or $row.input_sha256 -cne $hashes[$name]) { throw 'CSV input hash mismatch' }
        if ($row.rtl_revision -cne $provenance.rtl_commit -or $row.rtl_snapshot_sha256 -cne $provenance.compiled_snapshot_sha256) { throw 'CSV RTL identity mismatch' }
        $low = [int]$row.low_word_address; $high = [int]$row.high_word_address
        $words = @(Get-Content -LiteralPath "inputs/$name.mem")
        if ($low -lt 0 -or $low%2 -ne 0 -or $high -ne $low+1 -or $high -ge $words.Count) { throw 'CSV address mismatch' }
        if ($row.word_low16 -ine $words[$low] -or $row.word_high16 -ine $words[$high]) { throw 'CSV read value mismatch' }
        if ($row.reconstructed_fp32_bits -ine ('0x'+$words[$high]+$words[$low])) { throw 'CSV FP32 reconstruction mismatch' }
        if ([int]$row.low_data_valid_cycle -ne [int]$row.low_request_cycle+1 -or [int]$row.high_data_valid_cycle -ne [int]$row.high_request_cycle+1) { throw 'CSV read latency mismatch' }
        $key = "$name/$low"
        if ($covered.ContainsKey($key)) { throw "Duplicate element: $key" }; $covered[$key] = $true
    }
    foreach ($name in $names) {
        $count = (Get-Item -LiteralPath "inputs/$name.bin").Length/4
        for($i=0; $i -lt $count; $i++) { if(-not $covered.ContainsKey("$name/$($i*2)")) { throw 'Missing tensor element' } }
    }
    $report = [ordered]@{
        status='CACHE_READBACK_ONLY_PASS'; rows=$rows.Count; groups=$names.Count
        rtl_commit=$provenance.rtl_commit; software_commit=$provenance.software_commit
        compiled_snapshot_sha256=$provenance.compiled_snapshot_sha256
        csv_sha256=(Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash.ToLowerInvariant()
        compile_arguments=$compileArguments; simulation_arguments=$simArguments
        compiler_version=$compilerVersion[0]; runtime_version=$runtimeVersion[0]
        limitations=@('Cache-manager boundary only; no PE, DMA, SRAM macro or E203 verification.',
            'Fresh replay does not authenticate the historical +dirty source snapshot.')
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run_report.json') -Encoding UTF8
    Write-Output "CACHE_READBACK_ONLY_PASS rows=$($rows.Count) groups=9 CSV_SHA256=$($report.csv_sha256)"
}
finally { Pop-Location }
