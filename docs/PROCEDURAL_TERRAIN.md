# Local geographic terrain pipeline

The current lighting/material appearance is described in [Dusty Mars](DUSTY_MARS.md). Its atmospheric sky, daylight sky fill and indirect-only cavity shading supersede the no-fill lighting described in the historical milestone records below. Measured geometry, collision and generation-cache behavior are unchanged.

## Entry points and scope

Select Curiosity or Bradbury and choose **DRIVE LOCAL TERRAIN**, or enable SURVEY GRID (G), select any cell and choose the same action. Both call the same TerrainPatchBuilder and TerrainGenerationGraph. Escape cancels preparation. Existing DEPLOY still opens the mobility field lab, and main.tscn is unchanged. procedural_terrain/mission.tscn is directly runnable with a Bradbury default.

A selected cell supplies a stable address and geographic footprint. The playable mission is a centered subset, up to 256 × 256 m, surrounded by 64 m of sampled scenery and collision. Extremely narrow cells have a 16 m minimum width, which may cross the source cell boundary near a pole. Source footprints, tile bounds and mission bounds stay separate. This pass does not generate a whole multi-kilometre survey cell at metre spacing.

The entire globe is addressable through global numeric MOLA. High-resolution data is used only where loaded and valid. Bradbury can use the bundled HiRISE product; most other places remain interpolated MOLA terrain. The inspector distinguishes mesh spacing, prepared source sampling and source spacing; a finer mesh does not create measured relief. No new thermal, soil or subsurface data is inferred.

## Coordinates and data

Planetocentric latitude, east-positive longitude and the globe's +Y north / +Z zero-longitude convention remain unchanged. Local gameplay uses metres with +X east, +Y radial up and -Z north. The region has an explicitly sampled radial origin. Tangent-plane geographic addressing uses scalar angular calculations and subtracts the radial origin before generating metre-scale vertices. Height is sampled from the existing radial datum conversion; the small patch includes planetary curvature. This is a bounded local tangent approximation, not a general cartographic reprojection for continent-sized regions.

Elevation and imagery select valid data independently. The existing elevation sampler blends valid regional data and MOLA at source boundaries. The image atlas projects registered imagery, honors masks, retains baked illumination, and falls back to the sourced Viking mosaic. It is a rendered color channel, never a height source. The inspector lists source products, links, prepared/source spacing, datum, available dates and documented accuracy notes. Unknown metadata remains unknown.

## Components

| File | Responsibility |
|---|---|
| procedural_terrain/region.gd | Bounded mission definition, geographic address and local metres |
| procedural_terrain/field.gd | Shared height, validity, normals, curvature and source sampling |
| procedural_terrain/graph_node.gd | Typed ports and declared runtime support |
| procedural_terrain/graph.gd | Reusable graph Resource and default node chain |
| procedural_terrain/evaluator.gd | Dependency evaluation, connection/cycle validation and cached outputs |
| procedural_terrain/artifact_cache.gd | Bounded, checksummed persistent geometry and imagery artifacts |
| procedural_terrain/rock.gdshader | Matte cosmetic rock shading |
| procedural_terrain/result.gd | Numeric chunk arrays, collision faces, imagery, rocks, route, hashes and warnings |
| procedural_terrain/builder.gd | Background numeric preparation and completion/cancellation |
| procedural_terrain/mission_world.gd | Native mesh/collision installation, rover, source inspector and controls |
| procedural_terrain/surface.gdshader | Matte projected imagery |
| procedural_terrain/route.gdshader | Edge/end fading for explicit local planned paths |

The default graph is Region -> Height Field and Grid -> Displace -> Normals -> Collision. Imagery depends on Region; Scatter depends on Height Field and seeded parameters; Route depends on Height Field, explicit waypoints and Scatter. Dependency hashes include node parameters and source versions. A seed/density change rebuilds Scatter and Route; mesh sampling changes Geometry, Normals and Collision while reusing imagery and height samples. Named attributes include slope_degrees, curvature_per_m and height_m.

