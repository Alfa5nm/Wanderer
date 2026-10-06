# Mars terrain, streaming and survey exploration

## Scene and component ownership

`project.godot` starts `planetary_map/mars_globe.tscn`. The existing navigation controller and state history remain in `globe.gd`. Survey inspection is an overlay inside those states: Cancel closes cell details first. Deploy cancels streams, keeps the destination marker, asynchronously loads `main.tscn`, resets time/physics defaults and hands off to the existing mobility field lab. That field lab remains directly runnable and is not geographic Gale terrain.

Created for 1B–1E:

- `data/dataset.gd`, `data/terrain_tile.gd`: typed Resources with source, sampling, bounds, datum and tile metadata.
- `terrain/surface_service.gd`: numeric raster loading, checksums, validity masks, independent elevation selection, double-precision position calculations, normals, terrain intersections and occlusion.
- `terrain/terrain_renderer.gd`, `terrain.gdshader`, `atmosphere.gdshader`: six cube faces, quadtree patches, screen-space refinement, hysteresis, neighbour balancing, stitched coarse edges, geometry morphing, imagery fades and a sun-dependent tan limb.
- `terrain/tile_streamer.gd`: stable-view/selected-cell requests, cancellable worker processes, warm-cache reuse, bounded decoded memory and oldest-file cache pruning.
- `survey/survey_grid.gd`: deterministic latitude/longitude cells, terrain-conforming boundaries, coverage checks and cell selection.
- `scripts/planetary/terrain_worker.py`, `requirements.txt`, `build_worker.ps1`: reproducible raster preparation and the packaged GDAL worker.
- `assets/terrain/`: global MOLA tiles, areoid, regional heights, separate imagery, source catalog, source measurements and provenance.
- `tests/terrain_run.gd`, `terrain_streaming.gd`, `terrain_visual.gd`, `terrain_capture.gd`: scientific, streaming and graphical evidence.

Modified globe camera, selection, markers, routes, HUD, mission panel, transition and mission Resources to share terrain sampling and expose the survey interface. Existing rover production scripts and `main.tscn` remain unchanged.

## Coordinates, datum and precision

Planetocentric degrees; +Y north, longitude zero +Z, east-positive toward +X. Longitudes normalize to [-180,180). MOLA longitude grids wrap at 0/360. Rasters are cell-centred, north-first; texture UVs run west-to-east and north-to-south. Numeric data, surface imagery and overlays remain separate.

MOLA MEGR products contain planetary radius: signed integers plus 3,396,000 m. MEGA contains areoid radius using the same offset. HiRISE/CTX areoid-relative elevations are converted to radial offsets by adding the sampled GMM3 areoid offset. They are never interpreted as heights above a mean-radius sphere. PDS scale/offset and GDAL band scale/offset are applied before combination. Invalid pixels remain NaN and fall back to regional MOLA or global MOLA. Four valid samples are required for interpolation.

Physical elevation uses 1× scale. The scene renders one normalized radius as 1000 units for usable near clipping. Camera position is rebased to zero; patch origins use scalar 64-bit calculations before subtraction into Godot Vector3 values. Adaptive clipping follows clearance. Geographic conversion APIs still support arbitrary transforms; the current globe assumes a fixed axis-aligned body and performs its own rebasing. Do not rotate the terrain node independently of the sampling service.

## Bundled sources

