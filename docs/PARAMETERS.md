# Editable engineering source table

Edit `engineering_parameters.json` to change the simulation. This table is generated from that file. Documented, measured, derived, estimated and calibrated describe provenance, not certification.

| Parameter | Value | Units | Status | Source / interpretation |
|---|---|---|---|---|
| total_mass | 899 | kg | Documented | NASA landing press kit 2012 p.3.  |
| gravity | 3.71 | m/s^2 | Documented | JPL planetary physical parameters; research pack.  |
| wheel_radius | 0.25 | m | Derived | JPL Wheel Damage Table 1. Includes grousers. Smooth cylinder collision envelope. |
| wheel_width | 0.4 | m | Documented | JPL Wheel Damage Table 1.  |
| baseline_speed | 0.04 | m/s | Documented | NASA landing press kit 2012.  |
| chassis_mass | 699 | kg | Estimated | Mass budget. Includes locked arm, turret, mast, electronics and MMRTG. Residual after mobility bodies. |
| rocker_mass | 35 | kg each | Estimated | Provisional mass budget.  |
| bogie_mass | 20 | kg each | Estimated | Provisional mass budget.  |
| carrier_mass | 9 | kg each | Estimated | Provisional mass budget.  |
| wheel_mass | 9 | kg each | Estimated | Provisional mass budget. Not a NASA wheel mass measurement. |
| drive_torque | 80 | N m | Estimated | Provisional actuator model. Not flight actuator data; sensitivity 0.5x and 1.5x. |
| drive_kp | 48 | N m s/rad | Calibrated | Finite PI speed servo; settled and driven at 120/240 Hz. Numerical tuning, not flight controller gains. |
| drive_ki | 24 | N m/rad | Calibrated | Finite PI speed servo with clamp. Numerical tuning, not flight controller gains. |
| steering_torque | 200 | N m | Estimated | Provisional actuator model. Sized for rigid-cylinder static scrub; not flight data. |
| steering_rate | 0.25 | rad/s | Estimated | Provisional actuator model.  |
| steering_limit | 1.48 | rad | Estimated | Provisional actuator travel, +/-84.8 deg.  |
| steering_kp | 1200 | N m/rad | Estimated | Bounded steering servo.  |
| steering_kd | 60 | N m s/rad | Estimated | Bounded steering servo.  |
| differential_stiffness | 50000 | N m/rad | Estimated | Compliant ideal gear constraint. qL+qR approaches zero; finite compliance rather than an exact gear joint. |
| differential_damping | 500 | N m s/rad | Estimated | Numerical stabilization of differential.  |
| differential_torque | 3000 | N m | Estimated | Coupling safety clamp.  |
| acceleration | 0.025 | m/s^2 | Estimated | Player command ramp.  |
| yaw_acceleration | 0.02 | rad/s^2 | Estimated | Player command ramp.  |
| baseline_yaw_rate | 0.025 | rad/s | Estimated | Playable point-turn command.  |
| linear_damping | 0.015 | 1/s | Estimated | Numerical damping, not measured drag.  |
| angular_damping | 0.025 | 1/s | Estimated | Numerical damping, not measured joint friction.  |
| wheel_friction | 1.0 | dimensionless | Estimated | Jolt contact material; terrain chooses effective friction.  |
| rock_friction | 0.85 | dimensionless | Estimated | Hard-ground rigid contact.  |
| regolith_friction | 0.6 | dimensionless | Estimated | Rigid consolidated-ground approximation.  |
| sand_friction | 0.25 | dimensionless | Estimated | Low-friction rigid sand proxy. No sinkage, shear history, compaction or embedding; not terramechanics. |
| game_time_scale | 6.0 | sim seconds/wall second | Estimated | Time acceleration. Physics tick frequency multiplied with time scale to preserve dt. |
| physics_hz | 120 | Hz | Estimated | Fixed-step integration; convergence compared at 240 Hz.  |
| chassis_inertia | [170, 230, 180] | kg m^2 XYZ | Estimated | Lumped rectangular internal mass distribution. Applied in rover.gd. Not solid external mesh; sensitivity required. |
| rocker_inertia | [12, 14, 3] | kg m^2 XYZ | Estimated | Slender-link approximation.  |
| bogie_inertia | [4, 5, 1] | kg m^2 XYZ | Estimated | Slender-link approximation.  |
| carrier_inertia | [0.8, 0.4, 0.8] | kg m^2 XYZ | Estimated | Carrier lump.  |
| wheel_inertia | [0.56, 0.4, 0.4] | kg m^2 XYZ | Estimated | Thin-hoop axial inertia m*r^2; transverse includes width.  |
| rocker_limit | 0.7 | rad | Estimated | Provisional travel.  |
| bogie_limit | 0.8 | rad | Estimated | Provisional travel.  |
| chassis_collision_size | [1.36, 0.5, 1.85] | m XYZ | Estimated | Simplified body collision; asset-inspected envelope.  |
| steering_readiness | 0.12 | rad | Estimated | Drive fades to zero while steering error exceeds 6.9 degrees.  |
| floating_torque_fraction | 0.12 | dimensionless | Estimated | Unloaded wheel speed limiting.  |
| slip_denominator_floor | 0.01 | m/s | Estimated | Regularization near zero speed.  |
| rocker_collision_radius | 0.1 | m | Estimated | Simplified pivot collision sphere.  |
| bogie_collision_radius | 0.085 | m | Estimated | Simplified pivot collision sphere.  |
| carrier_collision_radius | 0.06 | m | Estimated | Simplified carrier collision sphere.  |
| origin_ChassisVisual | [0.0, 0.8572210073471069, 0.08899986371397972] | m XYZ Godot | Estimated | assets/geometry.json; NASA visual asset. Body/pivot origin; not flight CAD. Chassis origin approximates locked-equipment COM. |
| origin_Rocker_L | [0.7943623065948486, 0.8921189904212952, 0.3030000738799572] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Bogie_L | [0.7949371933937073, 0.6505584716796875, -0.45100367441773415] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Wheel_FL | [1.0586358308792114, 0.24761857092380524, 1.1815880499780178] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Carrier_FL | [1.0582431554794312, 0.6472190618515015, 1.1814974509179592] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Wheel_ML | [1.1888525485992432, 0.2505468428134918, 1.7508864402770996e-07] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Wheel_RL | [1.0581867694854736, 0.2504662275314331, -1.0737556256353855] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Carrier_RL | [1.0576996803283691, 0.6499555706977844, -1.0749999321997166] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Rocker_R | [-0.7991629838943481, 0.8921190500259399, 0.3030000142753124] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Bogie_R | [-0.7997376918792725, 0.6505584716796875, -0.451003972440958] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Wheel_FR | [-1.0628914833068848, 0.25035539269447327, 1.1839090548455715] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Carrier_FR | [-1.0624990463256836, 0.6499561071395874, 1.1840002499520779] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Wheel_MR | [-1.1936531066894531, 0.2505464255809784, -1.7508864402770996e-07] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Wheel_RR | [-1.0629870891571045, 0.250466525554657, -1.076244119554758] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
| origin_Carrier_RR | [-1.0625003576278687, 0.6499557495117188, -1.0750004090368748] | m XYZ Godot | Measured from the visual asset | assets/geometry.json; NASA visual asset. Wheel centers or existing mechanical pivot origins; axes not certified flight data. |
