# Planetary interface — Phase 1

## Architecture and scene flow

Godot 4.6.1 / GL Compatibility. `project.godot` boots `planetary_map/mars_globe.tscn`; Deploy hands off to the original `main.tscn` mobility field lab. The original rover, orbit camera, world script, physics settings, test range and existing tests are unchanged.

The globe scene references `data/mars.tres`. `globe.gd` coordinates explicit PlanetView, RegionFocus, MissionFocus, SurfaceApproach and DeploymentTransition states. Back restores a stack of state, camera view and selected content. Components communicate through signals. No autoloads are required. Optional streaming uses a self-contained Windows GDAL worker; offline play does not need Python or GDAL installed.

- `data/`: typed Godot Resources for planet, mission, region, site, marker, waypoint, route and scientific layer; coordinate utility.
- `camera/planet_camera.gd`: damped orbit, inertial drag, logarithmic zoom, eased geographic focus, configurable sensitivities and normalized distance limits.
- `markers/`: projected screen markers, generous hit rectangles, terrain-aware occlusion and viewport culling and scale-dependent labels. Regional labels have separate offsets to avoid overlap with the mission/site.
- `selection.gd`: pointer/controller input adapter and shared elevation-service terrain intersection. Rendering and geographic selection require no physics bodies. This input adapter is the entry point for future touch gestures.
- `layers/`: independent material registry. Only available layers appear in the selector; the current visual layer uses a matte material and mipmapped, GPU-compressed 4K NASA Viking mosaic.
- `routes/`: great-circle subdivision and latitude/longitude projection, with optional sol/date filtering.
- `ui/`: anchored minimal HUD and contextual mission panel. No conventional main menu.
- `transitions/`: cancellable geographic approach, asynchronous scene/dependency loading, warm-color visual blend and persistent reveal overlay. Preloaded resources stay referenced by the overlay across globe teardown until gameplay owns its dependencies. The reveal uses wall time despite accelerated rover simulation.

## Controls

| Input | Action |
|---|---|
| Left mouse drag | Orbit with inertia |
| Wheel; +/- | Damped zoom |
| Click marker or its label | Select and focus geographic context |
| Double-click marker/region | Focus target |
| Enter | Select at screen center, or activate focused UI |
| Escape; breadcrumb | Back one navigation level; cancel descent before handoff |
| Gamepad left stick | Orbit |
| Gamepad triggers | Zoom (right approaches, left retreats) |
| Gamepad A / B | Select/confirm / back |
| D-pad | Navigate focused mission actions |

Curiosity selection focuses Gale. Explore Mission focuses Bradbury Landing and expands the mission description. Deploy approaches the landing anchor and launches the existing mobility field lab. The lab is a simulation test range, not a reconstruction of Gale terrain. Its original driving controls remain unchanged.

Debug telemetry requires a debug build and `--planet-debug`. It is never visible by default. Launch with `Run.cmd`, or `Run.ps1 -Editor` and F5. Directly running `main.tscn` still opens the original field lab.

## Coordinates and content

Coordinates are planetocentric degrees. +Y is north; longitude zero lies on +Z; longitude 90 degrees east lies on +X. East-positive longitude is normalized to [-180,180). The utility rejects non-finite values and latitude outside [-90,90]. An origin position has no latitude/longitude and returns infinity, rather than inventing a location.

`lat_lon_to_local(latitude, longitude, radius, altitude)` returns sphere coordinates. Radius and altitude use the same scene units. `lat_lon_to_world` and `world_to_lat_lon` accept a planet transform, including rotation, translation and scale. Do not use scene-unit distances as terrain elevations. With terrain enabled, the camera follows sampled radial elevation; the HUD reports its requested clearance above the local surface.

The equirectangular texture spans -180 to +180 from left to right and +90 to -90 from top to bottom. UV zero longitude is 0.5; north is v=0. The sphere builds explicit UVs using this convention rather than relying on an engine primitive's seam orientation.

Bradbury Landing uses NASA's reconstructed -4.5895 latitude, 137.4417 longitude. Gale's -4.5, 137.4 coordinate is the approximate NASA landing-region focus anchor, not a surveyed crater centroid. Its selection extent is an interaction guide, not a crater boundary. Mission dates use ISO dates and landing is shown in UTC.

