# Terrain validation record

Run date: 2026-10-01. Machine: NVIDIA GeForce GTX 1650, Godot 4.6.1 Compatibility renderer.

The numeric suite (`tests/terrain_run.gd`) passes 34 checks: MOLA/areoid datum handling, poles and longitude seam, invalid masks, HiRISE/CTX fallback, terrain ray picking and occlusion, cube-face round trips, shared edges, adjacent LOD balance, coarse-edge stitching, morph attributes, transformed positions, outward normals, survey-cell backtracking, injected controller selection/cancel, eight landing anchors and imagery validity independent of display opacity.

The streaming suite (`tests/terrain_streaming.gd`) passes 12 checks: packaged worker COG read, valid HiRISE discovery, warm-cache reuse, checksum rejection, missing files, fallback after corruption, worker failure, cancellation, offline preservation, disk pruning and decoded-memory accounting. The packaged worker is self-contained under `planetary_map/tools/mars_terrain_worker/`. The prepared offline assets are about 415 MiB; worker plus licenses are about 157 MiB. The conservative decoded core estimate is 487.1 MiB including packed imagery validity masks against the initial 512 MiB budget. This estimates managed terrain and imagery, not total process or GPU memory. The optional cache limit is 2 GiB.

The globe regression suite passes all 48 existing checks, including direct rover-scene loading, navigation backtracking, controller bindings, retry handling and rover driving after deployment. `Validate.ps1 -Controls` also passes its rover checks; its known external NASA Blender source hash mismatch is pre-existing and outside this project.

Graphical evidence is in `evidence/terrain_visual_checks.json` and the PNG captures. Exact captures were produced at 1920×1080, 1600×900 and 1366×768; mission and cell panels remained inside the viewport. Settled local exploration measured roughly 6.94 ms median and 7.1–7.9 ms p95 per frame. Orbit measured 6.93–6.95 ms median with 14.7–15.6 ms p95 in the latest run. Quadtree selection reached 59.99 ms in the worst measured refinement pass. Deployment including scene activation had a 6.94 ms median, 12.04 ms p95 and a 267 ms maximum activation spike on this laptop. Terrain warm-up takes roughly 8–10 seconds for a new close view. The project targets 60 FPS during settled navigation; refinement and rover activation remain visible limits rather than being hidden by the measurements.

No physical gamepad was connected; controller tests inject Godot events. Online service failure, missing coverage and worker failure preserve the bundled globe. Exported-PCK packaging of raw terrain and the external worker directory still needs a separate release build qualification. The field lab is not Gale terrain, and no traverse or public timeline is presented without an official dataset.

## Visual correction pass — 2026-10-02

The four-scale captures in evidence/terrain_*_direct.png use the corrected coverage fade, distance-dependent regional imagery and a front-surface atmospheric limb. The limb remains illustrative. These changes leave numeric elevation unchanged. Source mosaic illumination seams and uneven available detail remain visible; visual acceptance for Renderer V2 is not complete. The frame-time measurements above are historical. A fresh isolated three-resolution run passed all screen-size, mission-click, panel and deployment checks after an initial concurrent run failed its first click. Current timings are recorded below.



The isolated correction-pass run measured about 6.95 ms median and 7.1 ms p95 for settled local views. Quadtree selection peaked at 53.313 ms, and scene activation at 125.136 ms. The renderer reports roughly 212–221 MiB of video memory and 427–429 MiB of Godot static memory near Bradbury; these counters are not a complete operating-system working-set measurement. Close-view terrain warm-up remains about 8–10 seconds. All 48 globe checks passed, as did the rover behavior and 15 injected control checks; the rover provenance report continues to flag the external NASA source-file hash mismatch. Stable 60 FPS through every refinement and activation step is not achieved.


## Cosmoscope integration verification — 2026-10-02

The actual upstream repository was reviewed at commit 0f35ad4c56e6a8f727203f23b26bd8857d422a00. All 31 Cosmoscope/Godot checks, nine broker tests, 34 terrain checks, 12 streaming checks and 48 globe checks passed. The graphical offline test passed five checks, including automatic bundled-pyramid loading, settled refinement, no external worker and preservation of the Bradbury sample. Its rendered output is evidence/cosmoscope_bradbury.png. Live USGS catalog discovery recorded two cold misses followed by two hits without further catalog requests; the frozen worker also prepared valid HiRISE and CTX COG crops.

The sourced Bradbury demonstration pyramid has 18 tiles across three levels and adds about 4.9 MiB. Terrain assets total about 420.0 MiB, with the worker about 156.6 MiB; authoring scratch and the review checkout are excluded. The original full subsets remain retained, so this pass does not claim a reduction of the 487.1 MiB decoded core estimate. Current imagery source seams remain visible. The prior measured frame-time limits remain applicable as historical evidence; this streaming integration has not undergone a new full performance qualification.

See [Cosmoscope integration](COSMOSCOPE_INTEGRATION.md) for exact reuse decisions, source/provider limits, changed components and reproduction.

