"""Blender --background --disable-autoexec source/astronaut/Astronauta.blend --python this_file.
CC-BY 3.0 Juan Ignacio Gil-Hutton adaptation; never modifies the original.
"""
import bpy, math, json, pathlib
from mathutils import Vector, Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/astronaut'; OUT.mkdir(exist_ok=True)
if 'metarig' not in bpy.data.objects:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/astronaut/Astronauta.blend'),load_ui=False,use_scripts=False)
source=bpy.data.objects['metarig']; source.data.pose_position='REST'
for bone in source.pose.bones:
    for constraint in list(bone.constraints): bone.constraints.remove(constraint)
custom={b.custom_shape for b in source.pose.bones if b.custom_shape}
alias={'Bone':'root','Bone.001':'chest_attachment','Casco':'head'}
for authored in source.data.bones:
    anatomical=authored.name.replace('.IK','').replace('.FK','')
    if anatomical!=authored.name and anatomical in source.data.bones: alias[authored.name]=anatomical
keep=[b for b in source.data.bones if '.IK' not in b.name and '.FK' not in b.name and not b.name.startswith('Polo')]
data=bpy.data.armatures.new('EMUDeform'); rig=bpy.data.objects.new('AstronautRig',data)
bpy.context.collection.objects.link(rig); rig.matrix_world=source.matrix_world.copy()
bpy.context.view_layer.objects.active=rig; rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for bone in keep:
    target=data.edit_bones.new(alias.get(bone.name,bone.name))
    target.head=bone.head_local; target.tail=bone.tail_local; target.roll=source.data.edit_bones[bone.name].roll if source.mode=='EDIT' else 0
    target.align_roll(bone.matrix_local.to_3x3().col[2]); target.use_deform=True
for bone in keep:
    if bone.parent and bone.parent in keep: data.edit_bones[alias.get(bone.name,bone.name)].parent=data.edit_bones[alias.get(bone.parent.name,bone.parent.name)]
for side in ['L','R']:
    foot=data.edit_bones['foot.'+side]
    toe=data.edit_bones.new('toe.'+side); toe.head=foot.tail; toe.tail=foot.tail+(foot.tail-foot.head).normalized()*0.08; toe.parent=foot
bpy.ops.object.mode_set(mode='OBJECT')
meshes=[]; high_suit=None
for obj in list(bpy.data.objects):
    if obj.type!='MESH' or obj in custom or not obj.data.polygons: continue
    parent=obj.parent
    lineage=[]
    while parent: lineage.append(parent); parent=parent.parent
    if source not in lineage: continue
    for mod in obj.modifiers:
        if mod.type=='ARMATURE': mod.show_viewport=False
        if mod.type in ['MULTIRES','SUBSURF']: mod.levels=min(mod.levels,1)
    bpy.context.view_layer.update()
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh=bpy.data.meshes.new_from_object(evaluated)
    clean=bpy.data.objects.new('EMU_'+obj.name,mesh); bpy.context.collection.objects.link(clean)
    clean.matrix_world=obj.matrix_world.copy()
    for group in obj.vertex_groups:
        clean.vertex_groups.new(name=alias.get(group.name,group.name))
    for group in list(clean.vertex_groups):
        if group.name not in data.bones: clean.vertex_groups.remove(group)
    if obj.parent_type=='BONE':
        group=clean.vertex_groups.get(alias.get(obj.parent_bone,obj.parent_bone)) or clean.vertex_groups.new(name=alias.get(obj.parent_bone,obj.parent_bone))
        group.add(list(range(len(mesh.vertices))),1.0,'REPLACE')
    elif not clean.vertex_groups:
        group=clean.vertex_groups.new(name='chest'); group.add(list(range(len(mesh.vertices))),1,'REPLACE')
    clean.parent=rig; clean.matrix_world=obj.matrix_world.copy()
    mod=clean.modifiers.new('Deform','ARMATURE'); mod.object=rig
    bpy.context.view_layer.objects.active=clean
    bpy.ops.object.select_all(action='DESELECT'); clean.select_set(True)
    bpy.ops.object.vertex_group_limit_total(limit=4); bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    if len(clean.vertex_groups)==1:
        saved=clean.matrix_world.copy()
        bone_name=clean.vertex_groups[0].name
        clean.vertex_groups[0].add(list(range(len(mesh.vertices))),1.0,'REPLACE')
        clean.parent_type='BONE'; clean.parent_bone=bone_name
        clean.modifiers.remove(mod)
        bpy.context.view_layer.update(); clean.matrix_world=saved
    meshes.append(clean)

