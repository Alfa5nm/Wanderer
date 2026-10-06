# Runtime validation

Generated from local runtime measurements on 2026-10-02. Godot 4.6.1 stable, Jolt, Windows. Engineering cases use 3.71 m/s² and 1x simulation time with 120 Hz unless explicitly identified otherwise.

**24/25 scoped software acceptance checks passed.** These tolerances qualify this prototype and its declared approximations, not flight hardware or Mars soil behavior.

| Check | Result | Measurement | Acceptance criterion |
|---|---|---|---|
| Export and wheel dimensions | PASS | 73 meshes; 48384 triangles | Origins within 0.01 mm; diameter/width within 1 mm of 0.500/0.400 m |
| Mass conservation | PASS | 899 kg in every case, including redistribution | 0.001 kg bookkeeping tolerance |
| Level settling | PASS | Mean forward drift -0.000716 m/s | Below 0.002 m/s over last 5 s; numerical creep criterion |
| Whole-assembly static support | PASS | 3335.29 N inferred from momentum | Within 2% of 3335.29 N; does NOT validate individual contact loads |
| Baseline straight speed | PASS | 0.039782 m/s | Within 5% of 0.040 m/s |
| Straight distance | PASS | 1.1635 m in 30 s | Within 0.03 m of 1.168 m; includes 1.6 s acceleration ramp |
| Straight heading | PASS | -0.0116 degrees | Below 0.5 degree drift |
| Wheel rotation | PASS | 0.15979 rad/s (1.526 rpm) | Within 5% of 0.160 rad/s; effective-radius/contact approximation |
| Reverse | PASS | -0.039956 m/s | Within 5% of -0.040 m/s |
| Point turn | PASS | Yaw 99.80 deg; middle-axle center drift 0.0103 m | 20% yaw envelope including alignment and wide-cylinder scrub; center drift <0.1 m |
| Corner alignment | PASS | [-47.88, 0.0, 45.2, 48.18, 0.0, -45.62] | Actual corner angles within 5 deg of targets; middles fixed at zero |
| Arc geometry | PASS | Chord-derived radius 4.137 m; yaw 35.05 deg | Within 15% of ideal 4 m radius; finite steering settling and scrub included |
| Differential constraint | PASS | Residual on 0.314 deg / off 65.770 deg; pitch on -3.30 / off -36.19 deg | On residual <0.5 deg; disabled control >10 deg establishes mechanical influence |
| 100 mm traversal | PASS | Final chassis z 4.381 m; minimum 6 contacting wheels | All wheel centers clear the 0.65 m long obstacle by finish; recovered roll <5 deg |
| Wheel contact loss | PASS | Minimum 4 contacting wheels after ground drops 0.4 m under front pair | Front wheels lose support; articulated chassis remains finite and upright |
| uphill_10 | PASS | 0.03974 m/s; roll 0.03 deg | Within 10% commanded speed at end, no rollover; not an operational slope rating |
| downhill_10 | PASS | 0.03970 m/s; roll 0.03 deg | Within 10% commanded speed at end, no rollover; not an operational slope rating |
| cross_slope_10 | PASS | 0.03978 m/s; roll -9.97 deg | Within 10% commanded speed at end, no rollover; not an operational slope rating |
| uphill_25 | PASS | 0.03944 m/s; roll 0.05 deg | Within 10% commanded speed at end, no rollover; not an operational slope rating |
| Torque-limited wall stall | PASS | Peak 80.00 Nm; final mean speed -0.000006 m/s | Saturates at 80 Nm; no forward penetration/drive-through |
| Low-friction traction loss | PASS | Downslope -3.386 m/s; pitch -20.26 deg | Must slide rather than climb while remaining on the large test plane; no soil validation claimed |
| Timestep convergence | PASS | 120 vs 240 Hz speed difference 0.002% | Below 2% for straight case; does not establish all-contact convergence |
| Solver convergence | PASS | 20/8 vs 40/16 iterations speed difference 0.160% | Fresh process with verified configuration; below 2% straight-speed change |
| Input and camera | PASS | 15 synthetic/runtime checks passed | Keyboard, synthetic gamepad, orbit, zoom, reset, POV, recovery, overlay, time dt and camera obstruction |
| Original NASA file preserved | FAIL | e6e808d2d1d4f9191d86c006f7c3ef58cebc5180fab088786cf9f27ecf05b3bc | SHA-256 exactly matches original inspection |

## Recorded cases

The table includes observed adverse outcomes; a sand slide or torque-limited stall is not relabeled as successful traversal. Speed is the mean over the last five simulation seconds. Peak torque is the largest absolute drive torque sampled over the run.

