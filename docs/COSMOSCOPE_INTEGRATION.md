# Cosmoscope heritage integration

Reviewed 2026-10-02 against [Alfa5nm/CosmoScope_v2](https://github.com/Alfa5nm/CosmoScope_v2/tree/0f35ad4c56e6a8f727203f23b26bd8857d422a00), commit `0f35ad4c56e6a8f727203f23b26bd8857d422a00`. The checkout was inspected directly under the excluded authoring directory `.tools/cosmoscope_review/`; it is not part of the game. This replaces the earlier unsupported heritage review.

## Actual repository findings and decisions

| Upstream subsystem | Code reviewed | Decision | Godot implementation |
|---|---|---|---|
| Raster preparation | `scripts/prepare-raster.mjs` | ADAPT concepts; do not copy script | GDAL-backed `pyramid_package.py` creates bounded geographic multi-resolution packages with numeric elevation, masks and independent imagery. |
| Selective raster loading | `client/src/components/Map2D.tsx` | ADAPT tile addressing and zoom-dependent requests | `terrain/tile_address.gd` uses geographic z/x/y addresses and parent relationships, including poles and longitude wrapping. |
| Provider proxy | `server/routes/nasa.ts` | REIMPLEMENT as local worker boundary | `source_broker.py` owns STAC discovery, response validation, collection separation, TTL caching and failure handling outside the rendering thread. |
| Filesystem cache | `server/cache/tileCache.ts` | ADAPT principles | `terrain/tile_cache.gd` uses SHA-256 request identities, revision/provider/kind namespaces, TTL, entry-size limits, integrity checks and grouped eviction. |
| Redis | `server/cache/tileCache.ts` | DISCARD for offline desktop core | No database or separately installed service. |
| React / MapLibre / DOM markers | Map2D and client components | DISCARD rendering implementation | Godot retains native terrain meshes, camera, markers, survey UI and deployment. |
| Colorized elevation display layers | NASA proxy layer definitions | DISCARD as elevation input | Only numeric MOLA/CTX/HiRISE heights displace geometry. |

Important upstream qualifications: the preparation script fails Node syntax checking at this revision, including after removing its BOM. The file/Redis cache factory has no call sites in the checked server; the tile route sets HTTP cache headers but does not use that cache class. The route contains its own provider configuration; `server/config/tile-sources.json` is not wired into it. These are inspected code findings, not claims that upstream preprocessing or persistent tile caching runs successfully. See `evidence/cosmoscope_upstream_prepare*_check.log`.

## Prepared hierarchical data

`scripts/planetary/bradbury_pyramid.json` describes a reproducible package built from the existing sourced, normalized HiRISE Bradbury rasters. The package under `planetary_map/assets/terrain/pyramids/` contains 18 independent elevation/imagery tiles at levels 12–14, approximately 4.9 MiB. Each tile has masks, source references, input/output hashes, parent address, physical datum and source/prepared spacing. It is resampled source data, not additional source resolution. Numeric heights are already radial offsets and receive no second areoid conversion. Raster projection is explicitly geographic even when the original source product used a projected CRS.

Run from the project root:

```powershell
planetary_map/tools/mars_terrain_worker/mars_terrain_worker.exe --pyramid scripts/planetary/bradbury_pyramid.json
```

The frozen Windows worker contains GDAL and Python dependencies. The authoring equivalent is `terrain_worker.py --pyramid` in the isolated environment. Requests are bounded to 128 prepared tiles per package. Existing global/regional parent datasets remain available while children load. The original complete Bradbury subset is retained; this small demonstration package does not replace or convert every regional asset into a lazy pyramid.

`MarsTilePackage` loads only metadata on boot. The streamer chooses a geographic level using projected pixel spacing, checks bundled tiles before cache/network, and loads matching elevation and imagery independently. Cached prepared rasters can be reused while offline, including valid entries past their online TTL. Offline misses never start the worker. There is one completed job per frame; there is no whole-product download on the interactive path.

## Discovery, caching and scheduling

USGS STAC is the implemented live discovery provider. `MarsUSGSStacAdapter.discovery_request()` supplies the worker contract; the broker separately queries HiRISE and CTX collections. Catalog metadata has a 12-hour TTL, a short empty-result TTL, bounded responses and up to 30-day stale fallback during outages. Published footprints still do not establish valid terrain coverage.

PDS and Mars Trek adapters now index their actual bundled product records and answer local coverage queries. Live ODE search and arbitrary Mars Trek service discovery remain unimplemented. The local worker boundary replaces the proxy pattern; this project does not require Cosmoscope's Express server or expose an HTTP proxy.

Prepared entries expire online after 30 days, use a versioned/provider/kind/geometry/size SHA-256 identity, and are limited to 64 MiB per entry. Checksum or mask failure causes an online refetch instead of repeatedly accepting a corrupt cache hit. Descriptor, rasters and masks are evicted as a group using last-access time. The total 2 GiB cache includes catalog files; interrupted/legacy files are also pruned. Active entries are protected, and deletion is confined to the configured cache directory. In-flight writes can temporarily exceed the limit.

Foreground elevation and imagery precede one predicted neighbour, based on the recent geographic movement direction. Prediction is intentionally bounded, and prefetched data stays on disk until needed. Selecting a destination clears the prediction queue. Movement out of the requested tile cancels stale automatic work. This is a small directional predictor, not a complete frustum/trajectory scheduler. The existing 512 MiB managed decoded-data budget and parent retention still apply.

## Verification and limits

`tests/cosmoscope_run.gd` checks 31 cases: addressing, seams/poles, hierarchy, source/provider separation, cache integrity/TTL/size/containment, grouped eviction, destination priority, cancellation, local provider indexes and real offline pyramid loading/datum preservation. `test_source_broker.py` covers nine catalog-cache and provider-failure cases. Existing terrain, streaming and globe suites are retained.

`tests/cosmoscope_capture.gd -- --planet-offline` exercises automatic packaged-tile loading near Bradbury and captures `evidence/cosmoscope_bradbury.png`. The source elevation is compared before/after child loading. Real frozen-worker STAC/COG results and catalog metrics are recorded separately.

This applies the useful Cosmoscope data-delivery principles. It does not establish completion of the entire Renderer V2 brief. Full-screen imagery page management, general regional pyramid conversion, broader provider coverage, predictive frustum scheduling, source illumination seams, refinement stalls and exported-build qualification remain open. No rover, survival or Data Lens feature is added.