# Reconstruct portable materials from packed color/normal images; opaque gold visor.
converted={}
for obj in meshes:
    for slot in obj.material_slots:
        old=slot.material
        if not old: continue
        if old.name not in converted:
            mat=bpy.data.materials.new('Game_'+old.name); mat.use_nodes=True
            bsdf=mat.node_tree.nodes.get('Principled BSDF')
            bsdf.inputs['Roughness'].default_value=0.82
            images=[n.image for n in old.node_tree.nodes if n.type=='TEX_IMAGE' and n.image] if old.node_tree else []
            color=next((im for im in images if 'normal' not in im.name.lower() and 'nrm' not in im.name.lower()),None)
            normal=next((im for im in images if 'normal' in im.name.lower() or 'nrm' in im.name.lower()),None)
            for image in [color,normal]:
                if image and max(image.size)>2048: image.scale(min(image.size[0],2048),min(image.size[1],2048))
            if color:
                tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=color
                mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
            else:
                diffuse=next((n for n in old.node_tree.nodes if n.type=='BSDF_DIFFUSE'),None) if old.node_tree else None
                bsdf.inputs['Base Color'].default_value=tuple(diffuse.inputs['Color'].default_value) if diffuse else tuple(old.diffuse_color)
            if 'metal' in old.name.lower() or 'anisotropico' in old.name.lower():
                bsdf.inputs['Metallic'].default_value=0.65; bsdf.inputs['Roughness'].default_value=0.45
            if 'transparente' in old.name.lower() or (old.node_tree and any(n.type=='BSDF_GLASS' for n in old.node_tree.nodes)):
                bsdf.inputs['Alpha'].default_value=0.04; bsdf.inputs['Roughness'].default_value=0.12
                mat.surface_render_method='BLENDED'
            if normal:
                normal.colorspace_settings.name='Non-Color'
                tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=normal
                node=mat.node_tree.nodes.new('ShaderNodeNormalMap'); node.inputs['Strength'].default_value=0.35
                mat.node_tree.links.new(tex.outputs['Color'],node.inputs['Color']); mat.node_tree.links.new(node.outputs['Normal'],bsdf.inputs['Normal'])
            if any(s in old.name.lower() for s in ['glass','vidrio','gold','oro']):
                bsdf.inputs['Base Color'].default_value=(0.35,0.22,0.06,1); bsdf.inputs['Metallic'].default_value=0.85; bsdf.inputs['Roughness'].default_value=0.25
            converted[old.name]=mat
        slot.material=converted[old.name]

# Sculpt-derived body normal bake: retained source high resolution to game surface.
suit=next(o for o in meshes if 'Traje' in o.name)
high=None
if '--reuse-bake' in __import__('sys').argv and (OUT/'sculpt_normal.png').exists():
    image=bpy.data.images.load(str(OUT/'sculpt_normal.png')); image.colorspace_settings.name='Non-Color'; image.pack()
