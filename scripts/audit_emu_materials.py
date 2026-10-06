import bpy,json
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath=str(Path('source/astronaut/Astronauta.blend').resolve()),load_ui=False,use_scripts=False)
rows=[]
for m in bpy.data.materials:
 rows.append({'name':m.name,'diffuse':list(m.diffuse_color),'nodes':[{'type':n.type,'inputs':{i.name:list(i.default_value) if hasattr(i.default_value,'__len__') and not isinstance(i.default_value,str) else i.default_value for i in n.inputs if hasattr(i,'default_value') and i.name in ['Color','Base Color','Roughness','Metallic','Alpha']}} for n in (m.node_tree.nodes if m.node_tree else []) if n.type.startswith('BSDF') or n.type=='RGB']})
Path('evidence/astronaut_original_materials.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')

objects=[]
for o in bpy.data.objects:
 if o.type!='MESH': continue
 points=[o.matrix_world@__import__('mathutils').Vector(v) for v in o.bound_box]
 if max(v.z for v in points)<1.5: continue
 objects.append({'name':o.name,'parent_bone':o.parent_bone,'bounds':[[min(v[i] for v in points),max(v[i] for v in points)] for i in range(3)],'materials':[s.material.name if s.material else '' for s in o.material_slots]})
Path('evidence/astronaut_head_parts.json').write_text(json.dumps(objects,indent=2),encoding='utf-8')

for obj in bpy.data.objects:
 if obj.name in ["Cubre todo","Cubre todo.001","Cubre todo.002","Vidrio (Glass)","Parasol"]: print("HEAD_VISIBILITY",obj.name,obj.hide_render,obj.hide_viewport)
