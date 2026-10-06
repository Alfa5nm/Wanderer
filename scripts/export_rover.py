"""Reproducible NASA adaptation. Run Blender -b ORIGINAL --python this_file.
Preserves source, mesh topology and UVs. No flight CAD or actuator data implied.
"""
import bpy, json, math, pathlib, hashlib
from mathutils import Vector, Matrix
ROOT=pathlib.Path(__file__).resolve().parents[1]
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1.0
source=pathlib.Path(bpy.data.filepath)
source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.context.view_layer.update()
# Preserve world geometry before replacing the legacy helper/mesh hierarchy.
world={o.name:o.matrix_world.copy() for o in bpy.data.objects}
parents={o.name:o.parent.name if o.parent else None for o in bpy.data.objects}
for o in bpy.data.objects:
    o.animation_data_clear()
    for constraint in list(o.constraints): o.constraints.remove(constraint)
def descendants(name):
    return [o for o in bpy.data.objects if o.name==name or name in lineage(o.name)]
def lineage(name):
    chain=[]
    while parents.get(name):
        name=parents[name]; chain.append(name)
    return chain
# Pose adaptation: folded in front of body. These deltas are estimates, not flight encoder angles.
def rotate_tree(name,axis,angle):
    pivot=world[name].translation.copy()
    t=Matrix.Translation(pivot)@Matrix.Rotation(math.radians(angle),4,axis)@Matrix.Translation(-pivot)
    for o in descendants(name): world[o.name]=t@world[o.name]
rotate_tree('arm_02.001','Z',-90)
rotate_tree('arm_03.001','Y',105)
# Global coordinates: Blender X=left, -Y=forward, Z=up. Ground at wheel bottom.
lift=0.25-sum(world[f'wheel_0{i}_{s}'].translation.z for s in ['L','R'] for i in [1,2,3])/6
offset=Vector((0,0,lift))
middle_y=sum(world[f'wheel_02_{s}'].translation.y for s in ['L','R'])/2
def convert(v): return [v.x,v.z,-v.y+middle_y]
group_positions={'ChassisVisual':Vector((0,0,0.85))+offset}
wheel_ids={}
for s in ['L','R']:
    group_positions['Rocker_'+s]=world['suspension_arm_B_'+s+'_p'].translation+offset
    group_positions['Bogie_'+s]=world['suspension_arm_B2_'+s].translation+offset
    for i,loc in [(1,'F'),(2,'M'),(3,'R')]:
        wid=loc+s; name=f'wheel_0{i}_{s}'; wheel_ids[name]=wid
        group_positions['Wheel_'+wid]=world[name].translation+offset
        if i!=2:
            group_positions['Carrier_'+wid]=world[f'suspension_steer_{"F" if i==1 else "B"}_{s}'].translation+offset
groups={}
for name,p in group_positions.items():
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o); o.location=p; groups[name]=o
def group_for(name):
    if name in wheel_ids: return 'Wheel_'+wheel_ids[name]
    if name.startswith('suspension_steer_'):
        return 'Carrier_'+('F' if '_F_' in name else 'R')+name[-1]
    if name.startswith('suspension_arm_B2_'): return 'Bogie_'+name[-1]
    if name.startswith(('suspension_arm_','suspension_axel_','suspension_rod_')):
        return 'Rocker_'+('L' if name.endswith(('L','L2')) else 'R')
    return 'ChassisVisual'
kept=[]; removed=[]
for o in list(bpy.data.objects):
    if o.name in groups: continue
    camera_markers=['HazCam_F','HazCam_rear_L','HazCam_rear_R','MAHLI_cam','MARDI','MastCam_L','MastCam_R','NavCam_top_L','NavCam_top_R']
    if o.type!='MESH' or o.name in camera_markers or any(m and m.name in ['pivot','shadow2'] for m in o.data.materials) or o.name.endswith('_p') or o.name.startswith('Cube_'):
        removed.append(o.name); bpy.data.objects.remove(o,do_unlink=True); continue
    name=o.name; mat=world[name].copy(); mat.translation+=offset
    # Radial diameter exactly .500m including the existing tread; width .400m.
    if name in wheel_ids:
        c=mat.translation.copy()
        radial=0.5/0.4852944314479828; axial=0.4/0.39472949504852295
        mat=Matrix.Translation(c)@Matrix.Diagonal((axial,radial,radial,1))@Matrix.Translation(-c)@mat
    group=group_for(name); p=group_positions[group]
    o.data=o.data.copy(); o.data.transform(Matrix.Translation(-p)@mat)
    o.parent=groups[group]; o.matrix_parent_inverse=Matrix.Identity(4); o.matrix_basis=Matrix.Identity(4)
    o.hide_render=False; o.hide_viewport=False; o.hide_set(False)
    kept.append(o)
