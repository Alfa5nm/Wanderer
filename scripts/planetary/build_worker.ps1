param([string]$Python = '.tools/terrain_python/Scripts/python.exe')
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
    & $Python -m PyInstaller --noconfirm --onedir --console --name mars_terrain_worker --distpath planetary_map/tools --workpath .tools/worker_build --specpath scripts/planetary --collect-all rasterio scripts/planetary/terrain_worker.py
    if ($LASTEXITCODE -ne 0) { throw 'Terrain worker packaging failed.' }
    $packageRoot = (& $Python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])').Trim()
    $basePrefix = (& $Python -c 'import sys; print(sys.base_prefix)').Trim()
    $noticesRoot = Join-Path $workspace 'planetary_map/tools/mars_terrain_worker/THIRD_PARTY_LICENSES'
    New-Item -ItemType Directory -Force -Path $noticesRoot | Out-Null
    Get-ChildItem -LiteralPath $packageRoot -Directory | Where-Object { $_.Name -match '^(numpy|pillow|rasterio|affine|attrs|click|pyparsing|certifi|pyinstaller)-.*dist-info$' } | ForEach-Object {
        $noticePackage = $_
        Get-ChildItem -LiteralPath $noticePackage.FullName -File -Recurse | Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE)' } | ForEach-Object {
            $noticeRelative = $_.FullName.Substring($noticePackage.FullName.Length + 1)
            $noticeDestination = Join-Path (Join-Path $noticesRoot $noticePackage.Name) $noticeRelative
            New-Item -ItemType Directory -Force -Path (Split-Path $noticeDestination) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $noticeDestination
        }
    }
    Copy-Item -LiteralPath (Join-Path $basePrefix 'LICENSE.txt') -Destination (Join-Path $noticesRoot 'PYTHON_LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $packageRoot 'rasterio/gdal_data/LICENSE.TXT') -Destination (Join-Path $noticesRoot 'GDAL_LICENSE.txt')
    Set-Content -LiteralPath planetary_map/tools/.gdignore -Value ''
} finally { Pop-Location }
