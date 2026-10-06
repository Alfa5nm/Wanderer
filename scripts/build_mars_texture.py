"""Build the bundled 4K mosaic from NASA Mars Trek WMTS level 3.
Requires Pillow; run explicitly, never required at game runtime.
"""
import concurrent.futures
import hashlib
import io
import json
import time
import urllib.request
from pathlib import Path
from PIL import Image

BASE = "https://trek.nasa.gov/tiles/Mars/EQ/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0/default/default028mm/3"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "planetary_map/assets"

def fetch(pair):
    row, col = pair
    url = f"{BASE}/{row}/{col}.jpg"
    for attempt in range(3):
        try:
            data = urllib.request.urlopen(url, timeout=20).read()
            tile = Image.open(io.BytesIO(data)).convert("RGB")
            if tile.size != (256, 256):
                raise ValueError(f"Unexpected tile dimensions: {url}")
            return row, col, tile, hashlib.sha256(data).hexdigest()
        except Exception:
            if attempt == 2:
                raise
            time.sleep(0.5)

if __name__ == "__main__":
    mosaic = Image.new("RGB", (4096, 2048))
    manifest = {"source": BASE, "projection": "equirectangular", "extent": [-180, -90, 180, 90],
                "credit": "NASA / JPL / USGS, Viking MDIM 2.1; served by NASA Mars Trek", "tiles": []}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        for row, col, tile, digest in executor.map(fetch, [(r, c) for r in range(8) for c in range(16)]):
            mosaic.paste(tile, (col*256, row*256))
            manifest["tiles"].append({"row": row, "column": col, "sha256": digest})
    OUT.mkdir(exist_ok=True, parents=True)
    mosaic.save(OUT / "mars_viking_4k.jpg", quality=95)
    manifest["output_sha256"] = hashlib.sha256((OUT / "mars_viking_4k.jpg").read_bytes()).hexdigest()
    (OUT / "texture_provenance.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("Built 4096 x 2048 NASA Viking mosaic from 128 verified tiles")
