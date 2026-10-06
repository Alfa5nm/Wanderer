# Credits and references

## Pre-existing NASA visual asset

The rover mesh and textures originate from NASA's **Curiosity Rover (MSL), Clean** Blender download. NASA/JPL-Caltech rover imagery and engineering material underpin this adaptation. The team does not claim authorship of NASA's original mesh or textures, and does not imply NASA endorsement. NASA's insignia is not used as this game's or team's branding. Original visible equipment markings are part of the pre-existing model.

- [NASA original model download page](https://science.nasa.gov/3d-resources/curiosity-rover-msl/)
- [NASA images and media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)
- Source file supplied by the user: `NASA_Curiosity_Clean.blend`.
- Source SHA-256: `77fe6665223e38972728af404f1a277f0b0ab467fce5cc0aed6eba93488b74e2`.

Our contributions are inspection, wheel dimension correction, estimated folded arm pose, hierarchy adaptation, reproducible GLB export, explicit multibody physics, compliant rocker differential, bounded mobility actuators, coordinated steering, player controls, camera, test terrain, telemetry and runtime verification. Mesh topology was retained except removal of legacy non-render helper objects; no broad mesh optimization was necessary.

## Primary engineering references

1. [NASA MSL Landing Press Kit, July 2012](https://science.nasa.gov/wp-content/uploads/2024/03/44747_MSL-Landing.pdf). Overall dimensions, mass, speed, mobility, instrument layout; arm/turret discussion at printed pp. 39-40. Supplied local copy inspected.
2. [Rankin et al., Assessing Mars Curiosity Rover Wheel Damage, JPL, 2022](https://robotics.jpl.nasa.gov/media/documents/fmwi-rankin-2022-0225-final.pdf). Table 1 and Figures 2-3: diameter including grousers, width, skin and tread/flexure construction. Supplied local copy inspected.
3. [JPL arm kinematics paper, 2021](https://www-robotics.jpl.nasa.gov/media/documents/rankin-2540-arm-kinematics-2021-0102.pdf). Table 2 and Figure 2: five axes, arm base-to-turret-center length and mass categories. Supplied local copy inspected.
4. [MSL coordinate frames, PDS Imaging](https://pds-imaging.jpl.nasa.gov/documentation/MSL_COORDINATE_FRAMES.PDF). RNAV frame conventions. Supplied local copy inspected.
5. [Traction Control Design and Integration Onboard Curiosity, NTRS 20210007638](https://ntrs.nasa.gov/citations/20210007638). Terrain-aware wheel rates and floating-wheel handling motivate the simplified contact-tangent controller; actual flight algorithm is not reproduced.
6. [Driving Curiosity: First Seven Years, NTRS 20220000780](https://ntrs.nasa.gov/citations/20220000780). Research-pack background reference, not used to assign unverified actuator values.
7. [JPL planetary physical parameters](https://ssd.jpl.nasa.gov/planets/phys_par.html). Mars gravity baseline from the supplied research pack.
8. [Tools at Curiosity's Fingertips](https://science.nasa.gov/photojournal/tools-at-curiositys-fingertips/), [Curiosity's Work Bench](https://science.nasa.gov/photojournal/curiositys-work-bench/), [Wheel for MSL](https://science.nasa.gov/photojournal/wheel-for-mars-science-laboratory-rover/). Supplied component images and placement references.

The supplied `Curiosity_Blender_Engineering_Reference.md` is a secondary research guide. Its recommendations were treated as context, with the user's implementation brief controlling task scope. Numerical engineering confidence is tracked separately from visual fidelity.

## Software and notices

- [Godot 4.6 HingeJoint3D documentation](https://docs.godotengine.org/en/4.6/classes/class_hingejoint3d.html) and [Jolt integration documentation](https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html), checked for the installed 4.6.1 runtime.
- [Godot 4.6 Jolt contact listener source](https://github.com/godotengine/godot/blob/4.6/modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp), especially `EstimateCollisionResponse`, supports the wheel-load telemetry limitation described in the engineering report.
- [Blender 5.0 glTF manual](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html). The English manual endpoint was unavailable to the browser during this run; official indexed manual text and installed Blender 5.0.1 exporter RNA were used, followed by actual export/reimport checks.
- [Khronos glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html). Coordinate conventions and explicit visual interchange.
- [Godot Engine license](https://godotengine.org/license/) and [Godot third-party copyright notices](https://github.com/godotengine/godot/blob/4.6/COPYRIGHT.txt). Godot uses the MIT license; preserve its license and applicable bundled notices when distributing a packaged game executable.
- [Jolt Physics license](https://github.com/jrouwe/JoltPhysics/blob/master/LICENSE), MIT; included through Godot.
- [Blender license](https://www.blender.org/about/license/), GPL. Blender is an authoring tool and is not redistributed here.
- [Project Chrono SCM](https://api.projectchrono.org/10.0.0/classchrono_1_1vehicle_1_1_s_c_m_terrain.html), evaluated conceptually as an optional future offline validation reference; not installed or integrated.

No downloaded marketplace assets, external fonts, music or additional Godot plugins are required. Terrain, scenery and interface are generated by this project. The original NASA model and research PDFs retain their own source notices and are not relicensed by this document.


## Planetary interface assets and data

- **Numeric global elevation**: NASA/MGS MOLA MEGDR PDS products `MEGR90N000GB`, `MEGR90N180GB`, `MEGR00N000GB`, `MEGR00N180GB`; areoid `MEGA90N000EB`; Gale regional `MEGR00N090HB`. Product definitions: [MOLA MEGDR](https://pds-geosciences.wustl.edu/missions/mgs/megdr.html). The project stores radial metres separately from areoid-relative regional products and records preparation hashes in `planetary_map/assets/terrain/manifest.json`.
- **Regional terrain and orthophotos**: USGS Astrogeology STAC [HiRISE DTMs](https://stac.astrogeology.usgs.gov/docs/data/mars/hirise_dtms/) and [CTX DTMs](https://stac.astrogeology.usgs.gov/docs/data/mars/ctxdtms/). Bradbury uses `DTEEC_018854_1755_018920_1755_U01`; the requested `DTEEC_023957_1755_024023_1755_U01` was checked and has no valid touchdown pixel. HiRISE observation pages [ESP_018854_1755](https://www.uahirise.org/ESP_018854_1755) and [ESP_018920_1755](https://www.uahirise.org/ESP_018920_1755) provide the recorded 2010 acquisition dates.
- **Gale overview imagery**: NASA Mars Trek `Gale_CTX_BlockAdj_dd`, product UUID `22035911-cc4b-4e67-a9cd-a48b9fbb182c`; WMTS provenance and tile hashes are in `planetary_map/assets/terrain/gale_ctx_provenance.json` and `gale_ctx_wmts.xml`.
- **Terrain preparation runtime**: Rasterio/GDAL, NumPy and Pillow are bundled in the optional Windows worker. Their license texts, plus Python, PyInstaller and dependency notices, are retained in `planetary_map/tools/mars_terrain_worker/THIRD_PARTY_LICENSES/`.

- **Mars Viking MDIM 2.1 colorized mosaic**: NASA/JPL/USGS; delivered by [NASA Mars Trek](https://trek.nasa.gov/tiles/apidoc/trekAPI.html?body=mars). [WMTS capabilities](https://trek.nasa.gov/tiles/Mars/EQ/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0/WMTSCapabilities.xml). Assembled level-3 tiles into a 4096×2048 JPEG with mipmaps; no fictional terrain additions. Tile/output hashes are in planetary_map/assets/texture_provenance.json.
- Original source-comparison texture: [NASA Mars Image Texture](https://science.nasa.gov/3d-resources/mars/), NASA/Jet Propulsion Laboratory & Caltech, Viking images processed by USGS. Retained at native 1440×720; unused in the final globe.
- Landing coordinates: [Preliminary Assessment of the Mars Science Laboratory Entry, Descent and Landing](https://ntrs.nasa.gov/api/citations/20130011617/downloads/20130011617.pdf), NASA NTRS: Bradbury Landing -4.5895°, 137.4417°.
- Dates and mission context: [NASA Mars Science Laboratory fact sheet](https://mars.nasa.gov/internal_resources/824/). Landing 2012-08-06 UTC; launch 2011-11-26.
- Site name: [NASA/JPL Bradbury Landing announcement](https://www.jpl.nasa.gov/news/nasa-mars-rover-begins-driving-at-bradbury-landing/).
- Gale context and approximate landing-region focus: [Daybreak at Gale Crater](https://science.nasa.gov/resource/daybreak-at-gale-crater/).

No official traverse is bundled and no synthetic route is presented as NASA mission data. Interface graphics are project-created, using Godot's existing default font.

Regional imagery display alpha is derived with a 600 m coverage collar; source RGB and numeric elevations are unchanged. The tan atmospheric limb and procedural material variation are illustrative project effects, not measured atmospheric or elevation data.


## Cosmoscope architecture heritage

Data preparation, provider-boundary and cache principles are adapted from [Alfa5nm/CosmoScope_v2](https://github.com/Alfa5nm/CosmoScope_v2/tree/0f35ad4c56e6a8f727203f23b26bd8857d422a00), MIT, copyright 2025 NASA Space Apps Challenge - Cosmoscope Team. Its license is retained at third_party/COSMOSCOPE_LICENSE.txt. The implementation uses native Godot and the existing packaged worker; the browser rendering stack is not imported. [Review and integration details](docs/COSMOSCOPE_INTEGRATION.md).



## Local procedural terrain

Geographic mission patches reuse the MOLA, CTX, HiRISE and Viking products credited above. The generation graph, terrain and route shaders are project-created. Seeded rocks, material/friction settings and user-planned paths are explicitly procedural or authored gameplay content, not additional NASA observations.


Local driving patches use a narrower four-source-post blend with source validity masks, independently of the globe's 600 m display collar. Coarse surrounding scenery uses the same credited elevation products. Cosmetic dust shading and irregular seeded rock meshes with convex collision are project-created effects and are not additional geographic observations.


The detailed local surface's warm hue, grains, procedural normals, roughness/specular variation and gravel are illustrative project-created material effects, not additional NASA measurements. Terrain cavity shading is derived from the credited elevation products. SOURCE APPEARANCE disables cinematic surface styling while retaining measured geometry, derived cavity shading and sunlight. Adaptive meshes interpolate those same datasets and do not increase documented source resolution or accuracy.

The dramatic dusty appearance, analytical sand/rock normal-and-roughness maps, RGB atmospheric transport table, twilight aureole and drifting/wheel dust are project-created illustrative effects. They are not calibrated atmospheric observations, mapped soil types or additional measured relief. NASA/JPL sky-color references and the atmospheric/PBR/texture research informing the approximation are linked in [Dusty Mars](docs/DUSTY_MARS.md); no third-party paper implementation or texture pack is copied. The visual asset generator reproduces bundled maps without modifying geographic products.

Nearby gravel, drifting low dust banks and shared wheel-track height/compaction masks and dense visual terrain patches are project-created cosmetic effects. Tread shading and raised shoulders do not represent soil deformation measurements or physical terramechanics. Extended surrounding relief continues to use the credited geographic elevation products, without invented mountain geometry.


## Astronaut and science demonstration

Astronaut – EMU suit – Rigged by **Juan Ignacio Gil-Hutton**, [BlendSwap 12622](https://blendswap.com/blend/12622), [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/). Supplied original ZIP, Blender file and license are preserved under source/astronaut. Project modifications: clean export skeleton, removed cyclic/control constraints, repaired weights/toes/rigid accessories, PBR conversion, sculpt normal bake, mesh optimization/LODs and ten authored motion clips. Source appearance and artistic EMU identity are retained. This is not a NASA-certified Mars suit.

Rocknest and John Klein/Yellowknife Bay science area anchors use associated archived rover positions from the [PDS MSL PLACES localized interpolation table](https://planetarydata.jpl.nasa.gov/img/data/msl/msl_places/data_localizations/localized_interp.csv), [PLACES SIS](https://planetarydata.jpl.nasa.gov/img/data/msl/msl_places/document/PLACES_PDS_SIS.pdf), [NASA Rocknest first scoop](https://science.nasa.gov/photojournal/first-scoop-by-curiosity-sol-61-views/) and [NASA Curiosity first drilling](https://science.nasa.gov/photojournal/curiositys-first-sample-drilling/). Position precision and target-offset limits are documented in docs/ASTRONAUT_SCOUT.md. No historical traverse is synthesized.

Recording servo cue, demonstration routes, scout assessments, astronaut controller/IK, physical proxies and staging scenarios are project-created illustrative gameplay content.
