param([string]$Iverilog = '', [string]$Vvp = '')
$ErrorActionPreference = 'Stop'
function Invoke-NativeTool {
    param([string]$Executable, [string[]]$Arguments)
    # Windows PowerShell 5 wraps native stderr in ErrorRecord. Capture warnings
    # locally and check the exit code; keep errors terminating in the caller.
    $ErrorActionPreference = 'Continue'
    $toolOutput = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    $toolExit = $LASTEXITCODE
    [pscustomobject]@{ ExitCode=$toolExit; Output=$toolOutput }
}
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    if (-not $Iverilog) {
        $portableIverilog = Join-Path $projectRoot '.tools/iverilog/bin/iverilog.exe'
        if (Test-Path -LiteralPath $portableIverilog) { $Iverilog = $portableIverilog }
        else { $Iverilog = (Get-Command iverilog -ErrorAction Stop).Source }
    }
    if (-not $Vvp) { $Vvp = Join-Path (Split-Path -Parent $Iverilog) 'vvp.exe' }
    if (-not (Test-Path -LiteralPath $Vvp)) { $Vvp = (Get-Command vvp -ErrorAction Stop).Source }
    New-Item -ItemType Directory -Force -Path 'build/logs' | Out-Null
    & "$PSScriptRoot/Generate-Fp32Vectors.ps1"
    $failures = @()
    $tests = Get-ChildItem -LiteralPath 'tb' -Filter '*_tb.sv' | Sort-Object Name
    foreach ($test in $tests) {
        $testName = $test.BaseName
        $binary = "build/$testName.vvp"
        $compileLog = "build/logs/$testName.compile.log"
        $simLog = "build/logs/$testName.sim.log"
        $compileResult = Invoke-NativeTool $Iverilog @('-g2012','-s',$testName,'-o',$binary,'-f','rtl/files.f',$test.FullName)
        $compileResult.Output | Out-File -LiteralPath $compileLog -Encoding utf8
        if ($compileResult.ExitCode -ne 0) {
            Write-Output "FAIL $testName (compile; see $compileLog)"
            $failures += $testName
            continue
        }
        $simResult = Invoke-NativeTool $Vvp @($binary)
        $simOutput = $simResult.Output
        $simExit = $simResult.ExitCode
        $simOutput | Out-File -LiteralPath $simLog -Encoding utf8
        if ($simExit -ne 0 -or -not ($simOutput -match "$testName PASS")) {
            Write-Output "FAIL $testName (simulation; see $simLog)"
            $simOutput | Write-Output
            $failures += $testName
        } else { Write-Output ($simOutput -join "`n") }
    }
    $socResult = Invoke-NativeTool $Iverilog @('-g2012','-s','ai_engine_soc_adapter','-o','build/soc_elaboration.vvp','-f','rtl/files.f')
    $socResult.Output | Out-File -LiteralPath build/logs/soc_elaboration.log -Encoding utf8
    if ($socResult.ExitCode -ne 0) { $failures += 'soc_elaboration' }
    $summary = "Tests: $($tests.Count); failures: $($failures.Count); failed: $($failures -join ', ')"
    $summary | Out-File -LiteralPath build/logs/summary.txt -Encoding utf8
    Write-Output $summary
    if ($failures.Count) { throw 'RTL regression failed; see build/logs.' }
} finally { Pop-Location }
