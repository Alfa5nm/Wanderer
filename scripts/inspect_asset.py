import bpy, json, pathlib
from mathutils import Vector
root = pathlib.Path(__file__).resolve().parents[1]
report = {'blender': bpy.app.version_string, 'units': bpy.context.scene.unit_settings.system, 'scale_length': bpy.context.scene.unit_settings.scale_length, 'objects': [], 'materials': [], 'images': []}
for o in bpy.data.objects:
    corners = [o.matrix_world @ Vector(c) for c in o.bound_box] if o.type == 'MESH' else []
    report['objects'].append({'name': o.name, 'type': o.type, 'parent': o.parent.name if o.parent else None, 'location': list(o.matrix_world.translation), 'dimensions': list(o.dimensions), 'rotation': list(o.rotation_euler), 'scale': list(o.scale), 'vertices': len(o.data.vertices) if o.type == 'MESH' else 0, 'triangles': sum(len(p.vertices)-2 for p in o.data.polygons) if o.type == 'MESH' else 0, 'bounds': [[min(v[i] for v in corners) for i in range(3)], [max(v[i] for v in corners) for i in range(3)]] if corners else [], 'modifiers': [m.type for m in o.modifiers], 'constraints': [c.type for c in o.constraints], 'materials': [m.name if m else None for m in o.data.materials] if o.type == 'MESH' else []})
for m in bpy.data.materials:
    report['materials'].append({'name': m.name, 'nodes': [n.type for n in m.node_tree.nodes] if m.use_nodes else [], 'color': list(m.diffuse_color)})
for im in bpy.data.images:
    report['images'].append({'name': im.name, 'path': im.filepath, 'packed': bool(im.packed_file), 'size': list(im.size)})
(root/'evidence'/'asset_original.json').write_text(json.dumps(report, indent=2))
print('ASSET_AUDIT', len(report['objects']), sum(o['triangles'] for o in report['objects']))
