# Procedural Terrain Plan

Agreed architectural direction from the project discussion, 5 October 2026.
Status: the first native Godot terrain pipeline is implemented; verification results and limitations are recorded in PROCEDURAL_TERRAIN.md. The full visual editor, deformation and browser qualification remain pending.

## Goal

Build a typed procedural terrain graph in Godot, with a visual node editor inspired by Blender Geometry Nodes. Selecting a region on Mars should lead to a sourced, bounded, playable mission patch with terrain, collision, materials, seeded detail, and terrain-conforming route visualization.

The target is a browser-based Godot game. Heavy source preparation must happen before delivery or through a preparation service; the existing Windows GDAL worker cannot run inside the browser.

## Bounds and tile selection

Keep three boundaries separate:

| Boundary | Role |
|---|---|
| Source footprint | Actual valid coverage of each source product, including internal holes |
| Streaming tile | Stable geographic address for loading, caching, and rendering |
| Mission boundary | Playable region, potentially spanning multiple streaming tiles |

Use geographic coordinates for addressing and a documented local metre coordinate frame for gameplay. Equal longitude/latitude intervals do not have equal physical dimensions across Mars.

A selected tile becomes a mission candidate. Check coverage before preparation and expose valid high-resolution terrain, gaps, fallback coverage, and physical dimensions. Include a surrounding terrain collar outside the mission boundary for continuous scenery, lighting, collision edges, and projection.

The choice between arbitrary Mars selection with preparation latency and prevalidated mission patches remains open.

## Source-to-terrain pipeline

1. Discover numerical elevation and matching imagery. Mars Trek supports area selection and visual context; imagery tiles must not be treated as numerical heights.
2. Align and reproject products into the mission coordinate frame, preserving units, elevation reference, source resolution, provenance, and independent validity masks.
3. Generate terrain geometry from numerical heights and derive slope, aspect, curvature, geometric normals, and terrain-based ambient occlusion.
4. Add supported surface classifications and separately identified procedural detail.
5. Package chunk geometry, collision, materials, source metadata, layers, graph parameters, and deterministic seeds for Godot.

| Channel | Interpretation |
|---|---|
| Elevation / height | Numerical terrain; local height is relative to the chosen origin |
| Depth | View-dependent rendered depth; subsurface depth needs separate evidence |
| Color | Registered imagery with baked illumination and false color identified |
| Heat | Sourced thermal observations retaining footprint and time, or labeled simulation |
| Normal | Geometry-derived normals plus labeled procedural microdetail |
| Specular / roughness | Material assumptions unless supported observations constrain them |
| Ambient occlusion | Rendering result derived from reconstructed geometry |

## Modules and development order

| Order | Module | Responsibility | Initial nodes |
|---|---|---|---|
| 1 | Region & Coordinates | Mission bounds, source footprints, local metres, neighboring chunks | Select Region, Geographic to Local, Crop, Border Padding |
| 2 | Raster & Fields | Aligned layers and position-based sampling with validity and provenance | Sample Height, Sample Image, Validity, Slope, Normal, Curvature |
| 3 | Geometry Core | Terrain meshes, attributes, normals, and collision | Grid, Displace, Calculate Normals, Write Attribute, Build Collision |
| 4 | Graph Evaluator | Typed connections, dependency evaluation, caching, and invalidation | Parameters, Math, Remap, Clamp, Blend, Seed |
| 5 | Chunk & Detail Manager | Partitioning, detail levels, shared borders, and seamless transitions | Partition, Neighbor Samples, Detail Level, Stitch Borders |
| 6 | Surface & Scatter | Materials, zones, rocks, and dust driven by fields | Material Weights, Scatter Points, Filter by Slope, Instance Rocks, Exclusion Zone |
| 7 | Projection & Routes | Terrain-conforming paths and survey visuals | Sample Path, Project to Terrain, Ribbon, Edge Fade, Outcome Style |
| 8 | Local Deformation | Bounded geometry changes and collision updates | Brush, Track Stamp, Height Delta, Rebuild Dirty Chunk |
| 9 | Graph Editor & Inspector | Visual editing, previews, source inspection, and profiling | Node Canvas, Field Preview, Source Inspector, Timing and Memory Display |

Build modules 1-5 with a minimal inspector first. Add named attributes, reusable node groups, deterministic seeds, and composable fields early. Grow the full visual editor around a functioning pipeline rather than starting with a large node catalog.

## Core interfaces

- **Region definition:** bounds, coordinate frame, elevation reference, source versions.
- **Raster layer:** values, units, spacing, validity, source metadata.
- **Field:** a value evaluated at a position, such as height, slope, color, material weight, or exclusion.
- **Geometry chunk:** vertices, triangles, attributes, bounds, collision.
- **Graph result:** outputs, seed, versions, warnings, dependency hashes.

Fields remain distinct from meshes: one slope field can drive scattering, roughness, route styling, and dust accumulation without duplicating terrain.

