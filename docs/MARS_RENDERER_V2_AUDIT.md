# Mars Planetary Renderer V2 — current repository audit

Audit updated: 2026-10-02. The existing project is retained. Cosmoscope's repository has now been inspected directly and its useful data-delivery principles have been adapted. No gameplay, rover rebuild or Data Lens work is included.

## Current project review

1. **Godot:** 4.6.1, Compatibility renderer, Jolt Physics, 120 physics ticks/s.
2. **Startup:** `project.godot` starts `planetary_map/mars_globe.tscn`. `main.tscn` remains the directly runnable rover field lab.
3. **Planet mesh:** `terrain/terrain_renderer.gd` owns a six-face cube quadtree. Worker-thread patch construction uses 24×24 segments, numeric displacement, normals and camera-relative local origins. The old placeholder `MeshInstance3D` remains only as a compatibility surface handle for the layer API.
4. **Camera:** `camera/planet_camera.gd` provides damped orbit, logarithmic zoom, eased focus, controller axes, adaptive clipping and local-origin rebasing.
5. **Coordinates:** `+Y` north, zero longitude `+Z`, east-positive longitude `+X`, planetocentric latitude and normalized longitude. `surface_service.gd` owns terrain-aware position, normal, ray and occlusion queries.
6. **Shaders:** `terrain.gdshader` combines global Viking albedo with independently masked regional imagery and a displacement morph attribute. `atmosphere.gdshader` provides a thin sun-dependent limb. Materials are matte and high roughness.
7. **Atmosphere and lighting:** a restrained tan limb, directional sunlight, ambient fill and close-range terrain shadows are present. Dust/haze and a physically driven terminator remain polish work.
8. **Terrain/displacement:** real MOLA radius data, MOLA areoid, a Gale MOLA subset, CTX DTM and HiRISE DTM are loaded with masks, scale/offset handling and checksum validation.
9. **LOD:** screen-space quadtree refinement with hysteresis, adjacent-level balancing, coarse-edge stitching, morphing and parent retention. The latest measured selection pass is about 60 ms on the test laptop.
10. **Streaming/loading:** `terrain_worker.py` performs bounded COG reads and reprojection outside the rendering thread. `tile_streamer.gd` prioritizes selected cells and stable close views, cancels stale jobs and handles worker failure.
11. **Caching:** bundled assets are about 415 MiB; packaged worker plus notices about 157 MiB. The optional user cache is capped at 2 GiB and decoded terrain/imagery is capped at 512 MiB.
12. **Markers:** eight sourced high-level landing anchors with zoom-aware visibility, terrain placement, enlarged hit regions and terrain occlusion. Only Curiosity has deep interaction.
13. **Survey grid:** deterministic geographic cells at regional scale, terrain-conforming edges, partial validity checks, published-vs-loaded coverage, source links and scrollable inspection panel.

## Existing project module reuse

| Subsystem | Current path | Decision | Reason |
|---|---|---|---|
| Rover field lab | `main.tscn`, `scripts/world.gd`, rover scripts | REUSE DIRECTLY | Complete gameplay module and regression-tested; outside this milestone. |
| Planet interaction shell | `planetary_map/globe.gd`, camera, selection, HUD | ADAPT | Working state flow and controls are the integration contract. |
| Marker and mission data | `planetary_map/data/mars.tres`, `markers/` | ADAPT | Reusable Resources already support sourced anchors. |
| Old sphere handle | `globe.gd` compatibility `surface` node | RETAIN AS API HANDLE | Existing layer tests and future content can bind without rendering a smooth planet. |
| Numeric terrain | `terrain/`, `surface_service.gd` | REUSE / EXTEND | The current six-face renderer is the correct foundation. |
| Route renderer | `routes/route_renderer.gd` | RETAIN DORMANT | No public route is shown without an official dataset. |
| Layer registry | `layers/layer_manager.gd` | RETAIN / EXTEND | Data Lens is deferred, but scientific-layer registration is useful now. |
| Existing rover camera/physics | rover production files | DO NOT CHANGE | Curiosity is complete for this milestone. |

