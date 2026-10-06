"""Reproducible Mars raster preparation and bounded runtime COG streaming.

No image-derived heights. All output heights are radial metres minus 3396000.
Run with --bootstrap for the bundled core, or --request JSON for one runtime tile.
"""
import argparse
import concurrent.futures
import hashlib
import json
import math
import os
from pathlib import Path
import time
import urllib.request
import zlib

import numpy as np
import rasterio
from PIL import Image, ImageFilter
from rasterio.enums import Resampling
from rasterio.windows import Window
from rasterio.warp import reproject, transform, transform_bounds
from rasterio.transform import from_bounds
from source_broker import SourceBroker, validate_request
from pyramid_package import build as build_pyramid
from view_imagery import prepare as prepare_view_imagery

PDS = 'https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived'
GEOGRAPHIC = '+proj=longlat +R=3396190 +no_defs'
REFERENCE = 3396000.0
TILE = 256

def atomic(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.partial')
    temporary.write_bytes(data)
    temporary.replace(path)

def json_write(path, data):
    atomic(path, json.dumps(data, indent=2, allow_nan=False).encode())

def download(url, target):
    target = Path(target)
    if target.exists():
        return target
    if url.endswith('.img'):
        # PDS supports ranges; bounded requests avoid long stalled full-file transfers.
        probe = urllib.request.urlopen(urllib.request.Request(url,headers={'Range':'bytes=0-0'}),timeout=40)
        total = int(probe.headers['Content-Range'].split('/')[-1])
        probe.close()
        target.parent.mkdir(parents=True,exist_ok=True)
        part = target.with_suffix('.partial')
        with part.open('wb') as out: out.truncate(total)
        def chunk(start):
            end=min(total-1,start+2*1024*1024-1)
            for attempt in range(5):
                try:
                    request=urllib.request.Request(url,headers={'Range':f'bytes={start}-{end}'})
                    with urllib.request.urlopen(request,timeout=60) as response: data=response.read()
                    if len(data)!=end-start+1: raise IOError('Incomplete range')
                    with part.open('r+b') as out: out.seek(start); out.write(data)
                    return
                except Exception:
                    if attempt==4: raise
                    time.sleep(2**attempt)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(chunk,range(0,total,2*1024*1024)))
        part.replace(target)
        return target
    for attempt in range(4):
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            part = target.with_suffix('.partial')
            with urllib.request.urlopen(url, timeout=90) as response, part.open('wb') as out:
                while block := response.read(1024 * 1024):
                    out.write(block)
            part.replace(target)
            return target
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)

def grid_sample(array, lat, lon, ppd, west=0, north=90):
    """Bilinear sampling of cell-centred PDS grids, longitude periodic globally."""
    x = ((np.asarray(lon) - west) % 360) * ppd - .5
    y = (north - np.asarray(lat)) * ppd - .5
    y = np.clip(y, 0, array.shape[0] - 1)
    x0 = np.floor(x).astype(int) % array.shape[1]
    y0 = np.floor(y).astype(int)
    x1 = (x0 + 1) % array.shape[1]
    y1 = np.minimum(y0 + 1, array.shape[0] - 1)
    fx, fy = x - np.floor(x), y - y0
    return ((array[y0, x0] * (1-fx) + array[y0, x1] * fx) * (1-fy)
            + (array[y1, x0] * (1-fx) + array[y1, x1] * fx) * fy)

def save_height(path, data):
    raw = np.asarray(data, dtype='<f4').tobytes()
    atomic(path, zlib.compress(raw, 6))
    return hashlib.sha256(raw).hexdigest()

def coverage_alpha(valid, spacing_m, collar_m=600.0):
    """Display-only collar inside valid imagery; invalid source pixels stay transparent.

    A conservative coarse erosion measures distance to *all* coverage boundaries,
    including internal nodata holes, without introducing a heavy runtime dependency.
    """
    step = max(1, math.ceil(max(valid.shape) / 512))
    rows = math.ceil(valid.shape[0] / step)
    cols = math.ceil(valid.shape[1] / step)
    padded = np.zeros((rows*step, cols*step), dtype=bool)
    padded[:valid.shape[0], :valid.shape[1]] = valid
    core = padded.reshape(rows,step,cols,step).all(axis=(1,3))
    distance = np.zeros(core.shape, dtype='float32')
    rounds = min(256, math.ceil(collar_m / max(spacing_m*step, 1.0)) + 2)
    for _ in range(rounds):
        core = np.asarray(Image.fromarray((core*255).astype('uint8')).filter(ImageFilter.MinFilter(3)))>0
        core[0,:]=False; core[-1,:]=False; core[:,0]=False; core[:,-1]=False
        distance += core
    distance = np.asarray(Image.fromarray(distance).resize((valid.shape[1],valid.shape[0]),Image.Resampling.BILINEAR))
    t = np.clip(distance*spacing_m*step/collar_m,0,1)
    return np.where(valid, np.rint(t*t*(3-2*t)*255), 0).astype('uint8')