Add missions and regions as Resource entries in a PlanetDefinition's `markers` array, with unique IDs and source references. Link mission `region_id` and `site_id`; region/site `mission_id` points back to the mission. Marker categories, dates, descriptions, icons and zoom ranges are data. Mission selection resolves these links and switches geographic targets without mission-specific code. Change a region's deployment path and label to connect a future terrain scene; list optional heavy visual dependencies in `preload_paths` for asynchronous preparation. Eight sourced landing anchors are populated. Curiosity alone has regional, site and deployment interaction.

To add official rover tracks, create a PlanetRoute with ordered PlanetWaypoint resources containing latitude, longitude and optional ISO date/sol. Set the mission's `route` directly, or its optional `route_file` path for graceful missing-file handling. Add source references and leave `development_only=false` only for verified data. `PlanetRouteRenderer.set_timeline(sol, date)` filters the accumulated route; `PlanetRoute.points_until` supplies matching data for a future rover-position/event timeline. Missing date/sol values are excluded when that corresponding filter is active. Development-only routes are never rendered, including in debug builds. Synthetic test points exist only in the test script.

For a new scientific view, register a PlanetDataLayer with an available texture or material, then call `PlanetLayerManager.set_view_mode(id)`. Materials are independent of geometry, markers and route overlays. A regional/tiled surface provider can replace the surface mesh/material updates behind the layer manager without rewriting selection or mission content. Runtime tile streaming, scientific interpretations and terrain displacement are not implemented.

## Sources and assets

The bundled 4096 x 2048 visual texture is assembled from 128 NASA Mars Trek level-3 WMTS tiles of **Viking VIS, Global Color Mosaic / MDIM 2.1**. It is a colorized image mosaic, not a quantitative scientific layer. No generated or fictional terrain was inserted. NASA/JPL/USGS are credited in CREDITS.md. `assets/wmts_capabilities.xml` records projection, tile grid and endpoints; `texture_provenance.json` records every tile hash and the output hash.

`scripts/build_mars_texture.py` reproduces the image with Python and Pillow. It is an optional asset-build tool; playing the game requires neither Python nor a network connection. The originally inspected NASA 1440 x 720 texture is retained as a source comparison only; it is not used by the visual layer.

- NASA Mars Trek API: https://trek.nasa.gov/tiles/apidoc/trekAPI.html?body=mars
- Landing reconstruction: https://ntrs.nasa.gov/api/citations/20130011617/downloads/20130011617.pdf
- Mission dates/context: https://mars.nasa.gov/internal_resources/824/
- Landing-site name: https://www.jpl.nasa.gov/news/nasa-mars-rover-begins-driving-at-bradbury-landing/
- Gale context/approximate focus: https://science.nasa.gov/resource/daybreak-at-gale-crater/
- Mean-radius reference: https://ssd.jpl.nasa.gov/planets/phys_par.html

## Validation and integration limits

`tests/globe_run.gd` runs coordinate, selection, navigation, controller, route, asset-failure and deployment integration checks. Use Godot with `--headless --path . --script tests/globe_run.gd`. `tests/globe_visual.gd` renders orbital, region and site views at the three requested resolutions, clicks Explore/Deploy through the UI and measures real frame intervals. It must run graphically. Reports and screenshots are under `evidence/`. See [Planetary validation](PLANETARY_VALIDATION.md) for measured results and the external NASA-source hash mismatch flagged by the original rover checker.

Existing rover validation remains available through `Validate.ps1 -Controls`. Planet diagnostics are separate from rover engineering telemetry.

The globe renders numeric terrain at 1× physical elevation, independently sourced imagery and a thin illustrative atmospheric limb. See [terrain architecture](PLANETARY_TERRAIN.md) for datasets, LOD, caching and honest coverage limits. No official traverse or public timeline is bundled. Sun direction is illustrative. Physical controller hardware and integrated-GPU laptops remain unqualified.

Threaded loading prepares resources, but the existing field lab constructs its physics scene on the main thread at activation. Measured activation frame time is reported separately; the overlay conceals the visual scene swap, not a guarantee of zero CPU stalls. Back is available until handoff. After deployment the original gameplay owns input and time settings; return-to-globe navigation from gameplay is a future integration task.

Future integration: connect a drivable Gale terrain scene through the region deployment path, then ingest an official dated traverse. Data Lens remains deferred.

## Change inventory

Created: all files under `planetary_map/`, `scripts/build_mars_texture.py`, `tests/globe_run.gd`, `tests/globe_visual.gd`, this guide, `docs/PLANETARY_VALIDATION.md` and globe-specific evidence.

Modified: `project.godot` startup path; README.md and CREDITS.md. The existing validation report/parameter table and evidence were regenerated with their existing tools. No rover production files changed.
