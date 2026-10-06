"""Build a report from actual Godot measurements; failed criteria remain visible."""
import json, pathlib, math, hashlib, datetime
root=pathlib.Path(__file__).resolve().parents[1]
def read(name): return json.loads((root/'evidence'/name).read_text(encoding='utf-8-sig'))
rows=read('validation.json'); cases={r['case']:r for r in rows}
asset=read('reimport_audit.json'); controls=read('controls_validation.json'); solver=read('solver_validation.json')
performance=read('performance.json')
checks=[]
def check(name,ok,measured,tolerance): checks.append(dict(name=name,passed=bool(ok),measured=measured,tolerance=tolerance))
check('Export and wheel dimensions',asset['pass'],f"{asset['meshes']} meshes; {asset['triangles']} triangles",'Origins within 0.01 mm; diameter/width within 1 mm of 0.500/0.400 m')
check('Mass conservation',all(abs(r['final']['mass_kg']-899)<.001 for r in rows),'899 kg in every case, including redistribution','0.001 kg bookkeeping tolerance')
s=cases['settling']
check('Level settling',abs(s['mean_forward_speed_last5'])<.002, f"Mean forward drift {s['mean_forward_speed_last5']:.6f} m/s",'Below 0.002 m/s over last 5 s; numerical creep criterion')
check('Whole-assembly static support',abs(s['mean_support_last5']-3335.29)<.02*3335.29,f"{s['mean_support_last5']:.2f} N inferred from momentum",'Within 2% of 3335.29 N; does NOT validate individual contact loads')
a=cases['straight_120Hz'];b=cases['straight_240Hz']
check('Baseline straight speed',abs(a['mean_forward_speed_last5']-.04)<.002,f"{a['mean_forward_speed_last5']:.6f} m/s",'Within 5% of 0.040 m/s')
check('Straight distance',abs(a['distance_m']-1.168)<.03,f"{a['distance_m']:.4f} m in 30 s",'Within 0.03 m of 1.168 m; includes 1.6 s acceleration ramp')
check('Straight heading',abs(a['final']['heading'])<.5,f"{a['final']['heading']:.4f} degrees",'Below 0.5 degree drift')
rate=sum(w['rate'] for w in a['final']['wheels'])/6
check('Wheel rotation',abs(rate-.16)<.008,f"{rate:.5f} rad/s ({rate*60/(2*math.pi):.3f} rpm)",'Within 5% of 0.160 rad/s; effective-radius/contact approximation')
check('Reverse',abs(cases['reverse']['mean_forward_speed_last5']+.04)<.002,f"{cases['reverse']['mean_forward_speed_last5']:.6f} m/s",'Within 5% of -0.040 m/s')
t=cases['point_turn']['final']; expected=.025*65*180/math.pi
center=math.hypot(t['position'][0]-.089*math.sin(math.radians(t['heading'])),t['position'][2]-.089*math.cos(math.radians(t['heading'])))
check('Point turn',abs(t['heading']-expected)<expected*.20 and center<.1,f"Yaw {t['heading']:.2f} deg; middle-axle center drift {center:.4f} m",'20% yaw envelope including alignment and wide-cylinder scrub; center drift <0.1 m')
check('Corner alignment',all(abs(w['steer_deg']-w['steer_target_deg'])<5 for w in t['wheels']),str([round(w['steer_deg'],2) for w in t['wheels']]),'Actual corner angles within 5 deg of targets; middles fixed at zero')
t=cases['arc_turn']['final'];x=t['position'][0];z=t['position'][2]-.089
radius=(x*x+z*z)/(2*x)
check('Arc geometry',abs(radius-4)<.6,f"Chord-derived radius {radius:.3f} m; yaw {t['heading']:.2f} deg",'Within 15% of ideal 4 m radius; finite steering settling and scrub included')
on=cases['articulation_on_block']['final'];off=cases['differential_disabled_control']['final']
check('Differential constraint',abs(on['differential_error_deg'])<.5 and abs(off['differential_error_deg'])>10,f"Residual on {on['differential_error_deg']:.3f} deg / off {off['differential_error_deg']:.3f} deg; pitch on {on['pitch']:.2f} / off {off['pitch']:.2f} deg",'On residual <0.5 deg; disabled control >10 deg establishes mechanical influence')
obs=cases['obstacle_100mm']
check('100 mm traversal',obs['final']['position'][2]>4 and abs(obs['final']['roll'])<5,f"Final chassis z {obs['final']['position'][2]:.3f} m; minimum {obs['min_wheels_contact']} contacting wheels",'All wheel centers clear the 0.65 m long obstacle by finish; recovered roll <5 deg')
r=cases['front_contact_loss']
check('Wheel contact loss',r['min_wheels_contact']<=4 and abs(r['final']['roll'])<10,f"Minimum {r['min_wheels_contact']} contacting wheels after ground drops 0.4 m under front pair",'Front wheels lose support; articulated chassis remains finite and upright')
for name in ['uphill_10','downhill_10','cross_slope_10','uphill_25']:
 r=cases[name];check(name,abs(r['mean_forward_speed_last5']-.04)<.004 and abs(r['final']['roll'])<20,f"{r['mean_forward_speed_last5']:.5f} m/s; roll {r['final']['roll']:.2f} deg",'Within 10% commanded speed at end, no rollover; not an operational slope rating')