def reblend_bundled(root):
    root=Path(root)
    manifest=json.loads((root/'manifest.json').read_text())
    for data in manifest['datasets']:
        if data['kind']!='imagery': continue
        path=root/data['path']
        pixels=np.asarray(Image.open(path).convert('RGBA')).copy()
        mask_path=root/(data['id']+'.validity.z')
        if mask_path.exists():
            raw=np.frombuffer(zlib.decompress(mask_path.read_bytes()),dtype='uint8')
            valid=(np.unpackbits(raw,bitorder='little')[:pixels.shape[0]*pixels.shape[1]].reshape(pixels.shape[:2])>0) if data.get('validity_mask_encoding')=='bit-lsb' else raw.reshape(pixels.shape[:2])>0
        else:
            valid=pixels[:,:,3]>0
            atomic(mask_path,zlib.compress(np.packbits(valid,bitorder='little').tobytes()))
        atomic(mask_path,zlib.compress(np.packbits(valid,bitorder='little').tobytes()))
        data['validity_mask_encoding']='bit-lsb'
        pixels[:,:,3]=coverage_alpha(valid,data['prepared_spacing_m'])
        Image.fromarray(pixels).save(str(path)+'.partial',format='PNG')
        Path(str(path)+'.partial').replace(path)
        data['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        data['validity_mask_path']=mask_path.name
        data['display_collar_m']=600
        print('Coverage collar:',data['id'],flush=True)
    json_write(root/'manifest.json',manifest)


def prepare_cog(item, asset, bounds, size, out, kind, areoid):
    error=None
    for attempt in range(4):
        try:
            return _prepare_cog(item,asset,bounds,size,out,kind,areoid,attempt)
        except (rasterio.errors.RasterioIOError,rasterio.errors.RasterioError) as failure:
            error=failure
            time.sleep(2**attempt)
    raise error

def _prepare_cog(item, asset, bounds, size, out, kind, areoid,attempt):
    """GDAL reads only intersecting COG blocks; masks are reprojected explicitly."""
    west, south, east, north = bounds
    target_transform = from_bounds(west, south, east, north, size, size)
    href = item['assets'][asset]['href']
    with rasterio.Env(GDAL_HTTP_TIMEOUT='40', GDAL_HTTP_MAX_RETRY='3',
                      GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',
                      CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif', GDAL_CACHEMAX=64 * 1024 * 1024):
        with rasterio.open(href+('?read_retry='+str(attempt) if attempt else '')) as src:
            projected = transform_bounds(GEOGRAPHIC, src.crs, *bounds, densify_pts=21)
            win = rasterio.windows.from_bounds(*projected, src.transform).round_offsets().round_lengths()
            # Limit source RAM and respect source overviews, rather than reading whole products.
            scale = max(1, math.ceil(max(win.width, win.height) / (size * 2)))
            shape = (max(1, math.ceil(win.height/scale)), max(1, math.ceil(win.width/scale)))
            source = src.read(window=win, out_shape=(src.count, *shape), boundless=True,
                              masked=True, resampling=Resampling.bilinear)
            matrix = src.window_transform(win) * rasterio.Affine.scale(win.width/shape[1], win.height/shape[0])
            mask = np.all(~np.ma.getmaskarray(source), axis=0).astype('uint8')
            output_mask = np.zeros((size,size), dtype='uint8')
            reproject(mask, output_mask, src_transform=matrix, src_crs=src.crs,
                      dst_transform=target_transform, dst_crs=GEOGRAPHIC,
                      resampling=Resampling.nearest)
            bands = []
            for band in range(min(src.count,3)):
                values = source[band].astype('float32').filled(np.nan)
                values = values * src.scales[band] + src.offsets[band]
                result = np.full((size,size), np.nan, dtype='float32')
                reproject(values, result, src_transform=matrix, src_crs=src.crs,
                          src_nodata=np.nan, dst_transform=target_transform, dst_crs=GEOGRAPHIC,
                          dst_nodata=np.nan, resampling=Resampling.bilinear)
                bands.append(result)
            spacing = abs(src.transform.a)
            source_metadata = {'scale': src.scales[0], 'offset': src.offsets[0],
                               'projection': GEOGRAPHIC, 'source_projection': str(src.crs), 'source_spacing_m': spacing}
    valid = output_mask.astype(bool) & np.isfinite(bands[0])
    lat = north - (np.arange(size) + .5) / size * (north-south)
    lon = west + (np.arange(size) + .5) / size * (east-west)
    if kind == 'elevation':
        # HiRISE and geoid_adjusted CTX are heights relative to the MOLA areoid.
        datum = grid_sample(areoid, lat[:,None], lon[None,:], 16)
        radial = np.where(valid, bands[0] + datum, np.nan)
        digest = save_height(out, radial)
    else:
        values = np.stack(bands[:3],axis=-1)
        if values.shape[-1] == 1:
            values = np.repeat(values,3,axis=-1)
        low, high = np.nanpercentile(values[valid], [1,99]) if valid.any() else (0,1)
        values = np.clip((values-low)/max(high-low,1e-9)*255,0,255)
        image = np.nan_to_num(values).astype('uint8')
        prepared_spacing=max(spacing,(east-west)*math.pi/180*3396190/size,(north-south)*math.pi/180*3396190/size)
        alpha = coverage_alpha(valid,prepared_spacing)
        rgba = np.concatenate([image, alpha[...,None]],axis=-1)
        Image.fromarray(rgba).save(str(out)+'.partial',format='PNG')
        Path(str(out)+'.partial').replace(out)
        digest = hashlib.sha256(Path(out).read_bytes()).hexdigest()
    mask_path=Path(str(out)+'.validity.z')
    atomic(mask_path,zlib.compress(np.packbits(valid,bitorder='little').tobytes()))
    return dict(source_metadata, sha256=digest, validity_mask_path=str(mask_path.resolve()),validity_mask_sha256=hashlib.sha256(mask_path.read_bytes()).hexdigest(),validity_mask_encoding='bit-lsb',valid_fraction=float(valid.mean()),
                prepared_spacing_m=max(spacing,(east-west)*math.pi/180*3396190/size,(north-south)*math.pi/180*3396190/size),
                width=size,height=size,bounds=bounds,source_url=href)

def bootstrap(root, scratch):
    root, scratch = Path(root), Path(scratch)
    root.mkdir(parents=True,exist_ok=True)
    scratch.mkdir(parents=True,exist_ok=True)
    (scratch/'.gdignore').touch()
    products = ['megr90n000gb','megr90n180gb','megr00n000gb','megr00n180gb','mega90n000eb']
    def fetch(name):
        folder = 'meg016' if name.startswith('mega') else 'meg064'
        download(f'{PDS}/{folder}/{name}.lbl', root/'labels'/f'{name}.lbl')
        print('Downloading',name,flush=True)
        return download(f'{PDS}/{folder}/{name}.img', scratch/f'{name}.img')
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        paths = list(pool.map(fetch,products))
    areoid = np.memmap(paths[-1],dtype='>i2',shape=(2880,5760))
    atomic(root/'areoid16.bin',areoid.astype('<i2').tobytes())
    descriptors=[]
    for idx,path in enumerate(paths[:4]):
        data = np.memmap(path,dtype='>i2',shape=(5760,11520))
        west = 180*(idx%2)
        north = 90 if idx<2 else 0
        for row in range(0,5760,TILE):
            for col in range(0,11520,TILE):
                block = data[row:row+TILE,col:col+TILE]
                atomic(root/'mola64'/f'{idx}_{col//TILE}_{row//TILE}.z',zlib.compress(block.astype('<i2').tobytes(),6))
        descriptors.append({'id':products[idx],'bounds':[west,north-90,west+180,north],
                            'width':11520,'height':5760,'ppd':64,'offset_m':REFERENCE})
        print('Tiled',path.name,flush=True)
    # Tiny overview provides immediate startup; full 64ppd tiles stay on disk.
    global_grid=np.empty((11520,23040),dtype='int16')
    for idx,path in enumerate(paths[:4]):
        global_grid[(idx//2)*5760:(idx//2+1)*5760,(idx%2)*11520:(idx%2+1)*11520] = np.memmap(path,dtype='>i2',shape=(5760,11520))
    atomic(root/'mola_overview.bin',global_grid[8::16,8::16].astype('<i2').tobytes())
    del global_grid
    existing=json.loads((root/'manifest.json').read_text()) if (root/'manifest.json').exists() else {}
    manifest={'reference_radius_m':REFERENCE,'mola':descriptors,'datasets':existing.get('datasets',[]),
              'global_spacing_m':926,'areoid_spacing_deg':1/16,
              'sources':[PDS,'https://stac.astrogeology.usgs.gov/docs/data/mars/hirise_dtms/'],
              'built_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
    catalog_path=root/'source_catalog.json'
    if not catalog_path.exists():
        records=[]
        for collection,bbox,limit in [('mro_hirise_socet_dtms','137.43,-4.60,137.45,-4.58',8),('mro_ctx_controlled_usgs_dtms','137.1,-5.4,137.6,-4.1',6)]:
            with urllib.request.urlopen('https://stac.astrogeology.usgs.gov/api/search?collections='+collection+'&bbox='+bbox+'&limit='+str(limit),timeout=40) as response:
                records.extend(json.load(response)['features'])
        json_write(catalog_path,records)
    items=json.loads(catalog_path.read_text())
    required=['DTEEC_023957_1755_024023_1755_U01','DTEEC_018854_1755_018920_1755_U01','T01_000815_1749_XN_05S222W__P22_009716_1773_XI_02S223W']
    items=[next(item for item in items if item['id']==ident) for ident in required]+[item for item in items if item['id'] not in required]
    # Region has real bounds; the HiRISE subset surrounds touchdown by about 2km.
    plans=[(items[2],'geoid_adjusted_dem', [137.075,-5.402,137.634,-4.129],4096,'elevation','ctx_gale'),
           (items[2],'orthoimage',[137.075,-5.402,137.634,-4.129],3072,'imagery','ctx_gale_image'),
           (items[1],'dtm',[137.407,-4.624,137.476,-4.555],4096,'elevation','hirise_bradbury'),
           (items[1],'ortho_1',[137.407,-4.624,137.476,-4.555],4096,'imagery','hirise_bradbury_image')]
    for item,asset,bounds,size,kind,ident in plans:
        print('Preparing',ident,flush=True)
        path=root/(ident+('.height' if kind=='elevation' else '.tile'))
        metadata=prepare_cog(item,asset,bounds,size,path,kind,areoid)
        metadata['validity_mask_path']=Path(metadata['validity_mask_path']).name
        record=dict(metadata,id=ident,product_id=item['id'],kind=kind,path=path.name,
                    title=('HiRISE' if 'hirise' in ident else 'CTX')+(' elevation' if kind=='elevation' else ' grayscale orthoimage'),
                    vertical_datum='radial offset from 3396000 m' if kind=='elevation' else 'not applicable',
                    absolute_vertical_accuracy_m=None,observation_dates=(['2010-08-04','2010-08-09'] if kind=='elevation' else ['2010-08-04']) if 'hirise' in ident else [],
                    observation_source_urls=['https://www.uahirise.org/ESP_018854_1755','https://www.uahirise.org/ESP_018920_1755'] if 'hirise' in ident else [],
                    observation_date_note='Catalog processing date is not an observation date',
                    catalog_url=f'https://stac.astrogeology.usgs.gov/api/collections/{item["collection"]}/items/{item["id"]}',
                    asset=asset,footprint=item['geometry'],lod_range=[0,18])
        manifest['datasets']=[d for d in manifest['datasets'] if d['id']!=ident]
        manifest['datasets'].append(record)
        json_write(root/'manifest.json',manifest)
        print(ident,'valid fraction',metadata['valid_fraction'],flush=True)
    # Record measurements directly from the archived source, not renderer values.
    samples=[]
    for item in items[:2]:
        with rasterio.open(item['assets']['dtm']['href']) as src:
            x,y=transform(GEOGRAPHIC,src.crs,[137.4417],[-4.5895])
            value=next(src.sample(zip(x,y),masked=True))[0]
            samples.append({'product_id':item['id'],'lat':-4.5895,'lon':137.4417,
                            'height_above_areoid_m':None if np.ma.is_masked(value) else float(value)})
    json_write(root/'source_samples.json',samples)
    mola_gale(root)
    gale_mosaic(root,scratch/'gale_wmts')
    print('Core ready',sum(p.stat().st_size for p in root.rglob('*') if p.is_file()),'bytes',flush=True)

def request_tile(request):
    job=json.loads(Path(request).read_text())
    output=Path(job['output'])
    result=output.with_suffix('.json')
    try:
        validate_request(job)
        if job.get('provider') == 'mars_trek':
            metadata = prepare_view_imagery(job)
            json_write(result, {'ok':True, 'datasets':[metadata], 'cached_at':time.time(), 'pipeline_revision':'viewport-ctx-v1'})
            return
        catalog='https://stac.astrogeology.usgs.gov/api/'
        bounds=job['bounds']
        discovery=job.get('discovery',{})
        broker=SourceBroker(job.get('catalog_cache'),discovery.get('catalog_ttl_seconds',43200))
        items=broker.discover(bounds,discovery.get('collections',('mro_hirise_socet_dtms','mro_ctx_controlled_usgs_dtms')))
        kind=job['kind']
        candidates=[]
        for item in items:
            assets=item['assets']
            asset=('dtm' if 'dtm' in assets else 'geoid_adjusted_dem') if kind=='elevation' else ('ortho_0' if 'ortho_0' in assets else 'orthoimage')
            if asset in assets: candidates.append((float(item['properties'].get('gsd',100)),item,asset))
        candidates.sort(key=lambda entry:(entry[0],entry[1]['id']))
        areoid=np.memmap(job['areoid'],dtype='<i2',shape=(2880,5760))
        records=[]
        families=set()
        for _,item,asset in candidates:
            family='hirise' if 'hirise' in item['collection'] else 'ctx'
            if family in families: continue
            tile_output=output if not records else output.with_name(output.stem+'_'+family+output.suffix)
            try:
                metadata=prepare_cog(item,asset,bounds,int(job.get('size',512)),tile_output,kind,areoid)
            except Exception as error:
                print('Skipping unavailable asset:',item['id'],str(error),flush=True)
                continue
            if metadata['valid_fraction'] <= 0: continue
            families.add(family)
            is_false_color=kind=='imagery' and 'IRB' in item['assets'][asset]['href']
            records.append(dict(metadata,kind=kind,path=str(tile_output),product_id=item['id'],
                catalog_url=catalog+'collections/'+item['collection']+'/items/'+item['id'],
                title=('HiRISE' if family=='hirise' else 'CTX')+' '+('false-color orthoimage' if is_false_color else kind),
                observation_dates=[],absolute_vertical_accuracy_m=None,
                vertical_datum='radial offset from 3396000 m' if kind=='elevation' else 'not applicable'))
        if records:
            # Preserve both broad CTX and local HiRISE; their valid masks select independently.
            json_write(result,{'ok':True,'datasets':records,'published_items':items,'catalog_metrics':broker.metrics,'cached_at':time.time(),'tile':job.get('tile',{}),'pipeline_revision':'mars-radial-3396000-v3'})
            return
        raise RuntimeError('No valid published '+kind+' samples in this cell')
    except Exception as error:
        json_write(result,{'ok':False,'error':str(error)})

def mola_gale(root):
    root=Path(root)
    url=PDS+'/meg128/megr00n090hb.img'
    download(PDS+'/meg128/megr00n090hb.lbl',root/'labels/megr00n090hb.lbl')
    ppd=128
    x0,x1=math.floor((136.2-90)*ppd),math.ceil((138.8-90)*ppd)
    y0,y1=math.floor(3.0*ppd),math.ceil(6.3*ppd)
    start,end=y0*11520*2,y1*11520*2-1
    def read_chunk(begin):
        finish=min(end,begin+2*1024*1024-1)
        request=urllib.request.Request(url,headers={'Range':f'bytes={begin}-{finish}'})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request,timeout=60) as response: data=response.read()
                if len(data)!=finish-begin+1: raise IOError('Truncated MOLA range')
                return data
            except Exception:
                if attempt==3: raise
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        raw=b''.join(pool.map(read_chunk,range(start,end+1,2*1024*1024)))
    values=np.frombuffer(raw,dtype='>i2').reshape(y1-y0,11520)[:,x0:x1]
    bounds=[90+x0/ppd,-y1/ppd,90+x1/ppd,-y0/ppd]
    path=root/'mola128_gale.height'
    digest=save_height(path,values)
    manifest=json.loads((root/'manifest.json').read_text())
    manifest['datasets']=[d for d in manifest['datasets'] if d['id']!='mola128_gale']
    manifest['datasets'].append({'id':'mola128_gale','product_id':'MEGR00N090HB.IMG',
        'title':'MOLA 128 ppd Gale','kind':'elevation','path':path.name,'bounds':bounds,
        'width':x1-x0,'height':y1-y0,'prepared_spacing_m':463,'source_spacing_m':463,
        'projection':'IAU2000 planetocentric simple cylindrical','vertical_datum':'radial offset from 3396000 m',
        'source_url':url,'catalog_url':'https://pds-geosciences.wustl.edu/missions/mgs/megdr.html',
        'sha256':digest,'valid_fraction':1.0,'observation_dates':['1997-09-15','2001-06-30'],
        'absolute_vertical_accuracy_m':None,'lod_range':[0,18]})
    json_write(root/'manifest.json',manifest)
    print('Prepared true 128ppd MOLA Gale subset',values.shape,flush=True)

def gale_mosaic(root,cache):
    root,cache=Path(root),Path(cache)
    level=9
    step=180/(2**level)
    west,south,east,north=[135.1842593,-6.5732988,139.2413012,-2.8077809]
    x0,x1=math.floor((west+180)/step),math.ceil((east+180)/step)
    y0,y1=math.floor((90-north)/step),math.ceil((90-south)/step)
    canvas=Image.new('RGBA',((x1-x0)*256,(y1-y0)*256))
    records=[]
    endpoint='https://trek.nasa.gov/tiles/Mars/EQ/Gale_CTX_BlockAdj_dd/1.0.0/default/default028mm/'
    def fetch(tile):
        x,y=tile
        url=endpoint+f'{level}/{y}/{x}.png'
        path=download(url,cache/f'{x}_{y}.png')
        return x,y,path,url
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for x,y,path,url in pool.map(fetch,[(x,y) for y in range(y0,y1) for x in range(x0,x1)]):
            with Image.open(path) as image: canvas.paste(image.convert('RGBA'),((x-x0)*256,(y-y0)*256))
            records.append({'url':url,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    image=canvas.resize((2048,2048),Image.Resampling.LANCZOS)
    path=root/'ctx_mosaic.tile'
    image.save(path,format='PNG')
    bounds=[x0*step-180,90-y1*step,x1*step-180,90-y0*step]
    manifest=json.loads((root/'manifest.json').read_text())
    descriptor={'id':'ctx_mosaic','product_id':'Gale_CTX_BlockAdj_dd','kind':'imagery',
        'title':'CTX Gale mosaic (grayscale)','path':path.name,'bounds':bounds,'width':2048,'height':2048,
        'source_spacing_m':step/256*math.pi/180*3396190,
        'prepared_spacing_m':max(bounds[2]-bounds[0],bounds[3]-bounds[1])*math.pi/180*3396190/2048,
        'projection':'Mars geographic equirectangular, east positive','vertical_datum':'not applicable',
        'catalog_url':'https://trek.nasa.gov/tiles/apidoc/trekAPI.html?body=mars',
        'source_url':endpoint,'observation_dates':[],'lod_range':[0,18],
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'imagery_note':'NASA CTX mosaic WMTS. Instrument resolution up to 6m; this bundled overview is resampled.'}
    manifest['datasets']=[d for d in manifest['datasets'] if d['id']!='ctx_mosaic']+[descriptor]
    json_write(root/'manifest.json',manifest)
    json_write(root/'gale_ctx_provenance.json',records)
    print('Bundled Gale mosaic',bounds,len(records),'tiles',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--bootstrap',action='store_true')
    parser.add_argument('--root',default='planetary_map/assets/terrain')
    parser.add_argument('--scratch',default='.tools/terrain_sources')
    parser.add_argument('--request')
    parser.add_argument('--pyramid',help='Build a bounded sourced geographic tile package from request JSON')
    parser.add_argument('--mola-gale',action='store_true')
    parser.add_argument('--gale-mosaic',action='store_true')
    parser.add_argument('--reblend-bundled',action='store_true')
    args=parser.parse_args()
    if args.bootstrap: bootstrap(args.root,args.scratch)
    elif args.request: request_tile(args.request)
    elif args.pyramid: build_pyramid(args.pyramid)
    elif args.mola_gale: mola_gale(args.root)
    elif args.gale_mosaic: gale_mosaic(args.root,Path(args.scratch)/'gale_wmts')
    elif args.reblend_bundled: reblend_bundled(args.root)
    else: parser.error('Choose --bootstrap or --request')