Preparation runs on one worker outside rendering/physics. Mesh and shape uploads happen on the main thread. Neighboring chunks address the same global sample lattice, sharing exact edge coordinates and normals. Playable collision triangles use the same vertices and indices as the displayed mesh. Four coarser sourced scenery strips extend another 1,536 m beyond the terrain collar; they have no driving collision and do not expand the mission bounds. Playable collision uses the selected base spacing. Camera-dependent visual chunk LOD now runs independently; globe quadtree refinement remains independent.

The sampler and evaluator transfer across the asynchronous descent through a single consumed SceneTree payload; no autoload is introduced. Generated terrain extends the existing rover world, reusing its rover and orbit camera without changing production rover physics. Scene failure retains the globe and retry message. Native source buffers remain held by the patch until it exits. Cancellation discards results; scene exit joins an active worker, so cancellation during teardown can briefly wait for preparation.

## Driving and authoring controls

Existing WASD/arrows, brake, right-drag orbit, wheel zoom, recover and simulation modes remain. Escape or controller B returns to Mars and restores project time/physics defaults. T switches between overhead and rover views. Terrain settings expose rock density, seed and mesh spacing. Changes retain the existing terrain during preparation and replace only affected outputs.

Shift-click terrain plans a local path from the rover to the clicked destination. This is labeled user planned, not a historic traverse or a guarantee of traversability. Paths sample the shared terrain field, fade edges and ends, and interrupt at mission bounds, steep terrain and seeded obstacles. Official waypoints can enter the same graph when an actual sourced route exists; absent routes remain absent. No public fixture route is shipped.

Rocks are deterministic procedural objects with matching convex collision and a clear spawn exclusion. Their locations, distribution, friction and roughness are model assumptions. The local light maps the shared Sun into the mission frame, disables ambient fill, and retains true dark at night. Some selected patches may therefore be dark or physically steep; availability of MOLA does not certify safe rover travel.

## Verification and limitations

Run tests/procedural_run.gd for local coordinate checks at poles/seams, source height, shared chunk borders and normals, exact collision faces, seeds, graph invalidation, type errors, other geographic patches, route projection and actual rover contact/driving. The synthetic route exists only inside this test. Evidence is written to evidence/procedural_checks.json.

The first milestone includes a minimal inspector, not the full Geometry Nodes style visual editor. Deformation, custom reusable node groups, a larger math/field node catalogue, measured material classification and a full physical deformation system are not implemented. Visual local LOD and derived cavity shading are now implemented. The globe retains its existing LOD and streaming system. There is no new preparation service or browser work. Generation samples currently bundled/cached data; FETCH AVAILABLE DETAIL remains the independent geographic source acquisition action. Sampling fallback supports arbitrary addresses, not high-resolution coverage everywhere. Full-size imagery can require temporary preparation memory; the existing sampler budget does not account for every graph/mesh/physics allocation.

## Recorded verification (5 October 2026)

The native focused suite passed 15 checks, including real rover wheel contact and approximately 0.037 m/s forward travel on generated Bradbury terrain. Geographic samples at Jezero, the longitude seam and near both poles generated valid patches through the same pipeline. The rendered end-to-end suite passed six checks: Bradbury handoff, movement, source inspector, return to Mars, survey-cell handoff and truthful Jezero MOLA labeling. Actual 1920 × 1080 Compatibility captures are evidence/procedural_bradbury.png, procedural_sources.png and procedural_jezero.png.

The GTX 1650 graphical run used fixed 60 FPS simulation pacing. Initial 512-pixel atlas preparation took 17.44 s; handoff plus initial wait/capture took 23.02 s. This is a measured loading limitation, not a stable 60 FPS claim. Smaller 64-pixel test atlases and coarse test meshes prepared other geographic patches in roughly 0.1–0.2 s, but are not representative of the default 512-pixel presentation. Numeric default-spacing regeneration with cached inputs took about 0.58 s in the headless run. Texture leak messages remain at graphical test-process shutdown; no production parser/runtime errors were reported in the successful run. Native preparation latency, whole-process memory accounting and shutdown cleanup need further work before a release claim. Browser qualification and the full rover regression suite were not rerun for this milestone; rover production scripts and main.tscn remain unchanged.


## Loading and surface presentation (6 October 2026)

