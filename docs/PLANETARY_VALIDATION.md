# Planetary interface validation

Validated with Godot 4.6.1 GL Compatibility on NVIDIA GeForce GTX 1650. Globe integration: **48/48 checks passed**. The graphical test confirmed actual 1920×1080, 1600×900 and 1366×768 pixel captures, contained contextual panels, mouse clicks on Explore Mission at all three sizes, and deployment through the visible Deploy button into the original rover field lab.

## Runtime measurements

| Scenario | Median frame ms | 95th percentile ms | Maximum frame ms |
|---|---:|---:|---:|
| Orbit 1920×1080 | 6.943 | 7.127 | 7.262 |
| Orbit 1600×900 | 6.940 | 7.091 | 7.354 |
| Orbit 1366×768 | 6.939 | 7.103 | 7.253 |
| Deployment including activation | 6.944 | 7.136 | 59.376 |

Globe navigation ran near the display's 144 Hz cadence on this machine. This is a short local benchmark, not qualification of integrated-GPU laptops. Scene activation still has a brief peak around 60 ms, covered by the transition blend; zero activation stall is not claimed. Preloaded external assets are retained across old-scene teardown to avoid loading them again. Screenshot PNG encoding is excluded from frame measurements.

## Integration checks

Coordinate cardinal axes, poles, longitude wrapping, altitude, transformed spheres and UV anchors passed. Tests also covered occlusion, enlarged marker hit targets, mouse orbit/wheel, double-click focus, focus cancellation, controller orbit/zoom/select/back, orbit axes preserving UI focus, normalized planet radius, resource content, timeline filters, route projection, hidden development routes, missing texture/route/scene recovery, cancellation of descent, repeated deployment, global time reset, rover camera attachment and driving after deployment. Gamepad input is synthetic; physical controller hardware was not available.

The existing rover import, physics/solver and graphical controls suites completed successfully. Regenerating the existing engineering acceptance report gives **24/25**: its external original-source hash check fails. `assets/geometry.json` expects NASA_Curiosity_Clean.blend SHA-256 `77fe6665223e38972728af404f1a277f0b0ab467fce5cc0aed6eba93488b74e2`, while the file outside this project currently hashes to `e6e808d2d1d4f9191d86c006f7c3ef58cebc5180fab088786cf9f27ecf05b3bc`. The globe work did not write to that source file, the exported rover asset, or any rover production script. The mismatch is preserved as evidence; no baseline was changed to make the check pass.

## Artifacts

- `evidence/globe_checks.json`: complete integration results.
- `evidence/globe_visual_checks.json`: resolution, interaction and frame-time results.
- `evidence/mars_orbit_*`, `mars_gale_*`, `mars_bradbury_*`: rendered views at all requested resolutions.
- `evidence/mars_descent.png`, `mars_deployed_rover.png`: approach and resulting gameplay.
- `evidence/globe_rover_regression.log`, `acceptance.json`, `source_integrity.json`: existing rover regression outcome and external hash mismatch.

The public globe has no debug text or synthetic traverse. Its bundled global imagery becomes coarse at close range; high-resolution Gale terrain remains a future integration. The original field lab is accurately labeled as the deployment destination.
