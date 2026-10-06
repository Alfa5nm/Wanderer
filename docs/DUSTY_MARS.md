# Dramatic dusty Mars

Compatibility rendering, geographic elevations, collision, navigation and field-lab deployment are retained. This pass changes appearance only. The default is dramatic distant dust with a clear foreground, a tan surface sky, a brighter horizon and restrained blue around the twilight Sun. Star visibility fades with daylight. The local surface no longer uses an unobscured black space sky in daylight.

## Controls and scene flow

In a sourced driving patch, open **TERRAIN SETTINGS & SOURCES**. **Dramatic dusty** selects strength 1.35; **Clear inspection** selects 0.45. The slider spans 0–3. These are illustrative weather controls, not reconstructed opacity observations. **Graphics** controls atmospheric integration (4/8 samples), drifting-dust count, 2×/4× MSAA, glow and contact AO; it also selects the existing terrain-detail quality. The separate Detail control can override mesh refinement without changing atmosphere quality. Settings survive return/deployment within the current application session, but do not alter source cache keys or collision.

**SOURCE APPEARANCE** removes illustrative coloration, material normals/variation, gravel and drifting/wheel dust. Source imagery, measured geometry, lighting, aerial perspective and measured-elevation indirect occlusion remain. Large collision rocks stay present. Fine regional grayscale and false-color labels remain available in the source inspector. Original `main.tscn` and rover scripts are unchanged.

The driving HUD is reduced to a compact footer; detailed telemetry remains on F1. Existing camera controls and damping are untouched. Low-Sun/night examples are representative lighting arrangements, not date/time ephemerides.

## Architecture

- `MarsAtmosphereProfile` is a Resource on `PlanetVisualSettings`. It owns illustrative density, extinction per metre, scale/top height, anisotropy, near-clear distance, dust hue, daylight fill and graphics quality.
- `dust_common.gdshaderinc` supplies shared RGB sky radiance, a directional dust phase function, twilight falloff and transport lookup. `surface_sky.gdshader` uses these for the sky, coherent solar disk/halo and stars. The existing orbital atmosphere uses the same profile, transport and physical radius in metres.
- `surface_haze.gdshader` is a depth-bounded transparent full-screen pass. It reconstructs Compatibility depth with the [-1,1] NDC convention and integrates density along the camera-to-terrain segment. The first 45 m remain clear; height includes the patch radial reference and local camera coordinates. No haze is painted across the sky a second time. Haze priority follows cosmetic particles and precedes UI.
- `PlanetLighting.configure_surface()` installs the surface sky/haze and atmospheric daylight fill. `set_direction()` keeps the directional light, sky and haze aligned. Direct sunlight is disabled below the local horizon; atmospheric fill fades through twilight and reaches exactly zero below the twilight interval. There are no hidden night fill lights or emissive night terrain. Native Compatibility contact AO and restrained highlight glow are enabled at Balanced/High.
- `MarsLocalDust` creates low-opacity, camera-facing CPU particles with opaque-depth intersection fading and distance fading. Sparse drifting dust follows the rover's surroundings. Six small emitters follow actual wheel positions and emit only when wheels turn and contact ground. Particle state never influences physics, friction, terrain or rover telemetry.
- `TerrainSurfaceStyle` installs packed sand/rock normal-and-roughness maps. Three random texture offsets blend over a triangular lattice with explicit texture derivatives, preserving mip selection across cell boundaries. Normal gradients are projected onto the measured surface tangent plane. Fine detail fades with pixel footprint. Cavity now modulates indirect AO without multiplying baked source albedo darker. Cosmetic exposed-rock variation is an artistic mask, not soil classification.

## Asset preparation and provenance

Run `python scripts/prepare_visual_assets.py` with NumPy and Pillow during development to reproduce the three bundled PNGs under `planetary_map/visuals/assets/`. No user installation or runtime preparation is needed. Sand and rock maps are project-authored periodic analytical textures, not photography or NASA observations. Linear RGB encodes X/Z/up normal components and alpha encodes roughness. They never displace terrain.

The 256×128 transport table integrates an exponential dust density profile along 64 spherical-ray samples over a 3,396.19 km reference radius. It stores illustrative RGB solar transmission versus Sun elevation and altitude and a broad diffuse approximation. Its RGB extinction coefficients are an artistic fit; it does **not** reproduce calibrated aerosol spectra, observation-specific dust opacity, full multiple scattering or physical radiometry. The twilight blue aureole is an empirical visual approximation guided by NASA reference imagery. Resource changes to density/scale affect runtime haze; changing the table's reference profile requires regenerating it. The runtime cost is table sampling, not heavy precomputation.

Research guiding the implementation:

