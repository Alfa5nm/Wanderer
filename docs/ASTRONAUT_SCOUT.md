# Astronaut, scout loop and recording architecture

The local geographic terrain scene now includes a playable EMU astronaut and a rover-to-human scouting demonstration. This is **Mars-inspired movement**, not validated pressurized-suit biomechanics. Original `main.tscn` still opens the mobility field lab; the human/scout features belong to `procedural_terrain/mission.tscn`.

## Controls and scene flow

Select Curiosity, a science area, or a survey cell on Mars, then DRIVE LOCAL TERRAIN. H / gamepad D-pad Up switches Curiosity and the astronaut. WASD / left stick moves; Shift fast-walks; Space / gamepad A brakes or braces. Right mouse / right stick orbits; wheel zooms. R recovers a fallen astronaut when the saved standing position is stable and clear. Escape returns to Mars. Shift-click proposes a destination. F9 opens recording controls, F8 retracts HUD, F10 resets the prepared scout scenario. Keys 1–6 select shots while recording controls are enabled.

Human control sets simulation time to 1× and physics to the project default 120 Hz. Returning to Curiosity restores its selected 1×, 6× or 12× pace. The inactive rover receives zero drive commands and brakes; the inactive astronaut remains collision-grounded. Presentation camera smoothing, preparation cues and scout intervals use wall time.

## Asset and rig

`source/astronaut/original_emu.zip`, `Astronauta.blend` and `LICENSE.html` preserve the supplied source. Juan Ignacio Gil-Hutton's [Astronaut – EMU suit – Rigged](https://blendswap.com/blend/12622) is **CC BY 3.0**. Attribution is retained in CREDITS; modified geometry, weights, materials, rig and all animation clips are project adaptations. This is an artistic EMU model, not a NASA-certified Mars suit.

Run Blender 5.0 in background with `--factory-startup --disable-autoexec --python scripts/prepare_astronaut.py` from the project directory. The script removes the source's six cyclic constraints, excludes authoring controls/custom shapes, remaps stale toe weights, limits normalized influences to four, repairs rigid accessory attachments, creates anatomical toes and exports a separate clean skeleton. It bakes Multires sculpt detail into a 2048-pixel tangent normal map and converts packed materials into PBR textures capped at 2048. It writes `assets/astronaut/astronaut.glb`, two reduced meshes, `sculpt_normal.png` and `manifest.json`. Main mesh: 38,976 exported indexed triangles. Godot additionally generates automatic mesh LODs. The two lower-detail GLBs are available for explicit platform budgets. Legacy glass shaders export transparent; colored untextured parts retain their source diffuse values. Authoring IK/FK attachment names remap to anatomical bones, including the forearm notepad.

Ten authored, in-place clips: idle, walk, fast_walk, turn_left, turn_right, stop, brace, stumble, fall, recovery. Locomotion blends idle/walk/fast_walk/brace; the remaining clips are available for presentation, with severe falls driven by physical bones. These are authored procedural motions, not motion-captured astronaut observations.

## Contact, movement and fall assumptions

`astronaut/controller.gd` owns the CharacterBody3D capsule, collision grounding, acceleration 2 m/s², braking 4 m/s², walk 1 m/s, fast walk 1.6 m/s, gravity 3.71 m/s², 0.25 m step limit and 25° physical walk slope limit. There is no jump or unrestricted run. Step clearance checks use the capsule; cosmetic gravel and track relief are excluded from support checks.

TwoBoneIK3D solves the legs using center/heel/toe collision rays. Stance locks world targets, knee poles constrain bend direction, reach is limited to 99% of leg length, and pelvis displacement is clamped to 0.15 m. `foot_alignment.gd` aligns soles after IK and adds bounded torso lean. `camera.gd` uses wall-time focus smoothing and ray obstruction avoidance.

Unsupported descent or impact above 4.5 m/s triggers 13 physical bones. Illustrative masses: hips 20 kg, chest 18 kg, eleven remaining bodies 4 kg each, total 82 kg; these are simulation proxies, not actual suited body mass. Cone limits: 35° swing / 20° twist. Recovery checks the last grounded position's slope and capsule clearance before ending ragdoll. This is a responsive prototype: authored gait, limited IK support rays and simplified joint proxies need broader irregular-terrain tuning before any claim of realistic suit mechanics.

## Assessment and proposed routes

`scout/session.gd` persists geographic findings and route state at the SceneTree root across local/globe scene changes. Signals: assessment_added, map_changed, route_changed. Records distinguish DEM-derived slope from SIMULATED OBSTACLE detections of existing collision rocks. No cosmetic gravel, texture, hue or rut becomes a hazard.

`assessment.gd` samples the 10 m forward sector every 0.5 wall-time seconds while the rover is active, checks physical visibility and records valid dataset samples. New caution/hazard findings trigger worker replanning. `route_planner.gd` uses an eight-neighbor 2 m AStarGrid2D, rejects missing elevation and slopes ≥15°, increases cost from 8°, dilates rock footprints by 1 m, disallows diagonal corner cutting and validates the final polyline at ≤1 m intervals. Planning cutoffs are illustrative human planning assumptions, distinct from the actor's 25° movement limit.

