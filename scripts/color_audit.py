import bpy
s=bpy.context.scene
print('EXPOSURE',s.view_settings.exposure,'GAMMA',s.view_settings.gamma,'LOOK',s.view_settings.look)
for i in bpy.data.images: print(i.name,i.colorspace_settings.name)
