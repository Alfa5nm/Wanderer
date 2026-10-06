# Optional Forward+ trial

The project default remains GL Compatibility. `scripts/launch_forward_plus.ps1` launches a separate Vulkan/Forward+ process without modifying `project.godot`. Pass `-LocalTerrain` to start directly in the Bradbury driving patch, or omit it to start at the globe. Set `-GodotPath` if the Godot executable is elsewhere. Close that game and use your ordinary launch to return to Compatibility. Renderer changes require a restart, not a live graphics-setting change.

Forward+ local terrain enables native volumetric fog on Balanced and High. Its warm scattering, anisotropy and strength follow the shared illustrative atmosphere settings, with no emissive glow. Daylight fades its density to zero at night. The shared Sun lights the volume and supplies shadows; custom Mars aerial perspective is reduced to avoid two full-strength haze layers. Terrain settings expose a **FORWARD+ · native volumetric dust** checkbox for comparison. Performance quality uses the custom atmosphere alone. Source appearance retains atmosphere and measured geometry.

Orbital atmosphere, local haze and soft dust particles now branch their depth reconstruction for Compatibility's OpenGL depth range versus Forward+'s reversed Vulkan depth. Terrain, data, navigation, collision, rover parameters and startup scene are unchanged. This fixes the concrete shader portability issue found during the trial; changing only the renderer flag would not have been sufficient.

This is experimental, not the recommended default yet. Expect different tonemapping, sky reflection, shadow filtering and shader compilation delays. Native volumetric fog is costlier, can show temporal ghosting and uses a finite depth range (1500 m on Balanced, 2500 m on High). The distant scenery remains sourced and coarse. This is an illustrative dusty atmosphere, not calibrated Martian weather or physical soil simulation. Browser/export work remains deferred.

Official references: [Godot Environment volumetric settings](https://docs.godotengine.org/en/4.6/classes/class_environment.html), [depth reconstruction](https://docs.godotengine.org/en/4.6/tutorials/shaders/advanced_postprocessing.html).

## Trial results

Actual Vulkan rendering on the GTX 1650 passed 12 local/appearance/pacing assertions, plus four targeted orbital/original-field-lab assertions. A matching Compatibility run passed 13 assertions, including original direct scene loading. Both renderers displayed local terrain at 1920x1080, 1600x900 and 1366x768, with source appearance and night checks. The first Forward+ orbital capture happened before root terrain was ready; the corrected readiness-based capture replaces it. No script/shader compilation errors remained. Existing ObjectDB shutdown warnings persist; Compatibility also reports existing GL texture cleanup warnings.

Five-second moving-camera samples, Balanced, 6x local exploration:

| Size | Compatibility median / p95 | Forward+ median / p95 |
| --- | --- | --- |
| 1920x1080 | 15.28 / 24.47 ms | 49.33 / 66.33 ms |
| 1600x900 | 11.88 / 19.07 ms | 34.84 / 104.24 ms |
| 1366x768 | 8.29 / 10.48 ms | 29.20 / 43.75 ms |

The Forward+ sample with native fog switched off still measured 36.84 / 58.88 ms at 1600x900, so the slowdown cannot be assigned solely to fog. That sample used a stationary camera and a different warmed state; it is not an isolated A/B cost measurement. Forward+ texture memory reached roughly 445 MiB at 1080p versus approximately 265 MiB in Compatibility. Startup compilation, renderer overhead, shading and shadow settings need profiling before a default migration. These are short available-laptop observations, not sustained FPS certification; keep Compatibility as the default.

Evidence: `evidence/renderer_trial_forward_plus.json`, `evidence/renderer_orbit_lab_forward_plus.json`, `evidence/renderer_trial_gl_compatibility.json` and the `dusty_renderer_*` screenshots. Shader fixes preserve the Compatibility depth branch. No terrain, collision or original rover script changes were required for this trial.