The first line is explicitly UNVERIFIED PROPOSAL. Revised proposals still retain amber provisional segments where the scout has not inspected; cyan denotes inspected sections. The planner can use published elevation and existing simulated obstacle geometry outside the scanned sector, so a revised line is a proposed model result, not proof that the whole route has been physically surveyed. Stale destination generations are rejected; no valid path produces NO ROUTE FOUND. Worker preparation does not block Godot rendering but is currently several seconds on the available laptop.

`map.gd` and `presentation.gd` show the map, findings and terrain-following route. Presentation rebuilds coalesce into one deferred update per frame. `globe_overlay.gd` projects session findings and the current proposal back onto Mars using the shared terrain sampler. Session content is simulated gameplay feedback, never an invented NASA traverse.

## Science positions and provenance

`planetary_map/data/science_targets.json`, `science_site.gd` and `source/msl_places_science_excerpt.json` retain the selected PDS localization records and official NASA science sources. Rocknest uses archived rover position Sol 59/site 5/drive 104 (-4.589995670°, 137.448341795°E), the preceding localization for Sol 61 scoop activity. John Klein in Yellowknife Bay uses Sol 166/site 6/drive 0 (-4.589484879°, 137.449129568°E), preceding Sol 182 drilling. Neighboring localization intervals are recorded. These are **rover positions associated with science areas**, not surveyed exact scoop/drill point coordinates. Nine CSV decimal places express storage precision; absolute positioning accuracy and rover-to-target offset are undocumented.

Sources: [MSL PLACES localization table](https://planetarydata.jpl.nasa.gov/img/data/msl/msl_places/data_localizations/localized_interp.csv), [PLACES SIS](https://planetarydata.jpl.nasa.gov/img/data/msl/msl_places/document/PLACES_PDS_SIS.pdf), [Rocknest first scoop](https://science.nasa.gov/photojournal/first-scoop-by-curiosity-sol-61-views/), [John Klein first drilling](https://science.nasa.gov/photojournal/curiositys-first-sample-drilling/).

Provenance cards expose dataset/product identifiers, source and prepared sampling, accuracy wording, coverage/fallbacks, dates and source links. Source imagery, prepared mesh interpolation, illustrative coloration and suit motion remain separate. Science target selection prepares the same geographic patch pipeline used by survey cells. Ordinary DEPLOY continues to describe the existing mobility field lab accurately.

## Recording components and invariants

`capture/scenario.gd` first searches valid fine-resolution slopes in the current patch, then a bounded deterministic selection of bundled Gale candidates. A measured ≥15° slope is usable only with a <8° staging location and a validated alternative. If the bounded search finds none, it uses an existing seeded collision rock and visible SIMULATED OBSTACLE labels. It does not invent terrain slopes. `director.gd` prepares the scenario before capture, sets six repeatable cameras and controls DEM/imagery/derived-slope presentation uniforms. Reset restores actors, unverified proposal, findings and cameras without regenerating the prepared patch. `servo.wav` is an original synthesized activation cue.

Appearance and recording stages never change sampled elevations or fixed terrain collision. Compatibility remains default; the separate Forward+ launcher remains experimental and historically much slower on the GTX 1650. Browser portability, autonomous human route following, full suit biomechanics, physical soil tracks and video production remain deferred.

## Verification

`tests/astronaut_scout_run.gd`: structural rig/clip checks, movement, stopping, ragdoll/recovery, time restoration, invalid route coverage, obstacle clearance, unchanged terrain collision and persistent findings. `tests/scout_capture.gd`: actual native renders at 1920×1080, 1600×900 and 1366×768, recording stages, measured contacts, worker planning and proximity feedback. Raw results live in `evidence/astronaut_scout_checks.json` and `evidence/scout_capture_checks.json`. See [CAPTURE_GUIDE](CAPTURE_GUIDE.md) for recording directions and [ASTRONAUT_SCOUT_VERIFICATION](ASTRONAUT_SCOUT_VERIFICATION.md) for measurements and limits. No 60 FPS claim is made without measured results.

Reproduce the grouped check workflow with `ValidateAstronaut.ps1`; add `-Rover` for the original rover cases and `-Captures` for the native recording/route/performance windows. Godot and Python paths can be supplied as parameters. This script is supplied for repeatability; the completed runs are recorded separately in the verification report.

## Gait correction after player feedback

The original procedural motion passed contact checks but looked unnatural: the arms twisted about a local axis, foot adaptation flattened the swing phase, and knee poles crossed the body's left/right lanes. The rebuilt clips orient limbs in armature space while accounting for their posed parents. Arms swing opposite the legs with relaxed elbow/wrist angles; leg clips use forward-bending analytical knees, 60% support and 40% swing, with explicit ankle lift. Walk/fast-walk timing matches the controller speed, and changing pace preserves cycle phase.

`astronaut/gait_contacts.gd` now runs before TwoBoneIK3D in the skeleton modifier chain. It reads the current untouched animation pose, preserves swing clearance, adapts support feet to collision, and keeps each knee pole in its anatomical hip lane. Turning while moving keeps the walking clip; large turn/step transfers release old foot anchors rather than pulling the legs across the body. The source geometry, collider, gravity and gameplay speeds are unchanged.

`tests/astronaut_gait_review.gd` checks actual rendered arm movement, swing clearance, forward knee bend relative to the hip–ankle line, separate knee lanes, foot locks, moving turns and walk/fast phase continuity. Native side views are saved as `evidence/scout_gait_side_*.png`. Eight gait checks, nine contact checks and 26 integration checks pass after the correction. The gait remains project-authored, rather than motion capture or certified suit biomechanics.
