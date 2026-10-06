param(
    [string]$GodotPath = 'D:\Softwares\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe',
    [switch]$LocalTerrain
)
$projectPath = Split-Path -Parent $PSScriptRoot
if (!(Test-Path -LiteralPath $GodotPath)) { throw 'Set -GodotPath to your Godot 4.6 executable.' }
$launchArgs = @('--path', ('"' + $projectPath + '"'), '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan')
if ($LocalTerrain) { $launchArgs += 'res://procedural_terrain/mission.tscn' }
# A process-local override: project.godot and the default renderer stay unchanged.
Start-Process -FilePath $GodotPath -ArgumentList $launchArgs -WindowStyle Hidden
