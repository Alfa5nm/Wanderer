# Astronaut/scout verification — 2026-10-07

Godot 4.6.1, Compatibility/OpenGL, Jolt, Windows, NVIDIA GeForce GTX 1650. Implementation verification was grouped, with retries limited to failed checks or changes affecting the checked behavior. These results qualify an illustrative playable prototype, not astronaut biomechanics or scientific traversability safety.

## Completed checks

- Exported asset: acyclic hierarchy, no IK/FK/pole controls, ten clips, normalized four-influence weights, valid joint indices, texture cap, decreasing LOD counts, transparent glass export and unchanged original EMU Blender data compared with the preserved ZIP. `evidence/astronaut_asset_checks.json`.
- Native integration: H and injected D-pad switching, injected left/right sticks, 1× human time/default physics, walking/stopping, bounded pelvis, physical bones/fall/recovery, restored rover pace, obstacle detour, invalid-coverage failure, replan completion, unchanged terrain collision, deduplicated persistent findings and curated source records. `evidence/astronaut_scout_checks.json`.
- Physical contacts: standing, 20 cm step, 20° ramp, stopping, reach/sole checks, blocked recovery rejection and clear recovery. `evidence/astronaut_contacts.json`. The step helper checks a capsule-sized forward clearance and support, avoids treating walkable slope contacts as steps, and releases foot locks during a step transfer. This is a discrete step approximation, not force-based leg locomotion.
- Six recording presets rendered at 1920×1080, 1600×900 and 1366×768. Actual proximity caused a simulated obstacle finding, a revised proposal and a reset to unverified state. `evidence/scout_capture_checks.json`. Daylight/front/low-Sun/night and transformation renders are under `evidence/scout_*.png`; HUD retraction and map visibility were explicitly checked.
- Full scout-to-human flow: rover sensed the existing seeded obstacle, worker returned a revised 12-point proposal, injected ordinary player movement walked the astronaut to the destination, and returning to Mars projected the persisted session findings. 18.28 m displacement, 19.91 seconds of human movement at 1×. This test steers the player's camera/input to follow waypoints; autonomous human following is not part of the game. `evidence/scout_follow_route.json`.
- Camera/reset and preparation-failure checks retain the ready terrain and fixed collision. `evidence/scout_release_smoke.json`.
- Existing camera suite: 11 checks; globe: 48 checks; procedural terrain: 25 checks passed. The globe content expectation was updated to include two sourced science-area anchors. Existing rover suite completed its 24 measurement cases. Original main.tscn and rover/world/camera scripts have no semantic changes.

The old rover acceptance report still has a pre-existing source-integrity failure: the external original NASA Blender file has a different checksum from its initial metadata. The same mismatch was already present in the committed report before this task; this implementation did not touch that file or rewrite its expected checksum. The 24 physical/behavior checks in the report pass. Existing ObjectDB and small GL texture shutdown warnings also remain; no new GDScript runtime/parser error was observed in the completed checks.

## Performance measured

Eight-second moving-camera/astronaut windows per resolution, with native Compatibility effects enabled, VSync disabled:

| Viewport | Median frame | 95th percentile | Worst observed |
|---|---:|---:|---:|
| 1920×1080 | 10.29 ms | 14.70 ms | 87.30 ms |
| 1600×900 | 7.63 ms | 11.50 ms | 55.05 ms |
| 1366×768 | 6.65 ms | 8.42 ms | 33.15 ms |

During a nine-second worker-plan window: 9.92 ms median, 13.15 ms p95, 72.82 ms maximum at 1366×768. Godot's static-memory monitor ranged around 442–463 MiB; its texture-memory monitor around 339–376 MiB. These counters are not total process resident memory and must not be added as independent allocations. Maximum measured IK update in the sustained run was 0.339 ms, with a maximum locked-foot horizontal error of 0.54 mm. Separate collision fixtures measured below 0.1 mm; turning/recovery integration measured up to 15.9 mm. Foot error measures the final posed ankle versus its retained target, including reach/step lock release behavior; it is not a calibrated contact force or complete foot-slip measurement.

Warm terrain preparation: approximately 0.24–0.27 s in these runs. This task reused the existing preparation cache and did not repeat a new cold terrain build; prior terrain cold-build results remain in the terrain documentation. Worker route builds took 2.54 s in a warm repeated plan and approximately 7.7–8.4 s for the complete geographic/scout runs. Unknown sections remain provisional while the worker runs. Results are applied only for the current destination generation.

The final material/accessory smoke includes a separate twelve-second 1600×900 walking measurement: 8.29 ms median, 9.71 ms p95, 91.40 ms worst observed, 493 MiB static/354 MiB texture monitors, 0.301 ms maximum IK update and 0.41 mm locked-foot error (`evidence/scout_release_smoke.json`). Occasional upload/refinement/initialization stalls mean **locked 60 FPS is not claimed**, despite typical frame times below 16.7 ms. These are short laptop measurements, not a long-duration thermal or cross-hardware benchmark. Physical controller hardware was unavailable; input paths were exercised through injected Godot events.

Compatibility remains the recommended capture configuration. The existing optional Forward+ trial's substantially slower measurements remain documented in FORWARD_PLUS_TRIAL.md; it was preserved rather than re-profiled for this milestone.

## Limits and readiness

The demonstrated scenario is an existing procedural collision rock, visibly SIMULATED OBSTACLE. A bounded search of valid fine Gale elevations did not yield a qualifying measured-slope scenario with safe staging and an alternative in the checked candidate set; this does not mean Gale has no suitable slopes. Recording preparation can select one if it validates, and never invents a measured slope.

The astronaut has authored procedural clips and runtime contacts, a simplified ragdoll and a reactive third-person camera. It is usable for the scout handoff; full pressurized-suit mechanics, lifelike motion capture, self-collision anatomy and broad terrain certification remain outside scope. Recorded science-area anchors are archived rover localizations, with unknown absolute accuracy/target offsets. Data links and scientific limitations remain visible. Raw footage, edit, voiceover and browser deployment remain deferred.
