param(
    [string]$InputDirectory = '',
    [string]$IverilogPath = '',
    [string]$VvpPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $projectRoot 'build/fp32_trace_reference'
$simulatorImage = Join-Path $projectRoot 'build/fp32_pe_trace_tb.vvp'
$tracePath = Join-Path $buildDirectory 'pe_trace_framework.csv'
$referencePath = Join-Path $buildDirectory 'fp32_trace_reference.csv'
$logPath = Join-Path $buildDirectory 'framework_simulation.log'
$reportPath = Join-Path $buildDirectory 'framework_compare_report.json'
$prepareScript = Join-Path $PSScriptRoot 'Prepare-Fp32TraceVectors.ps1'
$rtlFileList = Join-Path $projectRoot 'rtl/files.f'
$testbenchPath = Join-Path $projectRoot 'tb/fp32_pe_trace_tb.sv'

if (-not $IverilogPath) {
    $IverilogPath = Join-Path $projectRoot '.tools/iverilog/bin/iverilog.exe'
}
if (-not $VvpPath) {
    $VvpPath = Join-Path $projectRoot '.tools/iverilog/bin/vvp.exe'
}

foreach ($requiredPath in @($prepareScript, $rtlFileList, $testbenchPath, $IverilogPath, $VvpPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file or tool not found: $requiredPath"
    }
}

function Get-NormalizedFp32Word {
    param(
        [AllowNull()][string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return '00000000' }
    $word = $Value.Trim()
    if ($word.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
        $word = $word.Substring(2)
    }
    if ($word -notmatch '^[0-9a-fA-F]{8}$') {
        throw "$Label is not an 8-digit FP32 bit pattern: '$Value'"
    }
    return $word.ToLowerInvariant()
}

function Get-IntegerValue {
    param([string]$Value, [string]$Label)
    $parsed = 0
    if (-not [int]::TryParse(
        $Value,
        [Globalization.NumberStyles]::Integer,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )) {
        throw "$Label is not an integer: '$Value'"
    }
    return $parsed
}

function Add-Mismatch {
    param(
        [System.Collections.Generic.List[object]]$List,
        [int]$LineNumber,
        [string]$Field,
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual
    )
    $List.Add([pscustomobject]@{
        line = $LineNumber
        field = $Field
        expected = [string]$Expected
        actual = [string]$Actual
    })
}

function Compare-Field {
    param(
        [System.Collections.Generic.List[object]]$List,
        [int]$LineNumber,
        [string]$Field,
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual
    )
    if ([string]$Expected -cne [string]$Actual) {
        Add-Mismatch -List $List -LineNumber $LineNumber -Field $Field -Expected $Expected -Actual $Actual
    }
}

Push-Location $projectRoot
try {
    if ($InputDirectory) {
        & $prepareScript -InputDirectory $InputDirectory -OutputDirectory 'build/fp32_trace_reference'
    }
    else {
        & $prepareScript -OutputDirectory 'build/fp32_trace_reference'
    }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Vector preparation failed with exit code $LASTEXITCODE"
    }

    $compileOutput = @(& $IverilogPath -g2012 -s fp32_pe_trace_tb `
        -o $simulatorImage -f $rtlFileList $testbenchPath 2>&1)
    $compileExitCode = $LASTEXITCODE
    if ($compileExitCode -ne 0) {
        $compileOutput | ForEach-Object { Write-Error ([string]$_) }
        throw "Icarus compilation failed with exit code $compileExitCode"
    }

    $simulationOutput = @(& $VvpPath $simulatorImage 2>&1)
    $simulationExitCode = $LASTEXITCODE
    $simulationOutput | Set-Content -LiteralPath $logPath -Encoding UTF8
    $simulationOutput | ForEach-Object { Write-Output ([string]$_) }
    if ($simulationExitCode -ne 0) {
        throw "Icarus simulation failed with exit code $simulationExitCode; see $logPath"
    }
    if (-not (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
        throw "Simulation did not create the expected trace: $tracePath"
    }

    $referenceRows = @(Import-Csv -LiteralPath $referencePath)
    $traceRows = @(Import-Csv -LiteralPath $tracePath)
    $traceLines = @(Get-Content -LiteralPath $tracePath)
    if ($traceLines.Count -lt 1) { throw 'Trace CSV is empty' }
    $headerColumnCount = $traceLines[0].Split(',').Count
    $malformedLineNumbers = @()
    for ($lineIndex = 1; $lineIndex -lt $traceLines.Count; $lineIndex++) {
        if ($traceLines[$lineIndex].Split(',').Count -ne $headerColumnCount) {
            $malformedLineNumbers += ($lineIndex + 1)
        }
    }

    $mismatches = New-Object 'System.Collections.Generic.List[object]'
    if ($referenceRows.Count -ne 74) {
        Add-Mismatch -List $mismatches -LineNumber 0 -Field 'reference_row_count' -Expected 74 -Actual $referenceRows.Count
    }
    if ($traceRows.Count -ne $referenceRows.Count) {
        Add-Mismatch -List $mismatches -LineNumber 0 -Field 'trace_row_count' -Expected $referenceRows.Count -Actual $traceRows.Count
    }
    if ($headerColumnCount -ne 22) {
        Add-Mismatch -List $mismatches -LineNumber 1 -Field 'trace_column_count' -Expected 22 -Actual $headerColumnCount
    }
    foreach ($badLine in $malformedLineNumbers) {
        Add-Mismatch -List $mismatches -LineNumber $badLine -Field 'csv_field_count' -Expected $headerColumnCount -Actual 'incorrect'
    }

    $compareCount = [Math]::Min($referenceRows.Count, $traceRows.Count)
    for ($index = 0; $index -lt $compareCount; $index++) {
        $lineNumber = $index + 2
        $reference = $referenceRows[$index]
        $trace = $traceRows[$index]
        $caseId = switch ($reference.case) {
            'hand_2x2' { 0 }
            'rounding_nonfused' { 1 }
            'k32_boundary' { 2 }
            default { -1 }
        }

        Compare-Field $mismatches $lineNumber 'status' 'framework_only' $trace.status
        Compare-Field $mismatches $lineNumber 'case_id' ([string]$caseId) $trace.case_id
        Compare-Field $mismatches $lineNumber 'case' $reference.case $trace.case
        foreach ($field in @('row', 'column', 'k')) {
            $expectedInteger = Get-IntegerValue -Value ([string]$reference.$field) -Label "reference.$field at line $lineNumber"
            $actualInteger = Get-IntegerValue -Value ([string]$trace.$field) -Label "trace.$field at line $lineNumber"
            Compare-Field $mismatches $lineNumber $field $expectedInteger $actualInteger
        }
        Compare-Field $mismatches $lineNumber 'cycle' $index (Get-IntegerValue -Value ([string]$trace.cycle) -Label "trace.cycle at line $lineNumber")
        Compare-Field $mismatches $lineNumber 'input_valid' 1 (Get-IntegerValue -Value ([string]$trace.input_valid) -Label "trace.input_valid at line $lineNumber")

        foreach ($field in @('x_bits', 'w_bits', 'acc_before_bits', 'product_bits', 'acc_after_bits')) {
            $expectedWord = Get-NormalizedFp32Word -Value ([string]$reference.$field) -Label "reference.$field at line $lineNumber"
            $actualWord = Get-NormalizedFp32Word -Value ([string]$trace.$field) -Label "trace.$field at line $lineNumber"
            Compare-Field $mismatches $lineNumber $field $expectedWord $actualWord
        }

        $biasValid = Get-IntegerValue -Value ([string]$reference.bias_valid) -Label "reference.bias_valid at line $lineNumber"
        $taskFirst = if ((Get-IntegerValue -Value ([string]$reference.k) -Label "reference.k at line $lineNumber") -eq 0) { 1 } else { 0 }
        Compare-Field $mismatches $lineNumber 'task_first' $taskFirst (Get-IntegerValue -Value ([string]$trace.task_first) -Label "trace.task_first at line $lineNumber")
        Compare-Field $mismatches $lineNumber 'task_last' $biasValid (Get-IntegerValue -Value ([string]$trace.task_last) -Label "trace.task_last at line $lineNumber")
        Compare-Field $mismatches $lineNumber 'trace_bias_valid' $biasValid (Get-IntegerValue -Value ([string]$trace.trace_bias_valid) -Label "trace.trace_bias_valid at line $lineNumber")
        Compare-Field $mismatches $lineNumber 'result_valid' $biasValid (Get-IntegerValue -Value ([string]$trace.result_valid) -Label "trace.result_valid at line $lineNumber")

        foreach ($fieldPair in @(
            @{ Reference = 'bias_bits'; Trace = 'bias_bits' },
            @{ Reference = 'acc_before_bias_bits'; Trace = 'acc_before_bias_bits' },
            @{ Reference = 'result_bits'; Trace = 'result_bits' }
        )) {
            $expectedWord = Get-NormalizedFp32Word -Value ([string]$reference.($fieldPair.Reference)) -Label "reference.$($fieldPair.Reference) at line $lineNumber"
            $actualWord = Get-NormalizedFp32Word -Value ([string]$trace.($fieldPair.Trace)) -Label "trace.$($fieldPair.Trace) at line $lineNumber"
            Compare-Field $mismatches $lineNumber $fieldPair.Trace $expectedWord $actualWord
        }

        foreach ($fieldPair in @(
            @{ Reference = 'k32_save'; Trace = 'k32_save_marker' },
            @{ Reference = 'k32_restore'; Trace = 'k32_restore_marker' }
        )) {
            $expectedInteger = Get-IntegerValue -Value ([string]$reference.($fieldPair.Reference)) -Label "reference.$($fieldPair.Reference) at line $lineNumber"
            $actualInteger = Get-IntegerValue -Value ([string]$trace.($fieldPair.Trace)) -Label "trace.$($fieldPair.Trace) at line $lineNumber"
            Compare-Field $mismatches $lineNumber $fieldPair.Trace $expectedInteger $actualInteger
        }
    }

    $caseCounts = [ordered]@{
        hand_2x2 = @($traceRows | Where-Object case -eq 'hand_2x2').Count
        rounding_nonfused = @($traceRows | Where-Object case -eq 'rounding_nonfused').Count
        k32_boundary = @($traceRows | Where-Object case -eq 'k32_boundary').Count
    }
    foreach ($caseCheck in @(
        @{ Name = 'hand_2x2'; Expected = 8 },
        @{ Name = 'rounding_nonfused'; Expected = 2 },
        @{ Name = 'k32_boundary'; Expected = 64 }
    )) {
        if ($caseCounts[$caseCheck.Name] -ne $caseCheck.Expected) {
            Add-Mismatch -List $mismatches -LineNumber 0 -Field "case_count.$($caseCheck.Name)" -Expected $caseCheck.Expected -Actual $caseCounts[$caseCheck.Name]
        }
    }

    $inputVectorPath = Join-Path $buildDirectory 'fp32_step_vectors.txt'
    $report = [ordered]@{
        status = if ($mismatches.Count -eq 0) { 'FRAMEWORK_ONLY_PASS' } else { 'FAIL' }
        scope = 'candidate reference boundary only; not a real FP32 PE validation'
        generated_at = (Get-Date).ToString('o')
        simulator = 'Icarus Verilog'
        rows = $traceRows.Count
        columns = $headerColumnCount
        case_counts = $caseCounts
        mismatch_count = $mismatches.Count
        mismatches = @($mismatches.ToArray())
        artifacts = [ordered]@{
            vector_file = [ordered]@{ path = 'build/fp32_trace_reference/fp32_step_vectors.txt'; sha256 = (Get-FileHash -LiteralPath $inputVectorPath -Algorithm SHA256).Hash.ToLowerInvariant() }
            software_reference_csv = [ordered]@{ path = 'build/fp32_trace_reference/fp32_trace_reference.csv'; sha256 = (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash.ToLowerInvariant() }
            framework_trace_csv = [ordered]@{ path = 'build/fp32_trace_reference/pe_trace_framework.csv'; sha256 = (Get-FileHash -LiteralPath $tracePath -Algorithm SHA256).Hash.ToLowerInvariant() }
            testbench = [ordered]@{ path = 'tb/fp32_pe_trace_tb.sv'; sha256 = (Get-FileHash -LiteralPath $testbenchPath -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
        limitations = @(
            'The adapter wraps rtl/fp32_mac_boundary.sv rather than a real FP32 PE.',
            'The required 8-cycle multiply plus 4-cycle add pipeline is not implemented or timed here.',
            'Bias is checked in the testbench; it is not computed by the candidate PE boundary.',
            'The software numerical rules remain provisional until both teams confirm them.'
        )
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    if ($mismatches.Count -ne 0) {
        $mismatches | Select-Object -First 20 | Format-Table -AutoSize | Out-String | Write-Error
        throw "Framework comparison failed with $($mismatches.Count) mismatch(es); see $reportPath"
    }

    Write-Output "FRAMEWORK_ONLY PASS: rows=$($traceRows.Count) columns=$headerColumnCount; hand_2x2=$($caseCounts.hand_2x2), rounding_nonfused=$($caseCounts.rounding_nonfused), k32_boundary=$($caseCounts.k32_boundary)"
    Write-Output "Diagnostic trace: $tracePath"
    Write-Output "Comparison report: $reportPath"
    Write-Output 'This is not a real FP32 PE trace or hardware sign-off.'
}
finally {
    Pop-Location
}
