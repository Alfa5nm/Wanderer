param([Parameter(Mandatory=$true)][string]$GodotPath, [switch]$VisualOnly, [switch]$WarmCache)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
$evidenceDirectory = Join-Path $projectDirectory 'evidence'
if (-not $VisualOnly) {
    foreach ($entry in @(@('procedural_run','numeric'), @('cinematic_run','camera'), @('globe_run','globe'), @('run','rover'))) {
        $arguments = @('--headless','--path',$projectDirectory,'--script',"tests/$($entry[0]).gd")
        if ($entry[0] -eq 'run') { $arguments += @('--fixed-fps','240') }
        & $GodotPath @arguments *> (Join-Path $evidenceDirectory "dusty_$($entry[1]).log")
        if ($LASTEXITCODE -ne 0) { Write-Warning "$($entry[1]) returned $LASTEXITCODE; inspect saved assertions and diagnostics." }
    }
}
$stdoutPath = Join-Path $evidenceDirectory 'dusty_capture.log'
$stderrPath = Join-Path $evidenceDirectory 'dusty_capture_errors.log'
$captureArguments = @('--path',('"'+$projectDirectory+'"'),'--script','tests/dusty_capture.gd')
if ($WarmCache) { $captureArguments += @('--','--warm-capture') }
$captureProcess = Start-Process -FilePath $GodotPath -ArgumentList $captureArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$samples = [System.Collections.Generic.List[object]]::new()
$capturePid = 0
$started = Get-Date
while (-not $captureProcess.HasExited) {
    if ($capturePid -eq 0 -and (Test-Path -LiteralPath $stdoutPath)) {
        $log = Get-Content -LiteralPath $stdoutPath -Raw
        if ($log -match 'DUSTY_PID\s+(\d+)') { $capturePid = [int]$Matches[1] }
    }
    if ($capturePid -gt 0) {
        $observed = Get-Process -Id $capturePid -ErrorAction SilentlyContinue
        if ($null -ne $observed) {
            $samples.Add(@{seconds=((Get-Date)-$started).TotalSeconds; resident_mib=$observed.WorkingSet64/1MB; private_mib=$observed.PrivateMemorySize64/1MB; peak_resident_mib=$observed.PeakWorkingSet64/1MB})
        }
    }
    Start-Sleep -Milliseconds 500
    $captureProcess.Refresh()
}
$captureProcess.WaitForExit()
@{pid=$capturePid; exit_code=$captureProcess.ExitCode; samples=$samples; duration_seconds=((Get-Date)-$started).TotalSeconds} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'dusty_process_memory.json')
Write-Output "Rendered batch finished with exit code $($captureProcess.ExitCode). Inspect dusty_visual_checks.json and error log."
