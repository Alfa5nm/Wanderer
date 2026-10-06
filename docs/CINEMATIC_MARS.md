# Cinematic Mars visual system

The shared atmosphere and local daylight treatment are now extended by [Dusty Mars](DUSTY_MARS.md). Atmospheric controls live in `PlanetVisualSettings.atmosphere` (`MarsAtmosphereProfile`) rather than the earlier independent shell/density settings. Surface daylight sky fill fades to zero after twilight; the orbital scene retains dark nightside lighting.

The desktop planetary interface uses a shared `PlanetVisualSettings` Resource and `PlanetLighting` controller. The scene exposes `visual_settings`, assigned to `planetary_map/visuals/cinematic_mars.tres`; edit the Resource in the inspector. Default values live in `planetary_map/visuals/visual_settings.gd`. Restart the scene after changing the preset defaults. This pass retains GL Compatibility and the original rover scene.

## Camera

Mouse events accumulate until the next frame. Drag sensitivity scales with viewport height, field of view and normalized ground clearance. Mouse dragging stops at release, with no between-event or post-drag inertia. Controller rotation retains damped acceleration and braking. Controller input uses a radial 0.18 dead zone and progressive stick response. Zoom interpolates logarithmic clearance, with descending input damping residual orbit momentum. Distance and pitch limits remain enforced.

`focus_on_coordinates(lat, lon, zoom_level, duration=-1)` retains the existing arguments and completion signal. A negative default duration selects 0.8–2.8 seconds automatically. Positive explicit durations remain authoritative for deployment timers. Distant targets (>30 degrees) use a stable great-circle route with a pullback and approach; nearby targets move directly. Manual input kills the previous flight, preventing stale completion callbacks. Single selection preserves a closer view; double-click applies the target focus distance.

## Lighting and shaders

The same Sun direction drives a `DirectionalLight3D`, the visible solar disk and atmospheric scattering. The sky has sparse deterministic antialiased stars, a representative 0.35-degree solar disk and a restrained halo. It is a fixed demo sky, not a dated ephemeris or catalogued star map. Camera translation and floating-origin rebasing do not move the sky.

The environment disables ambient and reflected sky illumination. Exposure is fixed. Terrain has no emission or ambient fill, so the nightside can reach RGB zero while the HUD stays readable. Terrain uses physical elevation-derived normals; procedural normal variation defaults to zero. Near-surface directional shadows use a clearance-dependent render-space range, capped at 300 units, and are disabled at orbital altitude.

The atmosphere is a fullscreen transparent shader integrating eight samples through a radial density shell (four-sample preset available). GL depth reconstruction stops at opaque terrain; a conservative analytic ground intersection prevents samples entering the planetary interior. Near the surface, the reference radius follows the sampled local ground, avoiding a solid-haze artifact in below-reference basins. Analytic planetary shadowing suppresses direct scattering on the deep nightside. Scattering is attenuated and capped, and modifies the sky as well as the surface view. It does not use renderer-specific volumetric fog or bloom.

## Terrain continuity

Six coarse displaced cube-face patches remain available while fine tiles rebuild. Missing root jobs are restored when the refinement queue changes. Visibility is recalculated as soon as the requested frontier changes and after stale children are removed. This prevents incomplete frontiers during interrupted camera flights. The opening background fades only when all six coarse faces are uploaded; the HUD and navigation remain available during preparation. Deployment uses a separate foreground cover. Terrain planning yields between roughly 2 ms work slices and uses a captured camera projection, avoiding long planning stalls during rotation. Camera movement immediately rebases all patches, including tween-driven movement after ordinary frame processing. The mesh remains numeric terrain, rather than a replacement textured sphere.

## Verification

`tests/cinematic_run.gd` checks 30/60/120 FPS equivalence, event accumulation, zoom sensitivity, distant pullback, flight interruption, polar stability, Sun alignment and disabled ambient illumination.

`tests/cinematic_capture.gd -- --planet-offline` captures orbital day, terminator, night, Sun, solar occlusion, Jezero at 1920x1080/1600x900/1366x768 and Bradbury. Reports are saved in `evidence/cinematic_report.json`. Surface light is a presentation setting, not radiometric calibration. Source imagery retains baked illumination and its independent grayscale/false-color classification.

Pixel inspection of the nightside and occluded solar center reached RGB zero; the unobstructed Sun reached 255. Existing globe acceptance checks include repeated Curiosity deployment and rover driving after handoff. Terrain and streaming suites pass, including bundled dataset identity preservation under eviction.

## Limits

The atmosphere uses approximate single scattering, a simplified Sun transmission and an analytic radial planetary shadow; it is not a scientific atmospheric simulation. The local ground reference is approximate across a wide view. The camera follows terrain clearance at its focus point, rather than sweeping a collision volume along every flight. Fine geometry and imagery still refine asynchronously; source illumination and footprint seams remain possible. Frame timing measurements describe the tested desktop, not a guarantee for other hardware or browser exports.

## Measured desktop result (2026-10-05)

On the GTX 1650 Compatibility renderer at 1920x1080, a 120-frame orbital sample measured 6.8 ms median and 10.4 ms P95 with atmosphere; the paired no-atmosphere sample measured 6.9 ms median and 10.0 ms P95. This short sample shows no material median cost, but is not a stable-60-FPS guarantee during refinement or loading. Tests ran with fixed simulation pacing, and other validation work was active. The new motion suite has nine passing checks; globe has 48, terrain 34 and streaming 13. The full 24-case rover physics measurement run completed with its original fixed physics steps in accelerated headless mode.
