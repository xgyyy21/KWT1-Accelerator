param(
    [int]$SimulatorProcessId,
    [string]$RunLog,
    [string]$Output
)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $Output) { throw "Refusing to overwrite $Output" }
$process=Get-Process -Id $SimulatorProcessId
if ($process.ProcessName -ne 'vvp') { throw 'Target is not a vvp simulator' }
$started=$process.StartTime
$stream=New-Object IO.StreamWriter($Output,$false,(New-Object Text.UTF8Encoding($false)))
try {
    while ($true) {
        $current=Get-Process -Id $SimulatorProcessId -ErrorAction SilentlyContinue
        if (!$current -or $current.StartTime -ne $started) { break }
        $sample=[ordered]@{
            timestamp=(Get-Date).ToString('o')
            pid=$SimulatorProcessId
            simulator_start=$started.ToString('o')
            elapsed_seconds=((Get-Date)-$started).TotalSeconds
            cpu_seconds=$current.TotalProcessorTime.TotalSeconds
            last_progress=[string](Get-Content -LiteralPath $RunLog -Tail 1)
        }
        $stream.WriteLine(($sample | ConvertTo-Json -Compress))
        $stream.Flush()
        Write-Output ("MONITOR wall={0:N1}s cpu={1:N1}s {2}" -f $sample.elapsed_seconds,$sample.cpu_seconds,$sample.last_progress)
        Start-Sleep -Seconds 15
    }
    Write-Output 'Simulator exited; inspect original process exit code and final log.'
} finally { $stream.Dispose() }