## Actual Cosmoscope review

The earlier module table was a review of this Godot project, not evidence of Cosmoscope integration. The actual upstream review now targets commit `0f35ad4c56e6a8f727203f23b26bd8857d422a00`. It covers `scripts/prepare-raster.mjs`, `server/cache/tileCache.ts`, `server/routes/nasa.ts`, provider configuration and `client/src/components/Map2D.tsx`.

GDAL pyramid preparation, selective tile addressing, proxy abstraction and cache principles are adapted into the native worker/streamer. React, MapLibre, DOM markers and Redis are discarded. The upstream preparation script fails syntax checking, and its persistent cache factory is not wired into the inspected tile route. See [Cosmoscope integration and verification](COSMOSCOPE_INTEGRATION.md) for the complete reuse classification, implemented files and limits.

## Data review

The repository contains NASA/JPL/USGS Viking color imagery, global MOLA MEGR quadrants, MOLA MEGA areoid, a MOLA Gale subset, USGS CTX Gale DTM/orthophoto, NASA Mars Trek Gale CTX overview imagery and USGS HiRISE Bradbury DTM/orthophoto. `manifest.json` records bounds, product IDs, projection, datum, source/prepared spacing, masks, dates and hashes. `source_catalog.json` preserves STAC footprints and links. `source_samples.json` records the invalid requested HiRISE candidate and the valid overlapping product.

Preparation is isolated in `scripts/planetary/terrain_worker.py`, with `requirements.txt` and `build_worker.ps1`. The worker supports PDS bootstrap, GDAL COG preparation and runtime STAC requests. The current data convention converts areoid-relative regional height to radial offset using the sampled MOLA areoid; global MOLA remains a separate radius product.

## Architecture decision and next pass

The current cube-sphere/quadtree approach is retained. Provider Resources now answer local coverage queries; USGS supplies an implemented live worker discovery contract. A real Bradbury geographic pyramid, versioned tile addressing, cached source broker, grouped cache validation/eviction and bounded directional prefetch are integrated. The remaining incremental work is:

- continuous elevation source transitions, source illumination seams and broader imagery paging;
- a subtle dust/haze layer and improved day/night terminator;
- broader provider discovery and a frustum-aware scheduler beyond the current one-neighbour predictor;
- refinement performance and exported-build qualification.

The main risks are CPU refinement stalls, memory pressure from the required 512 MiB decoded ceiling, and visible regional image boundaries when a mask ends abruptly. Scientific limits remain uneven coverage, product-specific accuracy metadata and the absence of globally uniform meter-scale elevation. These must stay visible in provenance/debug information rather than being hidden by fabricated geometry.

## Change plan

**Modify:** `terrain/surface_service.gd`, `terrain/tile_streamer.gd`, `terrain/terrain_renderer.gd`, `terrain.gdshader`, `atmosphere.gdshader`, `scripts/planetary/terrain_worker.py`, `docs/PLANETARY_TERRAIN.md`, `docs/TERRAIN_VALIDATION.md`.

**Create:** provider adapter/coverage-index Resources and tests only when their interfaces are exercised by the renderer.

**Do not modify:** rover assets, rover physics, Curiosity controls, gameplay scene or deployment destination semantics.

**External dependencies:** none at runtime; the optional Windows worker contains its raster dependencies and third-party notices.

**Acceptance gate:** Mars must visibly gain genuine relief and legitimate Gale detail while remaining stable, traceable and interactive. If a feature does not improve visual realism, scientific credibility, seamless zoom or future terrain integration, defer it.

## Current completion status — 2026-10-02

Renderer V2 remains incomplete. The Cosmoscope integration pass implements local PDS/Mars Trek indexes, live USGS discovery through the packaged broker, prepared Bradbury tile pyramids, cache integrity/TTL/grouped eviction and bounded predictive requests. Live ODE and arbitrary Mars Trek discovery remain unimplemented. Coverage-aware imagery collars, separate validity masks and orbital overlay fades do not establish seamless imagery/elevation source transitions. Export qualification, refinement stalls, broader provider coverage and full visual/performance acceptance remain open.

