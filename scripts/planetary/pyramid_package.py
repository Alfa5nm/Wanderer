"""GDAL geographic pyramids from already normalized, sourced bundle rasters.

Unlike Web Mercator display tiles, these retain planetocentric coordinates,
numeric radial metres, masks and independent imagery provenance.
"""
import hashlib
import json
import math
from pathlib import Path
import zlib

import numpy as np
from PIL import Image
from rasterio.transform import from_bounds
from rasterio.warp import reproject
from rasterio.enums import Resampling

GEOGRAPHIC = '+proj=longlat +R=3396190 +no_defs'


def write_atomic(path, data):
    temporary = Path(str(path) + '.partial')
    temporary.write_bytes(data)
    temporary.replace(path)


def build(request):
    job = json.loads(Path(request).read_text())
    root = Path(job['source_root'])
    output = Path(job['output'])
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((root / 'manifest.json').read_text())
    west, south, east, north = job['bounds']
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise ValueError('Invalid geographic pyramid bounds')
    minimum, maximum = int(job['min_level']), int(job['max_level'])
    size = int(job.get('size', 512))
    if not 0 <= minimum <= maximum <= 16 or not 256 <= size <= 1024:
        raise ValueError('Unbounded pyramid request')
    addresses = []
    for level in range(minimum, maximum + 1):
        step = 180 / (1 << level)
        x0, x1 = math.floor((west + 180) / step), math.ceil((east + 180) / step)
        y0, y1 = math.floor((90 - north) / step), math.ceil((90 - south) / step)
        for y in range(y0, y1):
            for x in range(x0, x1):
                addresses.append((level, x, y, [-180 + x * step, 90 - (y + 1) * step,
                                                -180 + (x + 1) * step, 90 - y * step]))
    if len(addresses) * len(job['datasets']) > 128:
        raise ValueError('Split preparation into packages of at most 128 tiles')
    records = []
    available = {metadata['id'] for metadata in manifest['datasets']}
    if not set(job['datasets']).issubset(available):
        raise ValueError('Requested source dataset is absent from manifest')
    for metadata in manifest['datasets']:
        if metadata['id'] not in job['datasets']:
            continue
        height, width = metadata['height'], metadata['width']
        if metadata['kind'] == 'elevation':
            source = np.frombuffer(zlib.decompress((root / metadata['path']).read_bytes()), '<f4').reshape(height, width)[None]
            valid = np.isfinite(source[0])
        else:
            source = np.array(Image.open(root / metadata['path']).convert('RGBA'), dtype='float32').transpose(2, 0, 1)
            packed = zlib.decompress((root / metadata['validity_mask_path']).read_bytes())
            valid = np.unpackbits(np.frombuffer(packed, 'uint8'), bitorder='little')[:width * height].reshape(height, width).astype(bool)
        transform = from_bounds(*metadata['bounds'], width, height)
        for level, x, y, bounds in addresses:
            destination = np.full((source.shape[0], size, size), np.nan, dtype='float32')
            matrix = from_bounds(*bounds, size, size)
            for band in range(source.shape[0]):
                values = np.where(valid, source[band], np.nan)
                reproject(values, destination[band], src_transform=transform, src_crs=GEOGRAPHIC,
                          dst_transform=matrix, dst_crs=GEOGRAPHIC, src_nodata=np.nan,
                          dst_nodata=np.nan, resampling=Resampling.bilinear)
            mask = np.zeros((size, size), 'uint8')
            reproject(valid.astype('uint8'), mask, src_transform=transform, src_crs=GEOGRAPHIC,
                      dst_transform=matrix, dst_crs=GEOGRAPHIC, resampling=Resampling.nearest)
            good = mask.astype(bool) & np.isfinite(destination[0])
            if not good.any():
                continue
            stem = f"{metadata['id']}_{level}_{x}_{y}"
            path = output / (stem + ('.height' if metadata['kind'] == 'elevation' else '.tile'))
            if metadata['kind'] == 'elevation':
                raw = np.where(good, destination[0], np.nan).astype('<f4').tobytes()
                write_atomic(path, zlib.compress(raw))
                digest = hashlib.sha256(raw).hexdigest()
            else:
                rgba = np.nan_to_num(destination).clip(0, 255).astype('uint8').transpose(1, 2, 0)
                rgba[..., 3] = np.where(good, rgba[..., 3], 0)
                temporary = Path(str(path) + '.partial')
                Image.fromarray(rgba).save(temporary, format='PNG')
                temporary.replace(path)
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
            packed_path = output / (stem + '.validity.z')
            write_atomic(packed_path, zlib.compress(np.packbits(good, bitorder='little').tobytes()))
            record = dict(metadata, id='pyramid_' + stem, path=path.name, sha256=digest,
                          preparation_input_sha256=metadata['sha256'],
                          bounds=bounds, width=size, height=size, valid_fraction=float(good.mean()),
                          projection=GEOGRAPHIC, source_projection=metadata.get('projection'),
                          validity_mask_path=packed_path.name, validity_mask_encoding='bit-lsb',
                          validity_mask_sha256=hashlib.sha256(packed_path.read_bytes()).hexdigest(),
                          prepared_spacing_m=max(metadata['prepared_spacing_m'], (bounds[2] - bounds[0]) * math.pi / 180 * 3396190 / size),
                          tile=dict(z=level, x=x, y=y), parent=dict(z=level-1, x=x//2, y=y//2) if level else None)
            records.append(record)
    index = dict(schema='mars-geographic-pyramid-v1', reference_radius_m=manifest['reference_radius_m'],
                 source_manifest_sha256=hashlib.sha256((root / 'manifest.json').read_bytes()).hexdigest(),
                 note='Resampled sourced normalized rasters; no second datum conversion or invented detail.', datasets=records)
    temporary = output / 'index.json.partial'
    temporary.write_text(json.dumps(index, indent=2, allow_nan=False))
    temporary.replace(output / 'index.json')
    return index
