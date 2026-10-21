param(
    [string]$InputDirectory = '',
    [string]$OutputDirectory = 'build/fp32_trace_reference'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-ProjectPath {
    param([string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $projectRoot $Path)
}

function Get-BytesSha256 {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Assert-Hex32 {
    param([object]$Value, [string]$Label)
    if ([string]$Value -notmatch '^0x[0-9a-fA-F]{8}$') {
        throw "$Label is not an 8-digit hexadecimal FP32 word: $Value"
    }
}

function Get-Binary32Word {
    param([byte[]]$Bytes, [int]$ElementIndex, [string]$Label)
    $offset = $ElementIndex * 4
    if ($offset -lt 0 -or ($offset + 3) -ge $Bytes.Length) {
        throw "$Label element index $ElementIndex is outside the binary image"
    }
    return ('0x{0:x2}{1:x2}{2:x2}{3:x2}' -f $Bytes[$offset + 3], $Bytes[$offset + 2], $Bytes[$offset + 1], $Bytes[$offset])
}

if (-not $InputDirectory) {
    $candidates = @(
        'testdata/software_db073056/software/examples/fp32_hand_image',
        'software/examples/fp32_hand_image'
    ) | ForEach-Object { Resolve-ProjectPath $_ }
    $InputDirectory = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $InputDirectory) { throw 'FP32 hand-image directory was not found' }
$InputDirectory = (Resolve-ProjectPath $InputDirectory)
$OutputDirectory = (Resolve-ProjectPath $OutputDirectory)
if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) {
    throw "FP32 input directory does not exist: $InputDirectory"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$manifestPath = Join-Path $InputDirectory 'manifest.json'
$tracePath = Join-Path $InputDirectory 'expected_traces.json'
$traceHashPath = Join-Path $InputDirectory 'expected_traces.sha256'
foreach ($required in @($manifestPath, $tracePath, $traceHashPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required FP32 reference file is missing: $required"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$traceDocument = Get-Content -LiteralPath $tracePath -Raw -Encoding utf8 | ConvertFrom-Json
$declaredTraceHash = ((Get-Content -LiteralPath $traceHashPath -Encoding ascii -TotalCount 1) -split '\s+')[0].ToLowerInvariant()

# The checked-in software file may have CRLF line endings after extraction. The
# declared digest is for its canonical UTF-8/LF representation.
$traceText = [IO.File]::ReadAllText($tracePath, [Text.Encoding]::UTF8)
$canonicalTraceText = $traceText.Replace("`r`n", "`n").Replace("`r", "`n")
$actualTraceHash = Get-BytesSha256 ([Text.Encoding]::UTF8.GetBytes($canonicalTraceText))
if ($actualTraceHash -ne $declaredTraceHash) {
    throw "expected_traces.json SHA-256 mismatch: declared $declaredTraceHash actual $actualTraceHash"
}

$verifiedTensors = @()
$tensorReports = @()
$tensorBinary = @{}
$tensorShapes = @{}
foreach ($tensorProperty in @($manifest.tensors.PSObject.Properties)) {
    $tensorName = $tensorProperty.Name
    $entry = $tensorProperty.Value
    $binPath = Join-Path $InputDirectory ($tensorName + '.bin')
    $memPath = Join-Path $InputDirectory ($tensorName + '.mem')
    foreach ($required in @($binPath, $memPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Tensor file is missing: $required"
        }
    }
    $binBytes = [IO.File]::ReadAllBytes($binPath)
    $actualBinHash = (Get-FileHash -LiteralPath $binPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualBinHash -ne $entry.sha256_bin.ToLowerInvariant()) {
        throw "$tensorName.bin SHA-256 mismatch: manifest $($entry.sha256_bin) actual $actualBinHash"
    }
    $memLines = @(Get-Content -LiteralPath $memPath -Encoding ascii | Where-Object { $_ -ne '' })
    if ($memLines.Count -ne [int]$entry.word_count) {
        throw "$tensorName.mem word count $($memLines.Count) differs from manifest $($entry.word_count)"
    }
    $memBytes = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($line in $memLines) {
        if ($line -notmatch '^[0-9a-fA-F]{4}$') { throw "$tensorName.mem contains an invalid 16-bit word: $line" }
        $word = [Convert]::ToUInt16($line, 16)
        [void]$memBytes.Add([byte]($word -band 0xff))
        [void]$memBytes.Add([byte](($word -shr 8) -band 0xff))
    }
    if ($memBytes.Count -ne $binBytes.Length) { throw "$tensorName.mem and .bin byte counts differ" }
    for ($i = 0; $i -lt $binBytes.Length; $i++) {
        if ($memBytes[$i] -ne $binBytes[$i]) { throw "$tensorName.mem differs from $tensorName.bin at byte $i" }
    }
    $tensorBinary[$tensorName] = $binBytes
    $tensorShapes[$tensorName] = @($entry.shape)
    $verifiedTensors += $tensorName
    $tensorReports += [pscustomobject][ordered]@{
        name = $tensorName
        shape = @($entry.shape)
        bin_bytes = $binBytes.Length
        mem_words = $memLines.Count
        bin_sha256 = $actualBinHash
    }
}

$expectedCases = @('hand_2x2', 'rounding_nonfused', 'k32_boundary')
$actualCaseNames = @($traceDocument.cases.PSObject.Properties.Name)
if ((Compare-Object $expectedCases $actualCaseNames)) {
    throw "Expected cases differ: $($actualCaseNames -join ', ')"
}
$caseTensorMap = @{
    hand_2x2 = @{ x = 'x'; w = 'w'; bias = 'bias'; result = 'expected' }
    rounding_nonfused = @{ x = 'rounding_x'; w = 'rounding_w'; bias = 'rounding_bias'; result = 'rounding_expected' }
    k32_boundary = @{ x = 'tile_x'; w = 'tile_w'; bias = 'tile_bias'; result = 'tile_expected' }
}

$traceRows = @()
$stepVectorLines = New-Object 'System.Collections.Generic.List[string]'
$caseSummaries = @()
$caseIds = @{ hand_2x2 = 0; rounding_nonfused = 1; k32_boundary = 2 }
foreach ($caseProperty in @($traceDocument.cases.PSObject.Properties)) {
    $caseName = $caseProperty.Name
    $case = $caseProperty.Value
    $rows = [int]$case.x_shape[0]
    $depth = [int]$case.x_shape[1]
    $columns = [int]$case.w_shape[1]
    $tensorNames = $caseTensorMap[$caseName]
    if ((@($tensorShapes[$tensorNames.x]) -join ',') -ne "$rows,$depth" -or
        (@($tensorShapes[$tensorNames.w]) -join ',') -ne "$depth,$columns" -or
        (@($tensorShapes[$tensorNames.bias]) -join ',') -ne "1,$columns" -or
        (@($tensorShapes[$tensorNames.result]) -join ',') -ne "$rows,$columns") {
        throw "$caseName trace shapes do not match the hashed tensor images"
    }
    $xImage = $tensorBinary[$tensorNames.x]
    $wImage = $tensorBinary[$tensorNames.w]
    $biasImage = $tensorBinary[$tensorNames.bias]
    $resultImage = $tensorBinary[$tensorNames.result]
    $cells = @($case.cells)
    if ($cells.Count -ne ($rows * $columns)) { throw "$caseName cell count is incorrect" }
    foreach ($cell in $cells) {
        $cellRow = [int]$cell.row
        $cellColumn = [int]$cell.column
        $steps = @($cell.steps)
        if ($steps.Count -ne $depth) { throw "$caseName cell ($cellRow,$cellColumn) step count is incorrect" }
        Assert-Hex32 $cell.bias_bits "$caseName bias"
        Assert-Hex32 $cell.initial_acc_bits "$caseName initial accumulator"
        Assert-Hex32 $cell.acc_before_bias_bits "$caseName acc_before_bias"
        Assert-Hex32 $cell.result_bits "$caseName result"
        if ($cell.initial_acc_bits -ne '0x00000000') { throw "$caseName initial accumulator is not +0" }
        $binaryBias = Get-Binary32Word $biasImage $cellColumn "$caseName bias"
        $binaryResult = Get-Binary32Word $resultImage (($cellRow * $columns) + $cellColumn) "$caseName result"
        if ($cell.bias_bits.ToLowerInvariant() -ne $binaryBias) { throw "$caseName bias trace differs from its hashed .bin image" }
        if ($cell.result_bits.ToLowerInvariant() -ne $binaryResult) { throw "$caseName final trace result differs from its hashed .bin image" }
        $previousAccumulator = $cell.initial_acc_bits
        for ($index = 0; $index -lt $steps.Count; $index++) {
            $step = $steps[$index]
            if ([int]$step.k -ne $index) { throw "$caseName cell ($cellRow,$cellColumn) K order is incorrect" }
            Assert-Hex32 $step.x_bits "$caseName x at k=$index"
            Assert-Hex32 $step.w_bits "$caseName w at k=$index"
            Assert-Hex32 $step.acc_before_bits "$caseName acc_before at k=$index"
            Assert-Hex32 $step.product_bits "$caseName product at k=$index"
            Assert-Hex32 $step.acc_after_bits "$caseName acc_after at k=$index"
            if ($step.acc_before_bits.ToLowerInvariant() -ne $previousAccumulator.ToLowerInvariant()) {
                throw "$caseName cell ($cellRow,$cellColumn) accumulator chain breaks at k=$index"
            }
            $binaryX = Get-Binary32Word $xImage (($cellRow * $depth) + $index) "$caseName X"
            $binaryW = Get-Binary32Word $wImage (($index * $columns) + $cellColumn) "$caseName W"
            if ($step.x_bits.ToLowerInvariant() -ne $binaryX) { throw "$caseName X trace differs from its hashed .bin image at row=$cellRow k=$index" }
            if ($step.w_bits.ToLowerInvariant() -ne $binaryW) { throw "$caseName W trace differs from its hashed .bin image at k=$index column=$cellColumn" }
            $isLast = ($index -eq ($steps.Count - 1))
            $traceRows += [pscustomobject][ordered]@{
                status = 'software_candidate'
                case = $caseName
                row = $cellRow
                column = $cellColumn
                k = $index
                x_bits = $step.x_bits
                w_bits = $step.w_bits
                acc_before_bits = $step.acc_before_bits
                product_bits = $step.product_bits
                acc_after_bits = $step.acc_after_bits
                bias_valid = [int]$isLast
                bias_bits = if ($isLast) { $cell.bias_bits } else { '' }
                acc_before_bias_bits = if ($isLast) { $cell.acc_before_bias_bits } else { '' }
                result_bits = if ($isLast) { $cell.result_bits } else { '' }
                k32_save = [int]($depth -gt 32 -and $index -eq 31)
                k32_restore = [int]($depth -gt 32 -and $index -eq 32)
            }
            $biasField = if ($isLast) { $cell.bias_bits.Substring(2) } else { '00000000' }
            $preBiasField = if ($isLast) { $cell.acc_before_bias_bits.Substring(2) } else { '00000000' }
            $resultField = if ($isLast) { $cell.result_bits.Substring(2) } else { '00000000' }
            $k32Save = [int]($depth -gt 32 -and $index -eq 31)
            $k32Restore = [int]($depth -gt 32 -and $index -eq 32)
            $vectorLine = '{0} {1} {2} {3} {4} {5} {6} {7} {8} {9} {10} {11} {12} {13} {14}' -f `
                $caseIds[$caseName], $cellRow, $cellColumn, $index,
                $step.x_bits.Substring(2), $step.w_bits.Substring(2),
                $step.acc_before_bits.Substring(2), $step.product_bits.Substring(2),
                $step.acc_after_bits.Substring(2), $biasField, $preBiasField,
                $resultField, [int]$isLast, $k32Save, $k32Restore
            [void]$stepVectorLines.Add($vectorLine)
            $previousAccumulator = $step.acc_after_bits
        }
        if ($cell.acc_before_bias_bits.ToLowerInvariant() -ne $previousAccumulator.ToLowerInvariant()) {
            throw "$caseName cell ($cellRow,$cellColumn) pre-bias accumulator differs from its final K step"
        }
    }
    $caseSummaries += [pscustomobject][ordered]@{ name = $caseName; shape = @($rows, $depth, $columns); cells = $cells.Count; steps = $cells.Count * $depth }
}

$csvPath = Join-Path $OutputDirectory 'fp32_trace_reference.csv'
$csvLines = @($traceRows | ConvertTo-Csv -NoTypeInformation)
Set-Content -LiteralPath $csvPath -Value $csvLines -Encoding utf8
$vectorPath = Join-Path $OutputDirectory 'fp32_step_vectors.txt'
Set-Content -LiteralPath $vectorPath -Value $stepVectorLines -Encoding ascii
$report = [ordered]@{
    status = 'CANDIDATE software reference; not a hardware PE trace'
    input_directory = $InputDirectory
    expected_traces_sha256 = $actualTraceHash
    tensors_verified = $verifiedTensors
    tensor_files = $tensorReports
    cases = $caseSummaries
    csv_rows = $traceRows.Count
    output_csv = $csvPath
    testbench_vector_format = '15 whitespace-separated fields, no header: case_id row column k x_bits w_bits acc_before_bits product_bits acc_after_bits bias_bits acc_before_bias_bits result_bits last_k k32_save k32_restore; binary32 fields are 8-digit hex without 0x'
    testbench_vector_file = $vectorPath
}
$reportPath = Join-Path $OutputDirectory 'validation_report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Output "PASS reference vectors validated: tensors=$($verifiedTensors.Count) trace_rows=$($traceRows.Count)"
Write-Output "CSV: $csvPath"
Write-Output "Testbench vectors: $vectorPath"
Write-Output "Report: $reportPath"
