"""Local provider boundary: bounded STAC discovery, TTL cache and offline fallback.

Adapted from Cosmoscope's proxy/cache principles, not its browser rendering stack.
No HTTP server, Redis, API keys or additional runtime services are required.
"""
import hashlib
import json
import math
from pathlib import Path
import time
from urllib.parse import urlencode
from urllib.request import urlopen

STAC_ENDPOINT = 'https://stac.astrogeology.usgs.gov/api/'
COLLECTIONS = ('mro_hirise_socet_dtms', 'mro_ctx_controlled_usgs_dtms')
MAX_RESPONSE = 8 * 1024 * 1024


def validate_request(job):
    bounds = job.get('bounds', [])
    if len(bounds) != 4 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in bounds):
        raise ValueError('Four finite geographic bounds required')
    west, south, east, north = bounds
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise ValueError('Bounds must use east-positive geographic longitude/latitude')
    if job.get('kind') not in ('elevation', 'imagery'):
        raise ValueError('Unsupported raster kind')
    if not 256 <= int(job.get('size', 512)) <= 1024:
        raise ValueError('Runtime crops are limited to 256–1024 pixels')
    if job.get('provider', 'usgs_stac') not in ('usgs_stac', 'mars_trek'):
        raise ValueError('Live provider not implemented; bundled sources remain available')
    if job.get('provider') == 'mars_trek' and job['kind'] != 'imagery':
        raise ValueError('Display mosaics cannot supply elevation')


class SourceBroker:
    def __init__(self, cache=None, ttl=43200, fetch=urlopen, now=time.time):
        self.cache = Path(cache) if cache else None
        self.ttl = max(1, min(int(ttl), 86400))
        self.fetch, self.now = fetch, now
        self.metrics = dict(hits=0, misses=0, stale_hits=0, failures=0)

    def _read(self, path):
        try:
            if path.stat().st_size > MAX_RESPONSE:
                return None
            value = json.loads(path.read_text())
            if not isinstance(value.get('features'), list) or not isinstance(value.get('cached_at'), (int, float)) or not math.isfinite(value['cached_at']):
                return None
            return value
        except (OSError, ValueError, AttributeError):
            return None

    def discover(self, bounds, collections=COLLECTIONS):
        # An application-controlled provider contract replaces URL construction in the renderer.
        items, seen = [], set()
        for collection in collections:
            if collection not in COLLECTIONS:
                raise ValueError('Unknown scientific collection')
            query = urlencode(dict(collections=collection, bbox=','.join(map(str, bounds)), limit=32))
            url = STAC_ENDPOINT + 'search?' + query
            key = hashlib.sha256(('usgs-stac-v1|' + url).encode()).hexdigest()
            path = self.cache / (key + '.json') if self.cache else None
            old = self._read(path) if path else None
            # Empty coverage gets a short TTL so a transient empty response is not sticky.
            ttl = self.ttl if old and old['features'] else min(self.ttl, 300)
            fresh = old and self.now() - old.get('cached_at', 0) < ttl
            if fresh:
                self.metrics['hits'] += 1
                features = old['features']
            else:
                self.metrics['misses'] += 1
                try:
                    with self.fetch(url, timeout=30) as response:
                        body = response.read(MAX_RESPONSE + 1)
                    if len(body) > MAX_RESPONSE:
                        raise ValueError('Catalog response exceeds entry limit')
                    features = json.loads(body)['features']
                    if not isinstance(features, list):
                        raise ValueError('Invalid STAC feature collection')
                    if path:
                        path.parent.mkdir(parents=True, exist_ok=True)
                        part = path.with_suffix('.partial')
                        part.write_text(json.dumps(dict(cached_at=self.now(), features=features)))
                        part.replace(path)
                except Exception:
                    self.metrics['failures'] += 1
                    if old and self.now() - old.get('cached_at', 0) < 30 * 86400:
                        features = old['features']
                        self.metrics['stale_hits'] += 1
                    else:
                        features = []
            for item in features:
                if not isinstance(item, dict) or not isinstance(item.get('assets'), dict) or not item.get('id'):
                    continue
                identity = (item.get('collection', collection), item['id'])
                if identity not in seen:
                    item.setdefault('collection', collection)
                    items.append(item)
                    seen.add(identity)
        self.prune()
        return items

    def prune(self, limit=32 * 1024 * 1024):
        if not self.cache or not self.cache.exists():
            return
        files = list(self.cache.glob('*'))
        files = [p for p in files if p.is_file()]
        total = sum(p.stat().st_size for p in files)
        for path in sorted(files, key=lambda p: p.stat().st_mtime):
            if total <= limit:
                break
            total -= path.stat().st_size
            path.unlink()
