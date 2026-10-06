# Engineering implementation and limits

## Baseline and asset

The 2012 landing press kit and JPL wheel-damage paper establish 899 kg, six driven wheels, four steering actuators, nominal 0.500 m outside wheel diameter including grousers, 0.400 m width, 19 chevron grousers and nominal 0.040 m/s hard-ground speed. Gravity is 3.71 m/s²; mass is never reduced to imitate Mars weight. These imply 3335.29 N weight and 0.160 rad/s / 1.528 rpm at the nominal radius before slip.

NASA's original file contains 106 objects and 48,638 triangles including helper meshes, with packed 1024-square textures and no physics constraints. It is already economical enough to retain. The exported asset has 73 mesh objects and 48,384 triangles. No indiscriminate decimation, replacement rover or added outer tread was used. UVs, hubs, flexures, odometry imagery, instruments, RTG, antennas and deck hardware are retained. Grouser appearance is inherited from NASA; the exact tread topology/count was not independently certified. Collision cylinders intentionally omit detailed grouser impacts and flexure compliance.

Legacy camera/pivot cube markers and a fake shadow plane were removed from the export. Missing duplicate texture references were redirected to the packed original. Wheels measured approximately 0.485294 m in radial bounding extent and 0.394729 m axially; only wheel meshes were adjusted to 0.500 x 0.400 m. This deliberate radial/axial correction is disclosed rather than scaling the whole rover to rounded envelope numbers. All 15 mechanical origins are in `assets/geometry.json`; export/reimport errors are measured separately. The resulting envelope is approximately 3.256 m long, 2.783 m wide and 2.220 m high, including the estimated folded arm and protrusions. This is not an assertion of flight manufacturing dimensions.

Blender uses +X left, -Y forward, +Z up in this asset. Godot uses +X left, +Y up, +Z forward. The navigation reference is shifted onto the middle-wheel axle line. For RNAV direction vectors from the PDS reference (+X forward, +Y right, +Z down), the directional mapping is Godot = (-RNAV Y, -RNAV Z, RNAV X); the visual asset's origins are not a SPICE calibration.

## Mechanical model

The model uses 15 dynamic bodies and 14 HingeJoint3D constraints: two rocker pivots, two bogie pivots, four steering joints and six wheel axes. All bodies are free to respond to gravity and contact. Chassis motion is not prescribed, and no force directly pushes the chassis to a commanded velocity. No automotive springs or raycast-car suspension is used. Simplified body spheres/box and wheel cylinders are separate from render meshes and explicit inertias. Adjacent bodies are excluded through joint collision exceptions; other simplified collision bodies can collide.

Mass budget: 699 kg chassis and locked equipment + 2 x 35 kg rockers + 2 x 20 kg bogies + 4 x 9 kg carriers + 6 x 9 kg wheels = 899 kg. Every allocation is provisional; total mass is documented. The arm, turret, mast, electronics, MMRTG and batteries are included in the chassis allocation. The chassis origin is an estimated COM. Inertias are diagonal plausible lumped distributions, not solid-metal render-mesh integrals. Sensitivity runs vary inertia, move 50 kg between chassis and rockers, and change torque/coupling parameters.

Jolt exposes hinges but no native three-body differential gear through Godot's node API. The implemented approximation is a compliant generalized gear constraint with q = qL + qR, potential energy 0.5*k*q², and damping c*qdot. Each rocker receives -k*q-c*qdot about the chassis lateral axis; the chassis receives the opposite sum. Torque is capped. This enforces the chassis pitch approximately as the mean absolute rocker pitch while transmitting reaction torque. It is not a visual animation or a terrain-height pose adjustment. Residual compliance is reported; an otherwise identical disabled-coupling fixture is recorded to demonstrate the effect.

Drive uses bounded PI torque control with a bounded integral and opposing torque on the parent. Steering uses a rate-limited reference and bounded PD torque with hard hinge travel limits. The 80 Nm drive and 200 Nm steering caps are **estimates**, not flight motor specifications. Steering torque was increased during calibration because rigid cylinders resist static steering scrub. Changing these estimates changes climbing/stall behavior. Locked wheels do not have an infinitely strong velocity motor.

## Kinematics, contact and timing

