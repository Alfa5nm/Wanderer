param([string]$Godot = 'D:\Softwares\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe', [switch]$Controls)
Push-Location $PSScriptRoot
try {
    & $Godot --headless --editor --path . --import *> evidence/import.log
    & $Godot --headless --path . --script tests/asset_audit.gd *> evidence/asset_audit.log
    if ($LASTEXITCODE -ne 0) { throw 'Asset reimport audit failed.' }
    & $Godot --headless --path . --fixed-fps 120 --script tests/run.gd *> evidence/validation.log
    if ($LASTEXITCODE -ne 0) { throw 'Physics run failed.' }
    $overridePath = Join-Path $PSScriptRoot 'override.cfg'
    if (Test-Path -LiteralPath $overridePath) { throw 'Preserving existing override.cfg; solver comparison not run.' }
    try {
        @'
[physics]
jolt_physics_3d/simulation/velocity_steps=40
jolt_physics_3d/simulation/position_steps=16
'@ | Set-Content -LiteralPath $overridePath
        & $Godot --headless --path . --fixed-fps 120 --script tests/run.gd -- --solver-only *> evidence/solver.log
        if ($LASTEXITCODE -ne 0) { throw 'Solver comparison failed.' }
    } finally { Remove-Item -LiteralPath $overridePath -ErrorAction SilentlyContinue }
    if ($Controls) {
        & $Godot --path . --fixed-fps 120 --script tests/ui_run.gd *> evidence/controls.log
        if ($LASTEXITCODE -ne 0) { throw 'Control run failed.' }
    }
    Write-Output 'Runs complete. Inspect evidence/validation.json and run scripts/report_validation.py for acceptance results.'
} finally { Pop-Location }
