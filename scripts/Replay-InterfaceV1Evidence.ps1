param(
    [Parameter(Mandatory=$true)][string]$Packet,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$Iverilog,
    [Parameter(Mandatory=$true)][string]$Vvp,
    [string[]]$Tests = @()
)
$ErrorActionPreference='Stop'
$packetRoot=(Resolve-Path -LiteralPath $Packet).Path
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
$compiler=(Resolve-Path -LiteralPath $Iverilog).Path
$simulator=(Resolve-Path -LiteralPath $Vvp).Path
if(Test-Path -LiteralPath $outputRoot){throw 'Replay output already exists; refusing overwrite'}
$verified=0
foreach($line in Get-Content -LiteralPath (Join-Path $packetRoot 'SHA256SUMS.txt')){
    if($line -notmatch '^([0-9a-f]{64})  (.+)$'){throw "Invalid hash line: $line"}
    $expected=$Matches[1];$relative=$Matches[2]
    $candidate=[IO.Path]::GetFullPath((Join-Path $packetRoot $relative))
    if(-not $candidate.StartsWith($packetRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Path outside packet'}
    if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw "Hash mismatch: $relative"}
    $verified++
}
$manifest=Get-Content -LiteralPath (Join-Path $packetRoot 'manifest.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $outputRoot | Out-Null
foreach($folder in @('rtl','tb','software_snapshot')){
    Copy-Item -LiteralPath (Join-Path $packetRoot $folder) -Destination (Join-Path $outputRoot $folder) -Recurse
}
foreach($folder in @('logs','run')){New-Item -ItemType Directory -Path (Join-Path $outputRoot $folder) | Out-Null}
function Invoke-Tool([string]$exe,[string[]]$argv,[string]$log){
    $ErrorActionPreference='Continue'
    $lines=@(& $exe @argv 2>&1 | ForEach-Object {"$_"});$code=$LASTEXITCODE
    $lines | Out-File -LiteralPath $log -Encoding utf8
    [pscustomobject]@{exit=$code;lines=$lines}
}
Push-Location $outputRoot
try{
    $results=@()
    foreach($test in $manifest.tests){
        $name=$test.test
        if($Tests.Count -gt 0 -and $Tests -notcontains $name){continue}
        if($name -notmatch '^[a-zA-Z0-9_]+$'){throw 'Invalid test name'}
        $compile=Invoke-Tool $compiler @('-g2012','-s',$name,'-o',"run/$name.vvp",'-f','rtl/files.f',"tb/$name.sv") "logs/$name.compile.log"
        $sim=$null
        if($compile.exit -eq 0){$sim=Invoke-Tool $simulator @("run/$name.vvp") "logs/$name.sim.log"}
        $pass=$compile.exit -eq 0 -and $null -ne $sim -and $sim.exit -eq 0 -and ($sim.lines -match '\bPASS\b').Count -gt 0
        $results+=[pscustomobject]@{test=$name;pass=$pass;compile_exit=$compile.exit;simulation_exit=$(if($null -ne $sim){$sim.exit}else{$null})}
        Write-Output "$name PASS=$pass"
    }
    if($results.Count -eq 0){throw 'No matching replay tests'}
    $results | ConvertTo-Json -Depth 4 | Out-File -LiteralPath logs/replay_results.json -Encoding utf8
    Write-Output "Verified packet files=$verified"
    if(@($results | Where-Object { -not $_.pass }).Count){throw 'Replay tests failed'}
}finally{Pop-Location}
