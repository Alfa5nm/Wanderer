"""Bounded, contiguous viewport imagery from NASA Trek's published CTX endpoint.

Tile geometry is verified against the linked ArcGIS tileInfo (512px, -180/+90
origin, level-0 resolution 0.3515625 degrees). No per-tile contrast adjustment.
This preliminary uncontrolled visible mosaic supplies imagery only, never heights.
"""
import concurrent.futures
import hashlib
import io
import math
from pathlib import Path
import urllib.request
import numpy as np
from PIL import Image

PRODUCT = 'CTX_beta01_uncontrolled_5m_Caltech'
ENDPOINT = 'https://astro.arcgis.com/arcgis/rest/services/OnMars/CTX/MapServer/tile'
CATALOG = 'https://trek.nasa.gov/tiles/Mars/EQ/' + PRODUCT + '/1.0.0/WMTSCapabilities.xml'


def assemble(bounds, size, fetch=None):
    west, south, east, north = bounds
    # Choose actual source sampling near the output pixel scale, limit concurrent
    # decoding/storage to at most 36 tiles. Cached prepared atlases own disk budget.
    level = max(0, min(12, math.ceil(math.log2(180 * size / (512 * max(east-west, north-south))))))
    while True:
        step = 180 / 2**level
        x0, x1 = math.floor((west+180)/step), math.ceil((east+180)/step)
        y0, y1 = math.floor((90-north)/step), math.ceil((90-south)/step)
        if (x1-x0)*(y1-y0) <= 36 or level == 0:
            break
        level -= 1
    canvas = Image.new('RGBA', ((x1-x0)*512, (y1-y0)*512))
    provenance, failures = [], []
    def read(tile):
        x, y = tile
        url = f'{ENDPOINT}/{level}/{y}/{x}'
        try:
            if fetch:
                raw = fetch(url)
            else:
                with urllib.request.urlopen(url, timeout=15) as response:
                    raw = response.read(4*1024*1024+1)
            if len(raw) > 4*1024*1024:
                raise ValueError('Oversize source tile')
            image = Image.open(io.BytesIO(raw))
            if image.size != (512,512):
                raise ValueError('Unexpected source grid')
            return x, y, image.convert('RGBA'), dict(url=url, sha256=hashlib.sha256(raw).hexdigest())
        except Exception as error:
            return x, y, None, dict(url=url, error=str(error))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for x, y, image, record in pool.map(read, [(x,y) for y in range(y0,y1) for x in range(x0,x1)]):
            if image is None:
                failures.append(record)
            else:
                canvas.paste(image, ((x-x0)*512, (y-y0)*512))
                provenance.append(record)
    # Pixel-edge crop: adjacent source tiles are joined before filtering, so no
    # repeated rectangle feather or exposure boundary appears at internal seams.
    extent = ((west+180)/step*512-x0*512, (90-north)/step*512-y0*512,
              (east+180)/step*512-x0*512, (90-south)/step*512-y0*512)
    image = canvas.transform((size,size), Image.Transform.EXTENT, extent, Image.Resampling.BICUBIC)
    return image, level, provenance, failures


def prepare(job):
    image, level, sources, failures = assemble(job['bounds'], int(job['size']))
    if not sources:
        raise RuntimeError('Surrounding CTX service unavailable; existing imagery retained')
    path = Path(job['output'])
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.partial')
    image.convert('LA').save(temporary, format='PNG')
    temporary.replace(path)
    valid = np.asarray(image)[:,:,3] > 127
    spacing = max(job['bounds'][2]-job['bounds'][0], job['bounds'][3]-job['bounds'][1])*math.pi/180*3396190/job['size']
    return dict(kind='imagery', path=str(path), product_id=PRODUCT,
        title='CTX visible mosaic (preliminary, uncontrolled; Caltech)',
        bounds=job['bounds'], width=image.width, height=image.height,
        source_spacing_m=5, prepared_spacing_m=max(spacing,180/2**level/512*math.pi/180*3396190),
        projection='Mars 2000 sphere geographic, planetocentric, east-positive',
        vertical_datum='not applicable', source_url=ENDPOINT, catalog_url=CATALOG,
        observation_dates=[], absolute_vertical_accuracy_m=None,
        accuracy_note='Preliminary uncontrolled mosaic; positional accuracy not established here',
        imagery_note='Visible grayscale. Baked illumination and source seams remain; no per-tile contrast stretch.',
        valid_fraction=float(valid.mean()), role='view_background', wmts_level=level,
        source_tiles=sources, missing_tiles=failures,
        sha256=hashlib.sha256(path.read_bytes()).hexdigest())