- [NASA/JPL sunset sky colors](https://www.jpl.nasa.gov/images/pia00917-color-variations-in-the-sky-at-sunset/) and [natural versus white-balanced lighting](https://www.jpl.nasa.gov/infographics/mars-lighting-conditions/).
- [Hillaire: scalable atmosphere rendering](https://onlinelibrary.wiley.com/doi/10.1111/cgf.14050), [Bruneton: precomputed atmospheric scattering](https://ebruneton.github.io/precomputed_atmospheric_scattering/index.html), and [MSL dust phase-function study](https://arxiv.org/abs/1905.01074). These inform the architecture; this project is a reduced RGB approximation, not a complete implementation of either atmospheric paper.
- [Deliot and Heitz: stochastic texture tiling/blending](https://eheitzresearch.wordpress.com/738-2/). The shader uses simplified randomized-offset blending; it does not implement their full histogram-preserving synthesis.
- [Filament PBR documentation](https://google.github.io/filament/main/filament.html) informs indirect-only cavity occlusion.
- [Godot 4.6 renderer capabilities](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html). Compatibility has simplified SSAO (radius/intensity controls), glow and MSAA. This pass does not claim native volumetric fog, PCSS, temporal AA or dynamic global illumination.

## Verification and limitations

`tests/dusty_capture.gd` captures Bradbury, Jezero and a coarse MOLA patch in daylight, low Sun, twilight and night at 1920×1080, 1600×900 and 1366×768. It also captures close-up, source/clear, distant and overhead views, compares Filmic and AgX, exercises quality/strength controls, checks unchanged measured heights/collision, drives the rover, repeats deployment and records 30 s Bradbury / 10 s other-site navigation samples. Existing numeric, camera, globe and rover checks run in the same verification batch.

Terrain sunlight is shadowed, but the Compatibility atmospheric approximation does not ray-trace terrain shadows through dust; no accurate volumetric shafts are claimed. Transparent particles approximate airborne dust and can overlap; their density is deliberately low. Underlying coarse source imagery and flat measured landing terrain remain visible limitations. Existing preparation latency and shutdown resource warnings must still be reported. Sustained frame times, memory and final visual observations are recorded after verification below.

### Recorded verification, 6 October 2026

The combined batch passed 25 local numeric/rover-contact checks, 11 camera/lighting checks, 48 globe interaction checks and 49 rendered assertions. The original rover suite completed all 24 measurement cases with fixed simulation pacing (not real-time rendering pacing); straight travel measured 0.039782 m/s at 120 Hz and 0.039783 m/s at 240 Hz. Renderer, source heights, collision identity, navigation, source switching, arbitrary-cell deployment and repeat deployment remained intact.

The initial render showed an underexposed sky. Only the affected rendered pass was repeated after balancing sky radiance and daylight fill. All requested location/resolution/daylight combinations were captured, including exact-black sampled night ground. Filmic was retained after matched AgX comparison: both were close, with Filmic preserving the preferred readable contrast. Final captures are `evidence/dusty_*.png`, with assertions/timings in `dusty_visual_checks.json`. A targeted follow-up verified optional-map fallback and newly added wall-time dust pacing; the timing probe initially sampled before node processing and passed after waiting for the node's frame. Its final evidence is `dusty_walltime_checks.json` and `dusty_walltime.log`.

Final Balanced navigation samples on the GTX 1650 (10 s each):

| View | Median frame | p95 frame | Maximum |
| --- | ---: | ---: | ---: |
| Bradbury 1920×1080 | 16.54 ms | 24.09 ms | 37.68 ms |
| Bradbury 1600×900 | 13.08 ms | 20.07 ms | 29.18 ms |
| Bradbury 1366×768 | 7.56 ms | 9.82 ms | 12.74 ms |
| Jezero 1600×900 | 12.29 ms | 18.93 ms | 23.70 ms |
| MOLA fallback 1600×900 | 11.89 ms | 18.22 ms | 165.08 ms |

A targeted 1080p Performance-preset sample measured median 10.11 ms and p95 12.99 ms, but a 587.81 ms spike occurred around initial quality/variant setup. Quality transitions and occasional stalls remain visible limitations; this is not a stable-60-FPS certification. The first rendered pass recorded lower frame times than the final pass, demonstrating run-to-run laptop variability. An unrelated pre-existing Godot instance remained running; these are observations on the available machine, not an isolated hardware laboratory benchmark.

Cold prepared-terrain creation took 16.78 s in the first graphical batch. The final warm pass started in 0.336 s and repeat deployment prepared in 0.354 s. Largest measured final upload batch was 2.10 ms, slightly above the soft 2 ms target. Navigation tracked approximately 445–450 MiB static memory and 230–267 MiB texture memory; external sampling of the final rendered batch peaked at 773 MiB resident and 1,519 MiB private allocation. These counters are different measures and must not be added or treated as the decoded-tile cache budget. The three bundled cosmetic assets total about 1.53 MiB on disk.

No production script/parser/shader compilation errors remained in the final runs. Existing GL texture/ObjectDB shutdown reports still occur, so shutdown cleanup is not accepted as clean even where the capture wrapper reports success. The fallback and performance smoke evidence retains its original timing-probe failure for transparency; the separate corrected wall-time probe passed. No numeric or rover suite was rerun after the sky-only repair.
