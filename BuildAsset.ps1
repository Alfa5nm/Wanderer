param([string]$Blender = 'C:\Program Files\Blender Foundation\Blender 5.0\blender.exe', [string]$Source = 'D:\Projects\Competitions\NASA APPS CHALLENGE 2026\Research papers\Mars Rover\Curiosity_Blender_Research_Pack\NASA_Curiosity_Clean.blend')
& $Blender --background $Source --python-exit-code 1 --python (Join-Path $PSScriptRoot 'scripts/export_rover.py')
if ($LASTEXITCODE -ne 0) { throw 'Blender export failed; inspect output.' }
