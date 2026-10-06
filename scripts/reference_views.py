import bpy, pathlib, math
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'evidence'/'reference_views'; out.mkdir(exist_ok=True)
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=48; scene.cycles.use_denoising=True
scene.render.resolution_x=900; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs[0].default_value=(.25,.25,.25,1)
scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.6
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=-1
scene.render.film_transparent=False
for pos,power,size in [((3,-4,6),1400,5),((-4,-1,3),1000,4),((0,5,5),1800,4)]:
 d=bpy.data.lights.new('StudioArea','AREA'); o=bpy.data.objects.new(d.name,d); scene.collection.objects.link(o)
 o.location=pos; o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler(); d.energy=power; d.shape='DISK';d.size=size
data=bpy.data.cameras.new('ReferenceCamera'); cam=bpy.data.objects.new('ReferenceCamera',data); scene.collection.objects.link(cam);scene.camera=cam;data.type='ORTHO';data.ortho_scale=4.2
views={'front':(0,-6,1),'rear':(0,6,1),'left':(6,0,1),'right':(-6,0,1),'top':(0,0,7),'underside':(0,0,-6),'front_left':(4,-5,3.6),'front_right':(-4,-5,3.6),'rear_left':(4,5,3.6),'rear_right':(-4,5,3.6)}
for name,pos in views.items():
 cam.location=pos;cam.rotation_euler=(Vector((0,0,1))-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
