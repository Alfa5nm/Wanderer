# The Curiosity Voyage

An interactive Mars globe that leads into a playable, full-scale NASA Curiosity visual asset with an articulated Godot mobility simulation. **Double-click Run.cmd to play.**

This repository uses **Git LFS** for bundled terrain, imagery, models, the packaged worker and rendered evidence. Install Git LFS before cloning, then run `git lfs pull` if any assets appear as small pointer files. Local `.godot` imports and `.tools` preparation environments are generated separately and are excluded from Git.

Boot into Mars, drag to orbit, scroll to zoom and click **Curiosity**. **Explore Mission** focuses Bradbury Landing; **Deploy** descends toward Gale and enters the existing mobility field lab. Escape returns one globe navigation level or cancels descent before handoff. Gamepad: left stick orbit, triggers zoom, A confirm, B back. The lab retains its original controls below.

See [Planetary interface guide](docs/PLANETARY_MAP.md) for architecture, adding sourced content, geographic conventions, layers, tests and limitations. The globe now uses physical MOLA/CTX/HiRISE elevation with progressive terrain detail and a bundled Gale imagery mosaic. Offline Gale/Bradbury exploration is included; optional online detail uses a packaged Windows GDAL worker. Toggle SURVEY GRID with G or gamepad X at regional scale, then select a cell to inspect coverage and sources. See [terrain architecture and preparation](docs/PLANETARY_TERRAIN.md) and [measured verification](docs/TERRAIN_VALIDATION.md). To edit, open **project.godot** in **Godot 4.6.1** and press **F5** to run the project. `Run.ps1 -Editor` also opens the editor. The supplied executable is inside the directory named `Godot_v4.6.1-stable_win64.exe`.

The workspace and nearby challenge folders contained no existing Godot project, scenes, terrain, input map or repository instructions at inspection. This project provides the rover, camera, controls and a compact test range together. The reusable `rover.tscn` can be instanced in another project.

## Play

| Control | Action |
|---|---|
| W/S or Up/Down | Forward/reverse |
| A/D or Left/Right | Turn; hold without throttle for a coordinated point turn |
| Space / gamepad A | Brake |
| Right mouse drag / right stick | Orbit |
| Mouse wheel / gamepad shoulder buttons / +/- | Zoom |
| C / right-stick click | Reset camera |
| Tab / gamepad Y | Real-time engineering / 6x simulation time |
| F1 / gamepad Start | Engineering overlay |
| V / gamepad X | Illustrative rover mast view |
| R / gamepad Back | Recover at the starting pad |
| Gamepad left stick | Forward/reverse and steering |

The default Explore mode accelerates **time**, keeping the same 1/120-second simulation step. The nominal longitudinal command remains 0.040 m/s. Turning initially waits for steering alignment. Release the steering input before commanding straight travel. Allow the wheels to realign. The arm stays locked during driving.

Drive forward from the landing pad toward the measured steps and 10-degree ramp. Regolith and low-friction sand-proxy pads flank the range. The 20-degree ramp and 10-degree cross-slope are farther ahead. Scenery beyond the test range is visual background, not a traversable planet.

## Files

- `source/Curiosity_Adapted.blend`: editable adaptation; embedded textures, 15 visual assembly groups, five arm frames and mast pan/tilt hierarchy.
- `assets/curiosity.glb`: explicit Godot visual export. Original NASA source remains untouched outside this project.
- `assets/geometry.json`: measured assembly origins, coordinate conversion, source hash, changes and counts.
- `engineering_parameters.json`: editable physical parameters, units, sources and confidence status. `scripts/make_parameters.py` regenerates the initial defaults; do not run it over hand-tuned values.
- `scripts/rover.gd`: multibody construction, finite actuator servos, coordinated steering and differential coupling.
- `main.tscn`: playable physics range; `rover.tscn`: reusable rover.
- `evidence/runtime.png`, `runtime_engineering.png`: actual Godot screenshots.
- `evidence/reference_views/`: ten reference renders of the adapted asset.
- `docs/VALIDATION.md`: measured results, tolerances and qualification limits.
- `docs/ENGINEERING.md`: model architecture, source reconciliation and approximations.
- `CREDITS.md`: NASA asset attribution and primary references.

## Reproduce

`BuildAsset.ps1` runs Blender against the original asset and writes the adapted copy and GLB. Override its `-Source` and `-Blender` arguments on another computer. Reimport in Godot after exporting. No Blender runtime is needed for ordinary play; Godot ignores the source folder.

`Validate.ps1 -Controls` performs asset reimport checks, the headless physics suite, a fresh-process solver comparison and graphical input checks. The gamepad checks inject synthetic Godot input events; physical controller hardware was not available. The raw measurements are JSON and JSONL under `evidence/`. Run `scripts/report_validation.py` with Python to regenerate the readable acceptance report.

