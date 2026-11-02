param(
    [string]$OutputDirectory = 'build/sram_accelerator_top_2026-10-28_v1',
    [string]$IcarusBin = '.tools/iverilog/bin',
    [switch]$SkipFullLayer
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
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) { throw 'Icarus/vvp missing.' }
function Invoke-RecordedProcess {
    param([string]$Executable, [string[]]$ToolArguments, [string]$LogBase)
    # Start-Process needs explicit argument quoting. These arguments contain no
    # embedded double quotes; reject them instead of silently corrupting paths.
    foreach ($argument in $ToolArguments) {
        if ($argument.Contains('"')) { throw 'Embedded quotes in tool argument.' }
    }
    $argumentString = ($ToolArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $started = Get-Date
    $process = Start-Process -FilePath $Executable -ArgumentList $argumentString -WindowStyle Hidden `
        -WorkingDirectory $snapshot -RedirectStandardOutput "$LogBase.stdout.log" `
        -RedirectStandardError "$LogBase.stderr.log" -PassThru -Wait
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Started = $started.ToString('o'); Finished = (Get-Date).ToString('o')
        Seconds = ((Get-Date) - $started).TotalSeconds
        Command = $Executable + ' ' + $argumentString
    }
}
New-Item -ItemType Directory -Path $outPath | Out-Null
$snapshot = Join-Path $outPath 'sources'
$sources = @(Get-Content -LiteralPath (Join-Path $projectRoot 'rtl/files.f') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and !$_.StartsWith('//') })
$sources += @('rtl/files.f','tb/support/ramsp128x16_functional_model.sv',
    'tb/fp32_sram_accelerator_top_tb.sv','scripts/Test-SramAcceleratorTop.ps1')
$sourceManifest = foreach ($relative in ($sources | Sort-Object -Unique)) {
    $original = Join-Path $projectRoot $relative
    $copy = Join-Path $snapshot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
    Copy-Item -LiteralPath $original -Destination $copy
    $hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $hash) { throw "Snapshot mismatch: $relative" }
    [pscustomobject]@{ Path=$relative; Bytes=(Get-Item -LiteralPath $copy).Length; SHA256=$hash }
}
$sourceManifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $snapshot 'run') | Out-Null
$null = Invoke-RecordedProcess $iverilog @('-V') (Join-Path $outPath 'iverilog_version')
$null = Invoke-RecordedProcess $vvp @('-V') (Join-Path $outPath 'vvp_version')
$tests = @('continuous_jobs')
if (!$SkipFullLayer) { $tests += 'ffn1_full_layer' }
$results = @()
$status = [ordered]@{
    Created=(Get-Date).ToString('o'); WorkingDirectory=$snapshot; Complete=$false
    SourceIdentity='Local source snapshot fixed by source_manifest.csv, not a Git commit'
    VendorTimingModelUsed=$false; E203Integrated=$false; SoftwareIndependentReview=$false
    Tests=@(); Passed=0; Failed=0
}
foreach ($test in $tests) {
    $testPath = Join-Path $outPath $test
    New-Item -ItemType Directory -Path $testPath | Out-Null
    $image = "run/$test.vvp"
    $compileArgs = @('-g2012','-s','fp32_sram_accelerator_top_tb')
    if ($test -eq 'ffn1_full_layer') { $compileArgs += '-Pfp32_sram_accelerator_top_tb.FULL_LAYER=1' }
    if ($test -eq 'continuous_jobs') { $compileArgs += '-Pfp32_sram_accelerator_top_tb.CONTINUOUS_SMALL=1' }
    $compileArgs += @('-o',$image,'-c','rtl/files.f',
        'tb/support/ramsp128x16_functional_model.sv','tb/fp32_sram_accelerator_top_tb.sv')
    $runArgs = @($image,"+OUT_DIR=$testPath")
    Write-Host "Starting $test"
    $compile = Invoke-RecordedProcess $iverilog $compileArgs (Join-Path $testPath 'compile')
    $run = $null
    $result = [ordered]@{ Test=$test; State='Compiled'; Passed=$false; Compile=$compile; Simulation=$null }
    $results += [pscustomobject]$result
    $status.Tests = $results
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
    if ($compile.ExitCode -eq 0) {
        $run = Invoke-RecordedProcess $vvp $runArgs (Join-Path $testPath 'simulation')
    }
    $passed = $null -ne $run -and $run.ExitCode -eq 0 -and
        (Select-String -LiteralPath (Join-Path $testPath 'simulation.stdout.log') -Pattern '^PASS sram_accelerator_top ' -Quiet)
    $results[-1].Simulation=$run
    $results[-1].Passed=$passed
    $results[-1].State=$(if ($passed) {'Passed'} else {'Failed'})
    $status.Passed=@($results | Where-Object Passed -eq $true).Count
    $status.Failed=@($results | Where-Object State -eq 'Failed').Count
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
    Write-Host "$test Passed=$passed"
    if ($null -ne $run) { Get-Content -LiteralPath (Join-Path $testPath 'simulation.stdout.log') | Select-Object -Last 3 | ForEach-Object { Write-Host $_ } }
    if (!$passed) { break }
}
$status.Complete=$true
$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
Get-ChildItem -LiteralPath $outPath -Recurse -File | Where-Object Name -ne 'evidence_sha256.csv' |
    Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            Path=$_.FullName.Substring($outPath.Length+1).Replace('\','/')
            Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    } | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
if ($status.Failed -gt 0) { throw "Test failed; evidence retained at $outPath" }
Write-Host "Evidence: $outPath; passed=$($status.Passed); failed=$($status.Failed)"
