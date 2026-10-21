param(
    [string]$OutputDirectory = 'handoff/interface_v1_evidence_2026-10-20',
    [string]$TeamRepo = 'build/team_handoff_repo'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$destination = [IO.Path]::GetFullPath((Join-Path $project $OutputDirectory))
if (Test-Path -LiteralPath $destination) { throw "Refusing to overwrite evidence: $destination" }
$gitRepo = [IO.Path]::GetFullPath((Join-Path $project $TeamRepo))
$hardware = (& git -C $gitRepo rev-parse origin/hardware).Trim()
$software = (& git -C $gitRepo rev-parse origin/software).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve software revision' }
$tests = @('interface_v1_memory_tb','interface_v1_top_tb','ai_engine_regs_tb',
    'fp32_nice_control_adapter_tb','fp32_tile_soc_bus_adapter_tb',
    'fp32_tile_cache_mapper_tb','fp32_matrix_global_addr_gen_tb',
    'fp32_tile_dma_load_engine_tb','fp32_tile_dma_writeback_engine_tb',
    'fp32_tile_kblock_load_compute_tb','fp32_tile_kblock_load_compute_k256_tb',
    'fp32_matrix_tile_scheduler_tb','fp32_accelerator_top_tb')
New-Item -ItemType Directory -Path $destination | Out-Null
foreach ($dir in @('rtl','tb','logs','run','software_snapshot','scripts')) {
    New-Item -ItemType Directory -Path (Join-Path $destination $dir) | Out-Null
}
Copy-Item -LiteralPath (Join-Path $project 'rtl/files.f') -Destination (Join-Path $destination 'rtl/files.f')
foreach ($source in Get-Content -LiteralPath (Join-Path $project 'rtl/files.f')) {
    if ($source.Trim()) { Copy-Item -LiteralPath (Join-Path $project $source.Trim()) -Destination (Join-Path $destination $source.Trim()) }
}
foreach ($test in $tests) {
    Copy-Item -LiteralPath (Join-Path $project "tb/$test.sv") -Destination (Join-Path $destination "tb/$test.sv")
}
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $destination 'scripts/Run-InterfaceV1Evidence.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Replay-InterfaceV1Evidence.ps1') -Destination (Join-Path $destination 'scripts/Replay-InterfaceV1Evidence.ps1')
$archive = Join-Path $destination 'software_snapshot.zip'
& git -C $gitRepo archive --format=zip "--output=$archive" $software software/examples/fp32_hand_image software/driver software/pack_fp32.py software/fp32_reference.py software/innovation/FP32_TILING_CANDIDATE.md docs
if ($LASTEXITCODE -ne 0) { throw 'Cannot archive fixed software inputs' }
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $destination 'software_snapshot')
$iverilog = Join-Path $project '.tools/iverilog/bin/iverilog.exe'
$vvp = Join-Path $project '.tools/iverilog/bin/vvp.exe'
function Invoke-Logged([string]$exe,[string[]]$arguments,[string]$log) {
    $ErrorActionPreference = 'Continue'
    $lines = @(& $exe @arguments 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $lines | Out-File -LiteralPath $log -Encoding utf8
    [pscustomobject]@{exit=$code;lines=$lines}
}
Push-Location $destination
try {
    $tool = Invoke-Logged $iverilog @('-V') 'logs/iverilog_version.log'
    $runtime = Invoke-Logged $vvp @('-V') 'logs/vvp_version.log'
    $results = @()
    foreach ($test in $tests) {
        $binary = "run/$test.vvp"
        $arguments = @('-g2012','-s',$test,'-o',$binary,'-f','rtl/files.f',"tb/$test.sv")
        $compile = Invoke-Logged $iverilog $arguments "logs/$test.compile.log"
        $sim = $null
        if ($compile.exit -eq 0) { $sim = Invoke-Logged $vvp @($binary) "logs/$test.sim.log" }
        $passed = $compile.exit -eq 0 -and $null -ne $sim -and $sim.exit -eq 0 -and ($sim.lines -match '\bPASS\b').Count -gt 0
        $result = [ordered]@{test=$test;status=$(if($passed){'PASS'}else{'FAIL'});compile_exit=$compile.exit;simulation_exit=$(if($null -ne $sim){$sim.exit}else{$null});compile_command="iverilog $($arguments -join ' ')";simulation_command="vvp $binary"}
        $results += [pscustomobject]$result
        Write-Output "$($result.status) $test"
        if (-not $passed -and $null -ne $sim) { $sim.lines | Write-Output }
    }
    $manifest = [ordered]@{
        version='interface_v1-evidence-2026-10-20';created=(Get-Date).ToString('o');
        hardware_remote_baseline=$hardware;software_commit=$software;
        rtl_identity='Local uncommitted snapshot; not identical to hardware baseline. See SHA256SUMS.txt.';
        scope='Protocol-neutral NICE control and 16-bit word System-Bus model; not E203/SoC or physical timing.';
        input_loading='interface_v1_top_tb loads software_snapshot/software/examples/fp32_hand_image/*.mem; hand X/W explicitly zero-padded to K=32; K64 vector loaded directly.';
        input_bytes='Software .bin is little endian; no physical System Bus byte-lane wrapper tested.';
        tests=$results;passed=@($results | Where-Object status -eq 'PASS').Count;
        failed=@($results | Where-Object status -eq 'FAIL').Count;
        psum_storage='PE accumulator registers retained across K blocks; SRAM partial-sum save/restore NOT USED.'
    }
    $manifest | ConvertTo-Json -Depth 8 | Out-File -LiteralPath 'manifest.json' -Encoding utf8
    $hashes = Get-ChildItem -LiteralPath $destination -File -Recurse | Where-Object { $_.Name -ne 'SHA256SUMS.txt' -and $_.Extension -ne '.vvp' } | Sort-Object FullName | ForEach-Object {
        $relative=$_.FullName.Substring($destination.Length+1).Replace('\','/')
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$relative
    }
    $hashes | Out-File -LiteralPath 'SHA256SUMS.txt' -Encoding utf8
    Write-Output "Evidence=$destination Passed=$($manifest.passed) Failed=$($manifest.failed)"
} finally { Pop-Location }