else:
    original=bpy.data.objects['Traje (Suit)']
    original.modifiers['Multires'].levels=3
    bpy.context.view_layer.update()
    high_mesh=bpy.data.meshes.new_from_object(original.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    high=bpy.data.objects.new('BakeHigh',high_mesh); bpy.context.collection.objects.link(high); high.matrix_world=original.matrix_world.copy()
    high.data.materials.clear()
    image=bpy.data.images.new('EMU_Sculpt_Normal',width=2048,height=2048); image.colorspace_settings.name='Non-Color'
    for mat in suit.data.materials:
        node=mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image=image; mat.node_tree.nodes.active=node
    bpy.ops.object.select_all(action='DESELECT'); suit.select_set(True); high.select_set(True); bpy.context.view_layer.objects.active=suit
    scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=1
    scene.render.bake.use_selected_to_active=True; scene.render.bake.cage_extrusion=0.035; scene.render.bake.margin=8
    bpy.ops.object.bake(type='NORMAL')
    image.filepath_raw=str(OUT/'sculpt_normal.png'); image.file_format='PNG'; image.save(); image.pack()
for mat in suit.data.materials:
    bsdf=mat.node_tree.nodes.get('Principled BSDF'); tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=image
    normal=mat.node_tree.nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value=0.7
    mat.node_tree.links.new(tex.outputs['Color'],normal.inputs['Color']); mat.node_tree.links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
if high is not None: bpy.data.objects.remove(high,do_unlink=True)

# New authored motion, not captured astronaut biomechanics. Root remains in place.
rig.animation_data_create()
def rotation_world(name,axis,angle):
    bone=rig.pose.bones[name]; rest=bone.bone.matrix_local.to_quaternion()
    bone.rotation_mode='QUATERNION'; bone.rotation_quaternion=rest.inverted() @ Quaternion(Vector(axis),angle) @ rest
def pose(phase,amount,kind):
    for bone in rig.pose.bones: bone.rotation_mode='QUATERNION'; bone.rotation_quaternion=Quaternion(); bone.location=Vector((0,0,0))
    for side,sign in [('L',1),('R',-1)]:
        name='upper_arm.'+side
        bone=rig.pose.bones[name]; old=(bone.bone.tail_local-bone.bone.head_local).normalized()
        desired=Vector((sign*0.12,-0.08,-1)).normalized()
        rest=bone.bone.matrix_local.to_quaternion()
        bone.rotation_quaternion=rest.inverted() @ old.rotation_difference(desired) @ rest
        swing=math.sin(phase+(0 if side=='L' else math.pi))*amount
        rotation_world('thigh.'+side,(1,0,0),swing*0.36)
        rotation_world('shin.'+side,(1,0,0),max(0,-swing)*0.60)
        rotation_world('foot.'+side,(1,0,0),-swing*0.12)
        bone.rotation_quaternion=bone.rotation_quaternion @ Quaternion((1,0,0),-swing*0.22)
    if kind in ['brace','stumble','recovery']:
        rotation_world('spine',(1,0,0),0.14 if kind=='brace' else 0.28*math.sin(phase*0.5))
    if kind=='fall': rotation_world('root',(1,0,0),-min(phase/(2*math.pi),1)*1.35)
    if kind in ['turn_left','turn_right']: rotation_world('chest',(0,0,1),(-1 if kind=='turn_left' else 1)*0.12*math.sin(phase*0.5))
clips={'idle':(2,0.02),'walk':(1,1),'fast_walk':(.7,1.15),'turn_left':(1,.15),'turn_right':(1,.15),'stop':(.5,.1),'brace':(1,0),'stumble':(.65,.45),'fall':(.8,0),'recovery':(2,0.2)}
scene=bpy.context.scene
scene.render.fps=30
for name,(seconds,amount) in clips.items():
    action=bpy.data.actions.new(name); rig.animation_data.action=action
    frames=max(2,round(seconds*30))
    for frame in range(0,frames+1,2):
        pose(frame/frames*math.tau,amount,name)
        for bone in rig.pose.bones:
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
    action.use_fake_user=True
rig.animation_data.action=None; pose(0,0,'idle')
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
rig.data.pose_position='REST'
if triangles>40000:
    for obj in meshes:
        modifier=obj.modifiers.new('Budget','DECIMATE'); modifier.ratio=39000/triangles
        bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=modifier.name)
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
def export(name):
    bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True)
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(OUT/name),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_def_bones=True,export_influence_nb=4,export_all_influences=False)
rig.data.pose_position='POSE'
export('astronaut.glb')
report={'source':'Juan Ignacio Gil-Hutton, BlendSwap 12622','license':'CC-BY 3.0','triangles':triangles,'bones':[b.name for b in data.bones],'clips':list(clips),'textures_max':2048,'constraints':sum(len(b.constraints) for b in rig.pose.bones),'motion':'authored illustrative Mars-inspired motion','normal_bake':'source Multires 3 to game Multires 1, tangent normal 2048'}
(OUT/'manifest.json').write_text(json.dumps(report,indent=2))
original_meshes={obj:obj.data for obj in meshes}
for ratio,label in [(0.55,'lod1'),(0.28,'lod2')]:
    rig.data.pose_position='REST'
    for obj in meshes:
        obj.data=original_meshes[obj].copy()
        mod=obj.modifiers.new('LOD','DECIMATE'); mod.ratio=ratio
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    rig.data.pose_position='POSE'
    export('astronaut_'+label+'.glb')
    for obj in meshes: obj.data=original_meshes[obj]
print('ASTRONAUT_PREPARED',json.dumps(report))
