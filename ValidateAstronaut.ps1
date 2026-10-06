param(
    [string]$Godot = 'D:\Softwares\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe',
    [string]$Python = 'C:\Python314\python.exe',
    [switch]$Captures,
    [switch]$Rover
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$failuresTask = @()
& $Godot --headless --path . --editor --import --quit *> evidence/astronaut_batch_import.log
if ($LASTEXITCODE -ne 0) { $failuresTask += 'imports' }
& $Python tests/verify_astronaut_asset.py
if ($LASTEXITCODE -ne 0) { $failuresTask += 'asset' }
foreach ($testTask in @('astronaut_contacts','astronaut_scout_run','cinematic_run','globe_run','procedural_run')) {
    & $Godot --headless --path . --max-fps 120 --script "res://tests/$testTask.gd" *> "evidence/astronaut_batch_$testTask.log"
    if ($LASTEXITCODE -ne 0) { $failuresTask += $testTask }
    Write-Output "$testTask exit=$LASTEXITCODE"
}
if ($Rover) {
    & $Godot --headless --path . --fixed-fps 240 --script res://tests/run.gd *> evidence/astronaut_batch_rover.log
    if ($LASTEXITCODE -ne 0) { $failuresTask += 'rover' }
    Write-Output 'Rover measurements saved; the existing external source checksum discrepancy remains documented.'
}
if ($Captures) {
    foreach ($testTask in @('astronaut_gait_review','scout_capture','scout_follow_route','scout_final_review','scout_release_smoke')) {
        & $Godot --path . --script "res://tests/$testTask.gd" *> "evidence/astronaut_batch_$testTask.log"
        if ($LASTEXITCODE -ne 0) { $failuresTask += $testTask }
        Write-Output "$testTask exit=$LASTEXITCODE"
    }
}
if ($failuresTask.Count) { throw ('Failed checks: '+($failuresTask -join ', ')) }
Write-Output 'Astronaut/scout batch complete. Read docs/ASTRONAUT_SCOUT_VERIFICATION.md and evidence JSON for scoped results and limits.'
