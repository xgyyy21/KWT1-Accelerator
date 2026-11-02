param(
    [string]$OutputDirectory = 'build/kwt_e203_nice_wrapper_2026-11-02_v2',
    [string]$IcarusBin = '..\..\.tools\iverilog\bin'
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
if (!(Test-Path -LiteralPath $iverilog) -or !(Test-Path -LiteralPath $vvp)) { throw "Icarus/vvp missing under $IcarusBin" }
$versionAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$iverilogVersion = (& $iverilog -V 2>&1 | Select-Object -First 1).ToString()
$vvpVersion = (& $vvp -V 2>&1 | Select-Object -First 1).ToString()
$ErrorActionPreference = $versionAction
New-Item -ItemType Directory -Path $outPath | Out-Null
$image = Join-Path $outPath 'kwt1_e203_nice_wrapper_tb.vvp'
$compileArgs = @('-g2012','-Wall','-s','kwt1_e203_nice_wrapper_tb','-o',$image,
    '-c',(Join-Path $projectRoot 'rtl/files.f'),
    (Join-Path $projectRoot 'tb/kwt1_e203_nice_wrapper_tb.sv'))
$compileCommand = 'iverilog ' + ($compileArgs -join ' ')
$compileCommand | Set-Content -LiteralPath (Join-Path $outPath 'commands.txt') -Encoding UTF8
$oldErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$compileOutput = & $iverilog @compileArgs 2>&1
$compileExit = $LASTEXITCODE
$compileOutput | ForEach-Object { $_.ToString() } | Set-Content -LiteralPath (Join-Path $outPath 'compile.log') -Encoding UTF8
$ErrorActionPreference = $oldErrorAction
if ($compileExit -ne 0) { throw "Icarus compile failed with exit code $compileExit" }
('vvp ' + $image) | Add-Content -LiteralPath (Join-Path $outPath 'commands.txt') -Encoding UTF8
$ErrorActionPreference = 'Continue'
$simulationOutput = & $vvp $image 2>&1
$simulationExit = $LASTEXITCODE
$simulationOutput | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $outPath 'simulation.log')
$ErrorActionPreference = $oldErrorAction
if ($simulationExit -ne 0) { throw "vvp failed with exit code $simulationExit" }
$status = [ordered]@{
    Created = (Get-Date).ToString('o')
    CompileExitCode = $compileExit
    SimulationExitCode = $simulationExit
    IcarusVersion = $iverilogVersion
    VvpVersion = $vvpVersion
    CompileCommand = $compileCommand
    SimulationCommand = ('vvp ' + $image)
    Passed = $true
    Scope = 'Standalone KWT-1 E203 NICE wrapper mock protocol test'
    RealE203Integrated = $false
    NICEIcbPayloadActive = $false
    Note = 'Opcode/funct defaults are test parameters, not a frozen software ABI.'
}
$status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outPath 'status.json') -Encoding UTF8
$sourceFiles = @((Get-Content -LiteralPath (Join-Path $projectRoot 'rtl/files.f') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and !$_.StartsWith('//') }))
$sourceFiles += @('rtl/files.f','tb/kwt1_e203_nice_wrapper_tb.sv',
                  'scripts/Test-KwtE203NiceWrapper.ps1')
$sourceFiles = @($sourceFiles | Sort-Object -Unique)
$sourceManifest = foreach ($relative in $sourceFiles) {
    $sourcePath = Join-Path $projectRoot $relative
    if (!(Test-Path -LiteralPath $sourcePath)) { throw "Missing source file: $relative" }
    [pscustomobject]@{
        Path = $relative
        Bytes = (Get-Item -LiteralPath $sourcePath).Length
        SHA256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    }
}
$sourceManifest | Export-Csv -LiteralPath (Join-Path $outPath 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
Get-ChildItem -LiteralPath $outPath -File | Where-Object Name -ne 'evidence_sha256.csv' | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ Path = $_.Name; Bytes = $_.Length; SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
} | Export-Csv -LiteralPath (Join-Path $outPath 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Evidence: $outPath"