Prepared geometry, normals, playable collision arrays and imagery atlases persist under user://planetary_tiles/patch_*.bin. The artifact cache has a 64 MiB allocation and is also counted by the existing overall tile-cache pruner. Dependency hashes include generator revision, geographic bounds, source versions and settings. Checksum, decoded-size and array checks reject corrupt entries and trigger regeneration. Warm loads restore source inventories along with geometry, so caching never removes attribution. Settings compare output hashes when installing changes, including outputs restored from disk.

Global imagery preparation occurs lazily in the worker; the main thread no longer reads back the globe texture for every patch. Only regional images intersecting the patch and scenery footprint participate, with conservative handling around poles and the longitude seam. Validity masks remain mandatory where supplied. Local imagery uses a four-source-post edge blend rather than the globe's broad 600 m feather. Grayscale and false-color source classifications remain in the inspector. Two mipmapped atlases provide the playable patch and coarser surrounding scenery; this is not high-resolution imagery coverage everywhere.

Continuous, subtle dust shading affects roughness and visual normals only. Seeded irregular rocks use matching convex shapes. Neither effect changes measured elevation or claims mapped rock locations. The scenery annulus shares the inner geometric border with the terrain collar; far scenery is coarser and its imagery can visibly differ in detail. Local adaptive LOD is implemented below; imagery cross-resolution morphing remains future work.

The combined native check passed 17 checks, including a fresh evaluator restoring disk artifacts and source metadata, corrupt-cache rejection, chunk normals, poles/seam patches and rover driving. Cold default preparation measured 17.16 s and a fresh-builder warm load 0.160 s in the headless run. The rendered Compatibility flow passed seven checks, including repeat deployment through disk reuse; initial preparation measured 15.85 s and repeat preparation 0.152 s. Handoff plus initial wait/capture measured 27.62 s. These runs overlapped and used fixed simulation pacing, so they are loading observations, not controlled 60 FPS benchmarks. The first build remains a latency limitation.

Updated rendered evidence is in evidence/procedural_bradbury.png, procedural_sources.png and procedural_jezero.png, with measurements in procedural_checks.json and procedural_visual_checks.json. Known shutdown resource/texture warnings remain. Raw global JPEG bytes also require appropriate source-asset packaging for a future export; native project execution is the scope of this iteration. Browser qualification and a new full rover regression run remain deferred; the existing rover production scripts and directly runnable main.tscn were preserved.


## Detailed measured terrain and cinematic styling (6 October 2026)

The default appearance uses illustrative warm coloration, dust/sand normal detail, roughness variation, larger procedural rocks and instanced small gravel. SOURCE APPEARANCE in terrain settings disables tint, procedural normal/material variation and gravel. Source RGB/luminance and geography remain the underlying reference; neither cinematic hue nor gravel distribution is measured. Existing larger rock bodies remain present for stable collision, with neutral shading in source appearance. No soil classification is inferred. The original regional grayscale/false-color labels stay in the inspector.

TerrainSurfaceStyle is a reusable Resource on TerrainGenerationGraph. It exposes cosmetic seed, tint, dust color, broad/sand scales, normal strength, roughness, cavity strength and specular response. Applying it changes material uniforms only; changing gravel seed invalidates the Gravel output but not measured geometry or collision. New Cavity and Gravel graph nodes produce an optional derived map and deterministic visual instances. Missing optional outputs retain the ready sourced patch. Artifact caching supports these images and numeric refinement statistics; revisions invalidate incompatible prepared artifacts.

Cavity shading is an eight-direction horizon estimate from a 128-pixel measured height map, using four neighborhood radii. It is derived geometry shading, not measured reflectance or screen-space AO. Default strength is capped at a restrained 0.18 because imagery already has illumination. Source appearance retains this geometry shading and sunlight. Normalized blend shapes are explicitly selected so morph targets do not add their positions to the base mesh. Surface gradients are projected onto the terrain tangent plane in world coordinates and rotated into view coordinates; they do not modify height or collision. Fine material frequencies fade with pixel footprint, while gravel shrinks out between approximately 36 and 55 m. Gravel has no physics bodies or cast shadows.