Use `engineering_parameters.json` for physical tuning. The project physics rate and Jolt solver iterations live in `project.godot`; the parameter rate controls player time modes. Estimated mechanical origins are measured from NASA's visual model, not certified flight CAD.

This is a physics-informed research/game prototype, **not a flight-qualified digital twin**. Individual wheel loads, true soil mechanics, structural wheel damage, exact flight actuator characteristics and safe dynamic arm deployment remain unverified or unimplemented. See the engineering report before drawing quantitative mobility conclusions.

The viewport imagery pass now requests a padded visible-area atlas instead of a single center tile. NASA Trek's preliminary global CTX mosaic is joined before filtering, retained as the surrounding context while local elevation and orthophotos arrive, and cross-faded at dataset edges. A Jezero surroundings atlas is bundled for the offline demo. The source remains preliminary/uncontrolled imagery, with baked illumination; it is never used as elevation.


Cosmoscope's actual code has now been reviewed and its useful data-delivery principles adapted: sourced Bradbury tile pyramids, geographic tile requests, a local cached source broker, integrity-checked grouped cache eviction and bounded directional prefetch. See [Cosmoscope integration](docs/COSMOSCOPE_INTEGRATION.md) for the upstream revision, reuse decisions, verification and remaining limits.


The cinematic visual pass adds a shared visible Sun/light direction, distant stars, fixed exposure, dark nightside shading and depth-bounded atmospheric scattering. Orbit input and selection flights are zoom-aware. See [Cinematic Mars guide](docs/CINEMATIC_MARS.md) for controls, tuning, tests and limitations.


Select a survey cell or Curiosity and use **DRIVE LOCAL TERRAIN** for a bounded sourced rover patch. The same typed graph uses valid regional terrain or global MOLA fallback. Terrain settings show source resolution and rebuild only affected outputs. Original DEPLOY and main.tscn retain the mobility field lab. See [local procedural terrain](docs/PROCEDURAL_TERRAIN.md).


Local terrain revisits reuse checksummed prepared geometry and imagery from a bounded disk cache. Sourced scenery continues beyond the driving boundary; procedural dust and irregular rocks add cosmetic detail while preserving measured heights. Source information distinguishes regional grayscale imagery from global fallback. Initial preparation still takes roughly 16–17 seconds in the recorded native runs; prepared revisits took about 0.15 seconds. See the terrain guide for measurements and remaining limitations.


Detailed local terrain now supports automatic visual refinement, measured-elevation cavity shading and cinematic dust/sand materials with small instanced gravel. Open TERRAIN SETTINGS & SOURCES to choose detail quality or toggle SOURCE APPEARANCE. Cosmetic hue and microdetail are illustrative; measured elevations and rover collision remain independent. First-build and frame-time observations are recorded in the terrain guide.

The dusty lighting pass adds a shared orbital/surface atmosphere, tan daytime sky, twilight solar aureole, distance/height-dependent haze, subtle drifting and wheel dust, mapped sand/rock normals and restrained contact occlusion. Terrain settings offer **Dramatic dusty**, **Clear inspection**, atmosphere strength and graphics quality. Night remains dark after twilight; the driving HUD is smaller. These effects illustrate appearance and weather without changing measured terrain. See [Dusty Mars architecture and controls](docs/DUSTY_MARS.md).

Local exploration now starts at **6x time**, with **1x engineering** and **12x fast travel** choices in terrain settings. Sourced 3D scenery extends 20 km, low dust banks add atmospheric depth, nearby pebbles receive Sun shadows, and driving leaves shared cosmetic ground impressions. Source appearance hides those marks and scatter. See [Gameplay pacing and landscape depth](docs/GAMEPLAY_SURFACE_POLISH.md) for controls, performance and the distinction between visual tread depth and physical soil deformation.

An optional [Forward+ trial](docs/FORWARD_PLUS_TRIAL.md) enables native volumetric dust through a separate launcher. Compatibility remains the default. The trial runs on the GTX 1650 but measured substantially slower than Compatibility; it is experimental and needs profiling before migration.


Playable local exploration now includes the supplied, adapted EMU astronaut. **H / D-pad Up** switches rover and astronaut; human walking runs at 1× time and restores the selected rover pace on return. The rover records DEM-derived slopes and simulated collision obstacles, updates a session map and proposes routes with provisional coverage labels. **F9** opens six recording presets and scenario preparation. See [Astronaut/scout architecture](docs/ASTRONAUT_SCOUT.md) and [Capture guide](docs/CAPTURE_GUIDE.md). Motion and planning limits are illustrative Mars-inspired assumptions, not validated suit mechanics or historic traverses.
