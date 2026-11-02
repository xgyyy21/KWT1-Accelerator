param(
    [string]$RootOutputDirectory = 'build/hardware_independent_checks_2026-11-02_v1',
    [string]$IcarusBin = '.tools/iverilog/bin'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$root = [IO.Path]::GetFullPath((Join-Path $projectRoot $RootOutputDirectory))
if (!$root.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) { throw 'Output directory must be inside project.' }
if (Test-Path -LiteralPath $root) { throw "Refusing to overwrite evidence: $root" }
New-Item -ItemType Directory -Path $root | Out-Null
$common = @{ IcarusBin=$IcarusBin }
$runs = @(
  @{Name='wrapper_protocol'; Script='Test-KwtE203NiceWrapper.ps1'},
  @{Name='wrapper_continuous'; Script='Test-KwtE203NiceWrapperContinuous.ps1'},
  @{Name='sram_functional'; Script='Test-SramAdapterFunctional.ps1'},
  @{Name='top_continuous'; Script='Test-SramAcceleratorTop.ps1'; Extra=@{SkipFullLayer=$true}},
  @{Name='top_exceptions'; Script='Test-SramTopExceptions.ps1'},
  @{Name='sram_pin_contract'; Script='Test-SramAdapterPins.ps1'},
  @{Name='shared_loader'; Script='Test-KwtSharedSramLoader.ps1'}
)
$results = @()
foreach ($run in $runs) {
  $out = Join-Path $RootOutputDirectory $run.Name
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $run.Script),'-OutputDirectory',$out,'-IcarusBin',$IcarusBin)
  if ($run.ContainsKey('Extra') -and $run.Extra.SkipFullLayer) { $args += '-SkipFullLayer' }
  $started = Get-Date
  & powershell.exe @args
  $code = $LASTEXITCODE
  $results += [pscustomobject]@{Name=$run.Name;Script=$run.Script;ExitCode=$code;Started=$started.ToString('o');Finished=(Get-Date).ToString('o')}
  if ($code -ne 0) { throw "Independent check failed: $($run.Name)" }
}
[ordered]@{Created=(Get-Date).ToString('o');Scope='Hardware-side functional/robustness tests; synthesis intentionally skipped';Tests=$results;SynthesisSkipped=$true;E203SoCIntegrated=$false;VendorSramTimingModel=$false} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'status.json') -Encoding UTF8
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -ne 'evidence_sha256.csv' } | Sort-Object FullName | ForEach-Object {[pscustomobject]@{Path=$_.FullName.Substring($root.Length+1).Replace('\','/');Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}} | Export-Csv (Join-Path $root 'evidence_sha256.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Evidence: $root"