TerrainDetailRenderer estimates each chunk's measured interpolation error, selects 1/2/4/8/16 m nominal sampling for default 64 m chunks and balances neighboring interior levels. The default screen error target is 2 pixels, with 20% hysteresis; Performance and High select 3 and 1 pixels. Smaller/non-square chunks use corresponding subdivisions, so displayed nominal spacing is not a claim of source resolution. Boundary vertices retain the original base-mesh edge samples: coarse interiors add boundary fan triangles, and finer boundaries interpolate those shared anchors. This deliberate edge policy prevents cracks during asynchronous installs, including the unchanged scenery boundary. It preserves base edge accuracy rather than refining edge relief beyond the base sampling. Interior vertices remain sampled physical elevations at 1× scale.

Numeric preparation runs on a separate worker with at most two requested chunks. Visible chunks take priority; substantial camera movement or rotation discards stale results. Invalid samples keep the parent visual. Each installed ArrayMesh morphs from previous interior heights/normals over 0.35 s; boundaries remain fixed. Main-thread uploads stop after two chunks or after a completed upload reaches the 2 ms target. Individual uploads are atomic and can exceed that target; measurements must report this. Error maps and target meshes are persistently cached by source, region, base geometry and level. A worker-local sampling cache avoids sharing mutable sample dictionaries with rendering or graph generation.

Collision does not follow camera refinement or cinematic detail. The existing base triangle shapes and rover contacts remain intact. Terrain settings call the original manual spacing control Collision/base sampling to distinguish an explicit base rebuild from automatic visual detail. Local sunlight uses four blended shadow cascades with a 120 m shadow range and soft-filter request; exact filtering depends on Compatibility renderer support. Ambient/reflection fill stays disabled. The local Sun is disabled below the patch geographic horizon, preventing illumination through the underside of the finite terrain mesh. FILMIC tone mapping keeps the warm treatment restrained. The local camera now includes sourced distant scenery with a longer far clip. Settings scroll within the smaller window sizes.

Implementation additions: procedural_terrain/surface_style.gd, detail_mesh.gd and detail_renderer.gd; changes extend graph nodes/results/cache and mission materials/settings. Verification combines tests/procedural_run.gd, tests/detail_capture.gd, the existing globe checks and rover regression measurements. Browser work, full graph editor and imagery LOD morphing remain deferred.


### Recorded detailed-surface verification

The combined batch passed 25 local numeric/interaction checks and 48 existing globe checks. The existing full rover regression completed 24 measurement cases; straight travel remained approximately 0.03978 m/s at both 120 and 240 Hz. The final rendered check passed 17 assertions, including exact output sizes at 1920×1080, 1600×900 and 1366×768, progressive refinement, fixed collision identity, cinematic/source differences, repeat deployment, arbitrary-cell fallback and night darkness. Render inspection prompted two repairs: stronger shadow bias removed shadow-acne bands, and explicit normalized blend shapes eliminated additive-position morph artifacts. Only the affected render checks were repeated after those repairs.

On the GTX 1650, the final rendered Bradbury navigation sample recorded median 6.80 ms, p95 11.77 ms and a 48.70 ms maximum. Jezero and global MOLA fallback recorded p95 8.33 and 7.70 ms, respectively. These are short 1–2 s samples, not a sustained stable-60-FPS certification. Bradbury's largest measured upload batch was 2.46 ms, exceeding the soft 2 ms target; at most two chunks were queued. Rapid changes discarded three stale requests in the Bradbury sequence. Source-based preparation measured 19.15 s cold and 0.288 s warm in the final rendered run. The concurrently executed headless numeric batch measured 29.73 s cold and 0.524 s warm, demonstrating sensitivity to CPU contention.

Godot tracked approximately 491–494 MiB static memory and 200–214 MiB texture memory in the final navigation samples. An external process observation recorded an 847 MiB resident peak and approximately 1,310 MiB private allocation at that observation. These counters include more than decoded source tiles and are not a whole-session maximum or a guarantee of a 512 MiB whole-process budget. Preparation and whole-process memory remain limitations. Existing shutdown Texture/ObjectDB leak reports persist and make the graphical test process exit nonzero despite all saved assertions passing; they are not treated as a clean shutdown pass.

Evidence: evidence/procedural_checks.json, detail_visual_checks.json, detail_process_memory.json and detail_*.png. Close-up, source, low-Sun, night and overhead captures supplement the three resolution checks. README and credits identify all cosmetic effects. The actual measured landing terrain remains relatively flat: procedural styling does not invent hills, sub-metre measured relief or high-resolution global source coverage.