| Case | Forward m/s | Heading deg | Pitch deg | Roll deg | Peak drive Nm |
|---|---:|---:|---:|---:|---:|
| settling | -0.00072 | -0.012 | -0.222 | 0.031 | 25.13 |
| straight_120Hz | 0.03978 | -0.012 | -0.222 | 0.031 | 1.00 |
| straight_240Hz | 0.03978 | 0.005 | -0.212 | 0.031 | 1.06 |
| reverse | -0.03996 | -0.012 | -0.222 | 0.031 | 1.01 |
| point_turn | -0.00030 | 99.796 | -0.206 | 0.015 | 28.45 |
| arc_turn | 0.04096 | 35.052 | -0.233 | 0.093 | 14.28 |
| obstacle_100mm | 0.03973 | -0.590 | -0.209 | 0.029 | 49.09 |
| articulation_on_block | 0.00029 | 0.097 | -3.296 | 2.097 | 13.15 |
| differential_disabled_control | 0.00000 | -1.410 | -36.192 | 2.294 | 30.15 |
| uphill_10 | 0.03974 | -0.018 | -10.220 | 0.034 | 25.29 |
| downhill_10 | 0.03970 | -0.005 | 9.778 | 0.030 | 24.45 |
| cross_slope_10 | 0.03978 | 0.051 | -0.212 | -9.971 | 1.12 |
| uphill_25 | 0.03944 | -0.039 | -25.202 | 0.047 | 61.35 |
| sand_proxy_20deg | -3.38618 | -0.186 | -20.262 | 0.092 | 39.32 |
| trapped_wheel_stall | -0.00001 | -0.020 | -0.209 | 0.037 | 80.00 |
| torque_sensitivity_0.5 | 0.03976 | -0.018 | -10.221 | 0.034 | 25.34 |
| torque_sensitivity_1.5 | 0.03976 | -0.018 | -10.221 | 0.034 | 25.34 |
| differential_sensitivity_0.5 | 0.00043 | 0.081 | -3.463 | 2.108 | 23.46 |
| differential_sensitivity_2.0 | 0.00045 | 0.105 | -3.214 | 2.096 | 14.70 |
| inertia_sensitivity_0.5 | 0.03982 | 0.010 | -0.213 | 0.042 | 1.34 |
| inertia_sensitivity_2.0 | 0.03981 | -0.004 | -0.216 | 0.031 | 1.10 |
| mass_distribution_-50 | 0.03981 | -0.012 | -0.209 | 0.031 | 1.22 |
| mass_distribution_50 | 0.03982 | -0.012 | -0.240 | 0.032 | 1.19 |
| front_contact_loss | 0.03754 | 0.000 | 14.425 | 0.030 | 80.00 |

## Performance and artifacts

The graphical capture measured 144 FPS, 492 scene draw calls and 144182 rendered primitives, including scenery and shadow passes, on NVIDIA GeForce GTX 1650. The measured physics-process monitor was 0.746 ms. This is a short local capture, not a cross-hardware sustained benchmark. The source rover itself is 48,384 triangles; no LOD/decimation was justified by this measurement.

Raw data: `evidence/validation.json`, `physics_trace.jsonl`, `solver_validation.json`, `solver_trace.jsonl`, `controls_validation.json`, `reimport_audit.json`, `source_integrity.json`, `performance.json`. Logs retain the engine output. Screenshots: `runtime.png`, `runtime_engineering.png`. Ten reference renders are under `reference_views/`.

## Remaining acceptance gaps

- Per-wheel reaction forces and wheel-load distribution are unverified because the built-in Jolt reporting API uses collision-response estimates. Total support is an inverse-dynamics inference, not an independently instrumented contact-force sum.
- The folded arm is estimated. A documented flight stow-angle match, safe dynamic deployment, moving COM, swept collisions and turret orientation tests are not complete; deployment is disabled.
- Exact flight pivot coordinates, component inertias, actuator torque curves, backlash and friction remain unknown. Source mesh origins and explicit estimates are used.
- Point turns retain significant finite-width cylinder scrub and yaw error. Arc steering has finite static error. Do not infer precision autonomous navigation performance.
- Wheel grouser count/topology is inherited visually, not independently certified; no compliance or structural damage is simulated.
- Loose soil is a rigid low-friction proxy. There are no sinkage/embedding, shear-history or drawbar-pull validation results.
- Physical gamepad hardware was unavailable. Axis/button logic was checked using synthetic Godot inputs with a test device override.
- Convergence is checked on straight driving; high-contact-count impacts, every obstacle profile and extreme terrain are not exhaustively converged. The 200 mm fixture is provided for exploration, not a validated obstacle capability claim.
- Collision meshes are simplified and omit detailed locked equipment. NASA mesh/material compatibility is verified by reimport and viewing, not a pixel-identical renderer comparison.

Parameter sensitivity results are included above. The tested ranges do not bound real flight uncertainty. Read `ENGINEERING.md` and `CREDITS.md` with this report.