| Data | Product / source | Bundled sampling | Important distinction |
|---|---|---|---|
| Global radius | PDS MOLA `MEGR90N000GB`, `MEGR90N180GB`, `MEGR00N000GB`, `MEGR00N180GB` | 64 pixels/degree, about 926 m at equator | Angular spacing varies physically with latitude; not absolute accuracy |
| Areoid | PDS `MEGA90N000EB` | 16 pixels/degree | GMM3 areoid radius, not a sphere |
| Gale radius | PDS `MEGR00N090HB` clipped to Gale | 128 pixels/degree, about 463 m | Finest available MOLA source is not implied by this subset |
| Gale overview imagery | NASA Mars Trek `Gale_CTX_BlockAdj_dd` | about 132 m, 2048² grayscale | WMTS level 9 about 81 m; CTX instrument imagery can be about 6 m |
| Gale terrain | USGS CTX `T01_000815_1749_XN_05S222W__P22_009716_1773_XI_02S223W` | 20 m, masked 4096² crop | About 60% valid; source coverage has holes |
| Gale matching imagery | same CTX product, `orthoimage` | about 24.6 m, 3072² grayscale | Source raster spacing is 20 m; prepared imagery is downsampled |
| Bradbury terrain | HiRISE `DTEEC_018854_1755_018920_1755_U01` | about 1.012 m, masked 4096² crop | About 52% valid; masks determine displayable coverage |
| Bradbury imagery | same HiRISE product, `ortho_1` RED_C | about 1.012 m grayscale | Independent imagery validity; no elevation inferred from RGB |

The requested first candidate `DTEEC_023957_1755_024023_1755_U01` intersects the landing footprint but has no valid height at touchdown. `source_samples.json` records that gap and the overlapping product's -4492.5088 m areoid-relative source sample. Dataset descriptors retain source URLs, footprints, dimensions, masks/valid fractions, projection, source/prepared spacing and hashes. HiRISE acquisition dates are verified as 2010-08-04 and 2010-08-09. Generic catalog processing timestamps are excluded from acquisition dates. Unknown dates and product-specific absolute accuracy stay unknown.

The Viking color mosaic and regional orthophotos contain baked illumination. Matte shading and restrained display contrast add illustrative sunlight; this is not a photometrically corrected reflectance model. Procedural macro/micro normal and roughness variation improves visual scale and is explicitly not scientific topography. Streamed IRB orthophotos retain a false-color label. Sampling spacing, relative precision and absolute accuracy are separate concepts.

## LOD and streaming

Patches have 24×24 segments; visible screen error drives refinement with hysteresis through level 17. Balancing can exceed the initial 150-patch target. Adjacent leaves differ by at most one level, odd fine-edge vertices stitch to coarse edges, and vertex attributes encode a coarse-to-fine morph. A complete parent frontier remains visible until children are ready. Imagery uses independently masked projections and a 600 m display collar following valid-pixel boundaries, including internal holes. Packed validity masks remain separate from display alpha, so the survey reports coverage even when imagery fades. Regional grayscale overlays fade in below about 680 km altitude and reach full opacity near 170 km. This does not remove baked mosaic seams or implement an elevation transition collar. One completed mesh uploads per frame; mesh generation runs on a worker thread.

Stable regional views request a geographic tile after 1.5 seconds when detail is missing or a bundled pyramid tile is available. Tile level follows projected pixel spacing. Selected survey cells take priority; Fetch Available Detail requests a larger crop. One neighbour is predicted from recent geographic motion and prepared only after foreground elevation and imagery; it remains on disk until needed. HiRISE and CTX catalogs are queried separately through the local cached broker. The first valid candidate per instrument is prepared independently for imagery/elevation, preserving their own masks. Cache hits, misses, cancellations, prepared bytes and request latency are tracked for profiling. This is bounded tile streaming, not a complete catalog download or continuous full-screen HiRISE coverage. See [Cosmoscope integration](COSMOSCOPE_INTEGRATION.md) for prepared pyramids, provider contracts and verification.

A self-contained Windows executable under `planetary_map/tools/mars_terrain_worker/` performs remote COG range reads, crop/reprojection and preparation outside the rendering thread. Rapid requests cancel previous processes; failed, interrupted or corrupt results preserve the bundled core. The optional user cache is capped at 2 GiB, decoded terrain/imagery at 512 MiB, with at most eight streamed records. Global MOLA uses a 96-tile decoded LRU. The measured bundled decoded budget is about 487.1 MiB, including a conservative CPU/GPU imagery allowance. Worker transient memory is separate. Optional service outages do not prevent offline boot or deployment.

