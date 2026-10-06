param([string]$Godot = 'D:\Softwares\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe', [switch]$Editor)
$projectPath = $PSScriptRoot
if (!(Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Set -Godot to your Godot 4.6 executable." }
if ($Editor) { & $Godot --editor --path $projectPath } else { & $Godot --path $projectPath }
