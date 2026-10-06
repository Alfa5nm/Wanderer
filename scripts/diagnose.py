import bpy
from mathutils import Vector
for o in bpy.data.objects:
 if o.type=='MESH':
  v=[o.matrix_world@v.co for v in o.data.vertices]
  if max(abs(x.z) for x in v)>2.3 or max(abs(x.x) for x in v)>1.5:
   print('OUTLIER',o.name,[(round(min(vv[i] for vv in v),3),round(max(vv[i] for vv in v),3)) for i in range(3)],'delta',o.delta_location[:],o.delta_scale[:])