Use `--planet-offline` for offline play: bundled pyramids and valid cached tiles can be loaded without launching the worker. Cache lives in Godot's `user://planetary_tiles/`. Disk pruning occurs at boot/completion; an in-flight partial crop can temporarily exceed the cap. Prepared entries have a 30-day online TTL and 64 MiB size limit; integrity is verified before accepting a cache hit. Missing/corrupt groups trigger an online refetch. Descriptor, raster and mask companions are evicted together using last-access time, within the cache directory. Catalog metadata has its own bounded TTL cache and is included in the total disk cap.

## Survey and controls

G / controller X toggles SURVEY GRID at regional scale, off by default. Cell steps refine from 1° to 0.25°, 0.0625° and 0.015625°. Click terrain, or confirm at the controller center reticle, to inspect a cell. Bounds, landing anchors, loaded/bundled/cached products, partial sample checks, published footprints, source spacing, known dates and source links appear in a compact scrollable panel.

Dashed boundaries indicate MOLA, paired dashes CTX and solid boundaries HiRISE at the sampled cell center. The legend describes this sampled display indication, not exhaustive pixel-level coverage. Nine validity probes distinguish partial loaded coverage; published bounding footprints never claim valid terrain by themselves. Unknown metadata is stated honestly. Eight rounded NASA landing anchors are shown globally; only Curiosity has deep interaction. Routes remain absent without an official dataset.

Mouse drag/wheel and left stick/triggers continue to orbit/zoom. Escape/B closes details, then follows navigation history. Explore Mission focuses Bradbury; Deploy enters the existing mobility field lab. Touch can be added through the separate input adapter.

## Reproduction, packaging and future content

Ordinary Windows play requires only Godot; GDAL/Python are already frozen into the optional worker. For authoring, create an isolated Python 3.14 environment and install `scripts/planetary/requirements.txt`, then run `terrain_worker.py --bootstrap`. `--mola-gale` and `--gale-mosaic` rebuild individual subsets. Preparation downloads real numeric PDS products and reads regional COG windows; it may require several GB of authoring scratch space. `.tools/` and source scratch are excluded from Godot imports and the offline delivery budget.

Run `scripts/planetary/build_worker.ps1` to freeze the worker. Preserve the worker's complete directory and third-party licenses. For exported games include raw `.bin`, `.z`, `.height`, `.tile`, `.json`, `.lbl` and `.xml` terrain files in the PCK, and copy the worker directory beside the game executable at `planetary_map/tools/mars_terrain_worker/`. Exported-game packaging has not been independently qualified; source-project execution and the frozen worker have been tested.

Add a dataset descriptor to the manifest, with independently prepared elevation or imagery and verified masks. Preserve radial datum conversion and accurate source labels. `PlanetSurfaceService.add_dataset()` validates and signals geometry/imagery refresh. Future Data Lens layers can register with the existing layer manager; unavailable layers remain absent. Set `PlanetRegion.deployment_scene`, `deployment_label` and preload dependencies to connect future drivable Gale terrain without changing the globe state flow.

See [terrain verification](TERRAIN_VALIDATION.md) for measured results and limitations. Dense source seams, mask boundaries, catalogue outages and laptop performance require further qualification before scientific measurement or a release claim.


To regenerate display collars without another source download, run the isolated authoring worker with --reblend-bundled. The immutable packed masks make subsequent runs idempotent. The first migration conservatively derived bundled masks from existing nonzero alpha, so tiny areas previously rounded to zero remain excluded; newly prepared COG crops preserve validity directly from raster masks. The streamer byte counter records prepared output bytes, not HTTP transfer bandwidth. Its latency ends before render upload and is not end-to-end display latency.