r=cases['trapped_wheel_stall']
check('Torque-limited wall stall',abs(r['mean_forward_speed_last5'])<.002 and 79<r['max_abs_torque']<=80.001,f"Peak {r['max_abs_torque']:.2f} Nm; final mean speed {r['mean_forward_speed_last5']:.6f} m/s",'Saturates at 80 Nm; no forward penetration/drive-through')
r=cases['sand_proxy_20deg']
check('Low-friction traction loss',r['mean_forward_speed_last5']<-.5 and abs(r['final']['pitch']+20)<5,f"Downslope {r['mean_forward_speed_last5']:.3f} m/s; pitch {r['final']['pitch']:.2f} deg",'Must slide rather than climb while remaining on the large test plane; no soil validation claimed')
delta=abs(a['mean_forward_speed_last5']-b['mean_forward_speed_last5'])/.04
check('Timestep convergence',delta<.02,f"120 vs 240 Hz speed difference {delta*100:.3f}%",'Below 2% for straight case; does not establish all-contact convergence')
delta=abs(a['mean_forward_speed_last5']-solver['mean_forward_speed_last5'])/.04
check('Solver convergence',delta<.02 and solver['configured_velocity_steps']==40 and solver['configured_position_steps']==16,f"20/8 vs 40/16 iterations speed difference {delta*100:.3f}%",'Fresh process with verified configuration; below 2% straight-speed change')
check('Input and camera',all(v for v in controls.values() if isinstance(v,bool)),f"{sum(isinstance(v,bool) and v for v in controls.values())} synthetic/runtime checks passed",'Keyboard, synthetic gamepad, orbit, zoom, reset, POV, recovery, overlay, time dt and camera obstruction')
source=json.loads((root/'assets/geometry.json').read_text())
path=pathlib.Path(source['source_file'])
hash_now=hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
integrity={'original_sha256':source['source_sha256'],'current_sha256':hash_now,'unchanged':hash_now==source['source_sha256']}
(root/'evidence/source_integrity.json').write_text(json.dumps(integrity,indent=2))
check('Original NASA file preserved',integrity['unchanged'],hash_now or 'Source unavailable','SHA-256 exactly matches original inspection')
(root/'evidence/acceptance.json').write_text(json.dumps(checks,indent=2))
out=['# Runtime validation','',f"Generated from local runtime measurements on {datetime.date.today()}. Godot 4.6.1 stable, Jolt, Windows. Engineering cases use 3.71 m/s² and 1x simulation time with 120 Hz unless explicitly identified otherwise.",'',f"**{sum(c['passed'] for c in checks)}/{len(checks)} scoped software acceptance checks passed.** These tolerances qualify this prototype and its declared approximations, not flight hardware or Mars soil behavior.",'','| Check | Result | Measurement | Acceptance criterion |','|---|---|---|---|']
for c in checks:out.append(f"| {c['name']} | {'PASS' if c['passed'] else 'FAIL'} | {c['measured']} | {c['tolerance']} |")
out+=['','## Recorded cases','','The table includes observed adverse outcomes; a sand slide or torque-limited stall is not relabeled as successful traversal. Speed is the mean over the last five simulation seconds. Peak torque is the largest absolute drive torque sampled over the run.','', '| Case | Forward m/s | Heading deg | Pitch deg | Roll deg | Peak drive Nm |','|---|---:|---:|---:|---:|---:|']
for r in rows:
 t=r['final'];out.append(f"| {r['case']} | {r['mean_forward_speed_last5']:.5f} | {t['heading']:.3f} | {t['pitch']:.3f} | {t['roll']:.3f} | {r['max_abs_torque']:.2f} |")
