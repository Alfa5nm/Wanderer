import bpy, math, pathlib
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parents[1]
scene=bpy.context.scene
for o in list(bpy.data.objects):
    if o.type=='MESH' and (o.name.endswith('_p') or o.name.startswith('Cube_') or any(m and m.name in ['pivot','shadow2'] for m in o.data.materials)):
        o.hide_render=True
scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.light='STUDIO'
scene.display.shading.color_type='TEXTURE'
scene.display.shading.show_shadows=True
scene.display.shading.show_cavity=True
scene.display.shading.background_type='WORLD'
scene.world.color=(0.09,0.09,0.09)
scene.render.resolution_x=1100; scene.render.resolution_y=850; scene.render.resolution_percentage=100
data=bpy.data.cameras.new('AuditCamera'); cam=bpy.data.objects.new('AuditCamera',data); scene.collection.objects.link(cam); scene.camera=cam
cam.location=(4,-5,3.4); cam.rotation_euler=(Vector((0,-0.15,1))-cam.location).to_track_quat('-Z','Y').to_euler(); data.type='ORTHO'; data.ortho_scale=4.8
scene.render.filepath=str(root/'evidence'/'original_reference.png'); bpy.ops.render.render(write_still=True)