# Keep repaired textures embedded and use a predictable glTF PBR conversion.
for m in bpy.data.materials:
    if not m.use_nodes: continue
    for n in m.node_tree.nodes:
        if n.type=='TEX_IMAGE' and n.image and n.image.size[0]==0:
            replacement=bpy.data.images.get(n.image.name.split('.png')[0]+'.png')
            if replacement and replacement.size[0]>0: n.image=replacement
    for n in m.node_tree.nodes:
        if n.type=='BSDF_PRINCIPLED':
            n.inputs['Roughness'].default_value=0.7
for im in list(bpy.data.images):
    if im.size[0]==0: bpy.data.images.remove(im)
# Arm and mast joint frames are editable, but the driving model locks them to chassis.
frames={}
for name,key in [('ArmShoulderAzimuth','arm_01.001'),('ArmShoulderElevation','arm_02.001'),('ArmElbow','arm_03.001'),('ArmWrist','arm_04.001'),('ArmTurret','arm_05_head.001'),('MastPan','mast_02.001'),('MastTilt','mast_03.001')]:
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o)
    o.parent=groups['ChassisVisual']; o.location=world[key].translation+offset-group_positions['ChassisVisual']; o.empty_display_type='ARROWS'; o.empty_display_size=.1
    o['status']='Measured asset origin; axis/limits require validation before dynamic deployment'
    frames[key]=o
bpy.context.view_layer.update()
for key,frame in frames.items():
    parent_frame=next((frames[n] for n in lineage(key) if n in frames),None)
    if parent_frame:
        mat=frame.matrix_world.copy(); frame.parent=parent_frame; frame.matrix_world=mat
bpy.context.view_layer.update()
for o in kept:
    frame_key=next((n for n in [o.name]+lineage(o.name) if n in frames),None)
    if frame_key:
        mat=o.matrix_world.copy(); o.parent=frames[frame_key]; o.matrix_world=mat
bpy.context.view_layer.update()
for o in bpy.context.selected_objects: o.select_set(False)
for o in list(kept)+list(groups.values()): o.select_set(True)
for o in bpy.data.objects:
    if o.type=='EMPTY': o.select_set(True)
# Shift reference to middle-wheel axle, so point turns satisfy fixed-wheel kinematics.
for g in groups.values(): g.location.y-=middle_y
bpy.context.view_layer.update()
scene.render.image_settings.file_format='PNG'
scene.render.engine='CYCLES'
scene.cycles.samples=16
report={'source_sha256':source_hash,'source_file':str(source),'export_blender':bpy.app.version_string,'coordinate_mapping':'Godot (X,Y,Z)=(Blender X,Blender Z,-Blender Y + original middle_y); +Z forward, +X left','status':'Visual asset measurements, not flight CAD','wheel_radius_m':.25,'wheel_width_m':.4,'global_scale':1,'ground_lift_m':lift,'arm_pose':'Estimated folded stow; shoulder tree -90deg Z, elbow tree +105deg Y; no flight encoder claim','removed_helper_objects':removed,'groups':{n:convert(p) for n,p in group_positions.items()},'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in kept),'mesh_count':len(kept),'material_count':len(set(m.name for o in kept for m in o.data.materials if m))}
corners=[o.matrix_world@v.co for o in kept for v in o.data.vertices]
report['envelope_m']=[max(v[i] for v in corners)-min(v[i] for v in corners) for i in range(3)]
(ROOT/'assets'/'geometry.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/'Curiosity_Adapted.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets'/'curiosity.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_cameras=False,export_lights=False,export_extras=True)
print('EXPORT_AUDIT',json.dumps(report))