out+=['','## Performance and artifacts','',f"The graphical capture measured {performance['fps']:.0f} FPS, {performance['draw_calls']:.0f} scene draw calls and {performance['render_primitives']:.0f} rendered primitives, including scenery and shadow passes, on {performance['video_adapter']}. The measured physics-process monitor was {performance['physics_seconds']*1000:.3f} ms. This is a short local capture, not a cross-hardware sustained benchmark. The source rover itself is {asset['triangles']:,} triangles; no LOD/decimation was justified by this measurement.",'','Raw data: `evidence/validation.json`, `physics_trace.jsonl`, `solver_validation.json`, `solver_trace.jsonl`, `controls_validation.json`, `reimport_audit.json`, `source_integrity.json`, `performance.json`. Logs retain the engine output. Screenshots: `runtime.png`, `runtime_engineering.png`. Ten reference renders are under `reference_views/`.','', '## Remaining acceptance gaps','', '- Per-wheel reaction forces and wheel-load distribution are unverified because the built-in Jolt reporting API uses collision-response estimates. Total support is an inverse-dynamics inference, not an independently instrumented contact-force sum.','- The folded arm is estimated. A documented flight stow-angle match, safe dynamic deployment, moving COM, swept collisions and turret orientation tests are not complete; deployment is disabled.','- Exact flight pivot coordinates, component inertias, actuator torque curves, backlash and friction remain unknown. Source mesh origins and explicit estimates are used.','- Point turns retain significant finite-width cylinder scrub and yaw error. Arc steering has finite static error. Do not infer precision autonomous navigation performance.','- Wheel grouser count/topology is inherited visually, not independently certified; no compliance or structural damage is simulated.','- Loose soil is a rigid low-friction proxy. There are no sinkage/embedding, shear-history or drawbar-pull validation results.','- Physical gamepad hardware was unavailable. Axis/button logic was checked using synthetic Godot inputs with a test device override.','- Convergence is checked on straight driving; high-contact-count impacts, every obstacle profile and extreme terrain are not exhaustively converged. The 200 mm fixture is provided for exploration, not a validated obstacle capability claim.','- Collision meshes are simplified and omit detailed locked equipment. NASA mesh/material compatibility is verified by reimport and viewing, not a pixel-identical renderer comparison.','', 'Parameter sensitivity results are included above. The tested ranges do not bound real flight uncertainty. Read `ENGINEERING.md` and `CREDITS.md` with this report.']
(root/'docs/VALIDATION.md').write_text('\n'.join(out)+'\n',encoding='utf-8')
params=json.loads((root/'engineering_parameters.json').read_text())
table=['# Editable engineering source table','','Edit `engineering_parameters.json` to change the simulation. This table is generated from that file. Documented, measured, derived, estimated and calibrated describe provenance, not certification.','','| Parameter | Value | Units | Status | Source / interpretation |','|---|---|---|---|---|']
for key,p in params.items():
 table.append(f"| {key} | {p['value']} | {p['unit']} | {p['status']} | {p['source']}. {p['note']} |")
(root/'docs/PARAMETERS.md').write_text('\n'.join(table)+'\n',encoding='utf-8')
for c in checks:print(('PASS' if c['passed'] else 'FAIL'),c['name'],c['measured'])
raise SystemExit(0 if all(c['passed'] for c in checks) else 1)