```text
Selected Region
      |
Aligned Height + Imagery + Validity
      |
Chunk Grid -> Height Displacement -> Normals -> Collision
      |
Slope / Curvature / Surface Fields
      +-- Material Weights -> Terrain Shader
      +-- Scatter Points -> Rock Instances
      +-- Path Projection -> Fading Route Ribbon
```

## Execution and authoring

- **Preparation:** expensive reprojection, reconstruction, validation, and baking.
- **Browser CPU:** bounded mesh generation, sampling, collision updates, and scatter placement.
- **GPU shaders:** surface color, roughness, micro-normal detail, route fading, and visual dust.

Each node declares its execution support. Preparation-only nodes ship as baked outputs with retained parameters and provenance.

Use Blender Geometry Nodes to prototype and inspect reconstruction, material weights, scatter rules, collision representations, and debug views. Share mathematical rules and parameters with Godot; do not assume Blender node graphs transfer directly.

## Geometry and presentation rules

- Allocate mesh density to useful geometry and interactions, with dense nearby chunks and coarser distant chunks. Share edge samples between neighbors.
- Keep detailed imagery as projected textures. Use vertex colors/attributes for broad material weights, dust coverage, and zones; do not require a vertex per image pixel.
- Give gameplay-sized rocks corresponding collision. Use cheaper instances for tiny visual detail.
- Restrict deformation to affected local chunks rather than rebuilding the entire region.
- Construct route ribbons by resampling paths onto terrain height and normals. Blend edges and ends smoothly; handle cliffs, missing data, detail changes, and obstacle intersections.
- Support top-down or angled route inspection and return to the actor view.
- Preserve the reason for failed or abandoned attempts. A retreat is not automatically an incorrect or impassable route.
- Keep scientific coverage boundaries inspectable even when visual transitions fade smoothly.

## First milestone and acceptance

Demonstrate: select one validated patch -> generate seamless chunks -> project imagery -> scatter seeded rocks -> project a smoothly fading route -> change a parameter and rebuild only affected outputs.

Verify coordinate placement, source alignment, invalid-data handling, chunk seams, collision agreement, repeatable seeds, route projection, and dependency invalidation. Measure loading, memory, frame time, and input response in the actual browser export before increasing detail.

## Decisions still needed

- Arbitrary tile preparation versus prevalidated mission patches.
- Initial playable physical dimensions and high-resolution coverage threshold.
- Browser/device targets and performance budgets.
- Preparation service deployment and source delivery strategy.
- Initial graph editor depth and deformation scope.

This document records the agreed architecture; it does not imply these decisions are resolved or these modules are implemented.

## Implementation decisions (5 October 2026)

Browser engineering is deferred by the user. Native runtime preparation reuses the existing numeric terrain sampler, with no new source download required. Bradbury and survey cells share one typed generation graph. Mission patches default to at most 256 × 256 metres with a 64 m scenery collar; this is a bounded playable subset at the selected cell center, not a claim that the full streaming tile is reconstructed at high resolution. Very narrow polar cells use a minimum 16 m playable width and can extend across the cell edge.

The first inspector exposes mesh sampling, procedural rock density and seed. Regional elevation gaps fall back to numeric MOLA. Mesh spacing never implies source resolution. The original DEPLOY action and directly runnable main.tscn retain the mobility field lab; DRIVE LOCAL TERRAIN enters the geographic patch. No public synthetic historic route is added: an optional Shift-click path is explicitly user planned.

See PROCEDURAL_TERRAIN.md for the graph, scene handoff, source information and remaining work.


## Loading and presentation follow-up (6 October 2026)

The shared graph now persists prepared artifacts with validation, restores their source inventory on revisits, and uses dependency hashes to apply rebuilt or disk-restored settings. Local source imagery has a narrower mask-preserving blend, subtle cosmetic dust shading and irregular seeded rocks with convex collision. A coarse 1,536 m sourced scenery annulus extends beyond the existing collar without expanding driving bounds. The same pipeline applies to Bradbury and arbitrary survey-cell centers, with MOLA/Viking fallback rather than invented global high-resolution coverage. Native first-build latency remains roughly 16–17 s; measured warm preparation is approximately 0.15–0.16 s. Adaptive gameplay LOD, cross-resolution imagery morphing and the visual graph editor remain subsequent milestones.


## Measured detail and cinematic styling milestone (6 October 2026)

Visual chunks now refine independently of the unchanged rover collision, using measured error estimates, balanced levels, canonical shared boundary anchors and interior morphs. The shared typed graph adds cached elevation-derived cavity shading and deterministic gravel. TerrainSurfaceStyle supplies explicitly illustrative hue, grains and material variation; SOURCE APPEARANCE disables the cosmetic treatment. The original base edges remain the transition anchors, so refining interiors does not imply new edge measurements. See PROCEDURAL_TERRAIN.md for controls, transition policy, performance observations and remaining limitations.