For Godot local wheel position (left=x, forward=z), commanded hub velocity is (Omega*z, 0, v-Omega*x). The reference follows the current midpoint of the middle-wheel centers. Their steering angle is always zero. Corner wheels use atan2(left speed, forward speed), choosing an equivalent angle within +/-90 degrees with signed wheel rotation. Targets are further constrained by the estimated +/-84.8-degree steering travel. Rates are projected onto the contact tangent using the parent wheel axis and measured contact normal. Steering readiness gates drive; substantial torque is delayed until corners have aligned. This is an articulated geometric approximation, not JPL's flight traction-control algorithm. Arbitrary articulation can move the middle-wheel contact points off the ideal common axle and cause scrub.

Jolt solves hard-ground normal contact and friction, including contact loss and finite longitudinal/lateral traction. Wide rigid cylinders cause scrub during point turns; yaw-rate accuracy is weaker than straight-driving accuracy. Slip ratios use a 0.01 m/s denominator floor and should not be interpreted as reliable percentages near rest. A reduced torque cap is used on airborne wheels. Wheel-center tangent speeds omit some finite contact-patch and flexure effects.

The fixed engineering step is 1/120 s. Explore uses time_scale=6 and 720 physics ticks per wall second, keeping dt=1/120 simulation seconds. Controls and camera have separate smoothing; the camera uses wall time and world-up, not every chassis vibration. On an overloaded computer, the physics step cap can make accelerated time advance more slowly than requested. No higher physical cruising speed is enabled.

## Telemetry limitation

Godot 4.6's built-in Jolt contact listener uses JPH::EstimateCollisionResponse, rather than exposing the fully solved articulated contact impulses. Its reported values can approximate only a wheel's own gravitational load in this setup. `jolt_contact_proxy_n` is retained as diagnostic data and **must not be read as a true wheel load**. The overlay's total support is inferred from total assembly vertical momentum change, gravity and numerical linear damping. Static agreement with 3335.29 N checks whole-assembly equilibrium; it does not validate load allocation among wheels. Accurate individual loads require backend instrumentation or a solver exposing joint/contact reactions. This requirement remains unverified.

## Arm, mast and source reconciliation

The arm paper Table 2 gives 2.2 m from arm base to turret center, 67 kg without turret instruments, and 24 kg turret instruments. The 2012 press kit gives rounded 2.1 m arm length, 1.9 m forward turret-center extension from the front body, and a 33 kg assembled turret. NASA summaries sometimes use approximately 30 kg. These describe different reference points or component inclusions; do not assign 2.2 m to one link, or add 67+24+33 kg. A 91 kg complete-arm interpretation is plausible from Table 2 but remains a bookkeeping interpretation, contained within the 699 kg lump. No separately physical turret was added.

The source arm started deployed. The adaptation folds it across the front by rotating its original link hierarchy; exact stow encoder angles and latch geometry are unavailable. Therefore this is an **estimated stowed visual pose**, not a verified flight pose. Five nested arm frames and nested mast pan/tilt frames remain editable. Runtime arm deployment is intentionally disabled because link collision, moving COM and safe swept-volume verification are incomplete. The driving body collision does not resolve every arm, mast, antenna and harness detail. There is no claim that the locked pose clears every arbitrary obstacle. The V camera is illustrative and does not reproduce calibrated Mastcam, Navcam or Hazcam optics. No chemistry/radiation outputs or flight instrument effects are fabricated.

## Soil and structural behavior

Rock, consolidated regolith and sand-proxy pads use separate editable friction estimates. The sand proxy is rigid and low-friction, with **no sinkage**, pressure-sinkage relationship, shear-displacement memory, compaction, terrain history or progressive embedding. Its slide on a 20-degree fixture demonstrates traction loss, not Mars soil validation. No wheel puncture, fracture or structural damage simulation is included.

Chrono SCM could provide deformable-soil simulation and offline reference comparisons, but adds a C++/native coupling boundary, model synchronization and calibrated Bekker/Janosi/Mohr inputs that this pack does not establish. It was not added as an unvalidated dependency. A future offline drawbar-pull and sinkage study with measured analog soil is preferable before presenting quantitative loose-soil results.

## Camera and presentation

Third-person follow smooths the focus on wall time, uses world-up on slopes, supports mouse/gamepad orbit and zoom, and sweeps a small sphere against terrain and rover collision bodies. The minimum orbit radius keeps it outside the normal rover envelope. The normal HUD is separate from the optional engineering telemetry. Reference renders and runtime screenshots are actual renderer output, not conceptual mockups.

See `VALIDATION.md` for observed tests and remaining acceptance gaps. Engine-level convergence does not validate uncertain real-world parameters.
