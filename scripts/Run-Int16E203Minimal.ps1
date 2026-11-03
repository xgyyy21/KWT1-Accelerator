[CmdletBinding()]
param(
  [string]$VectorDir = "handoff/int16_e203_minimal_2026-11-03",
  [string]$EvidenceDir = "handoff/evidence/int16_e203_minimal_2026-11-04"
)

$ErrorActionPreference = "Continue"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$iverilogCandidates = @((Join-Path $PSScriptRoot "..\..\..\.tools\iverilog\bin\iverilog.exe"))
if ($env:COMPETITION_TOOLS) {
  $iverilogCandidates += (Join-Path $env:COMPETITION_TOOLS "iverilog\bin\iverilog.exe")
}
$iverilog = $iverilogCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
$vvpCandidates = @((Join-Path $PSScriptRoot "..\..\..\.tools\iverilog\bin\vvp.exe"))
if ($env:COMPETITION_TOOLS) {
  $vvpCandidates += (Join-Path $env:COMPETITION_TOOLS "iverilog\bin\vvp.exe")
}
$vvp = $vvpCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $iverilog -or -not $vvp) {
  throw "Icarus Verilog was not found. Set COMPETITION_TOOLS or install it under D:\competition\.tools."
}

$evidence = Join-Path $repo $EvidenceDir
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$simv = Join-Path $evidence "int16_e203_minimal.simv"
$compileLog = Join-Path $evidence "compile.log"
$runLog = Join-Path $evidence "run.log"
$trace = Join-Path $evidence "int16_e203_minimal_trace.csv"
$status = Join-Path $evidence "int16_e203_minimal_status.csv"

Push-Location $repo
try {
  & $iverilog -g2012 -s int16_e203_minimal_tb -o $simv -f integration/int16_e203_minimal.f 2>&1 |
    Tee-Object -FilePath $compileLog
  if ($LASTEXITCODE -ne 0) { throw "Icarus compilation failed with exit code $LASTEXITCODE" }

  & $vvp $simv "+vec_dir=$VectorDir" "+trace=$trace" "+status=$status" 2>&1 |
    Tee-Object -FilePath $runLog
  if ($LASTEXITCODE -ne 0) { throw "Simulation failed with exit code $LASTEXITCODE" }

  $hashes = @($compileLog, $runLog, $trace, $status) | ForEach-Object {
    $item = Get-Item -LiteralPath $_
    [ordered]@{ file = $item.Name; bytes = $item.Length;
      sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLower() }
  }
  $hashes | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $evidence "SHA256.json") -Encoding UTF8
  Write-Output "PASS: evidence written to $evidence"
}
finally {
  Pop-Location
}
