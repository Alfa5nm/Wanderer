"""Validate exported EMU data without Blender/Godot; fixtures never enter presentation."""
import io,json,struct,zipfile,hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def read_glb(path):
    data=path.read_bytes(); length=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+length]),data[28+length:]
g,binary=read_glb(ROOT/'assets/astronaut/astronaut.glb')
checks={}; parents={}
for i,node in enumerate(g['nodes']):
    for child in node.get('children',[]):
        assert child not in parents,'multiple parents'; parents[child]=i
for i in range(len(g['nodes'])):
    seen=set(); current=i
    while current in parents:
        assert current not in seen,'cyclic node hierarchy';seen.add(current);current=parents[current]
checks['acyclic_hierarchy']=True
joints={i for skin in g.get('skins',[]) for i in skin['joints']}
names=[g['nodes'][j].get('name','') for j in joints]
checks['no_authoring_controls']=not any(any(t in name for t in ['.IK','.FK','Polo']) for name in names)
clips=[a.get('name','') for a in g.get('animations',[])]
checks['ten_clips']=len(clips)==10
counts={}
for name in ['astronaut','astronaut_lod1','astronaut_lod2']:
    model,_=read_glb(ROOT/f'assets/astronaut/{name}.glb')
    counts[name]=sum(model['accessors'][p['indices']]['count']//3 for m in model['meshes'] for p in m['primitives'])
checks['triangle_budget']=counts['astronaut']<=40000
checks['decreasing_lod_counts']=counts['astronaut']>counts['astronaut_lod1']>counts['astronaut_lod2']
sizes=[]
for im in g.get('images',[]):
    if 'bufferView' not in im: continue
    v=g['bufferViews'][im['bufferView']];start=v.get('byteOffset',0)
    sizes.append(Image.open(io.BytesIO(binary[start:start+v['byteLength']])).size)
checks['texture_cap']=all(max(size)<=2048 for size in sizes)
formats={5126:('f',4),5123:('H',2),5121:('B',1)}
weight_errors=[]; joint_errors=[]
for mesh in g['meshes']:
    for primitive in mesh['primitives']:
        attrs=primitive['attributes']
        if 'WEIGHTS_0' not in attrs: continue
        for kind in ['WEIGHTS_0','JOINTS_0']:
            ac=g['accessors'][attrs[kind]];v=g['bufferViews'][ac['bufferView']];fmt,size=formats[ac['componentType']]
            start=v.get('byteOffset',0)+ac.get('byteOffset',0);stride=v.get('byteStride',size*4)
            for i in range(ac['count']):
                values=struct.unpack_from('<'+fmt*4,binary,start+i*stride)
                if kind=='WEIGHTS_0': weight_errors.append(abs(sum(values)-1))
                else: joint_errors.append(max(values)>=max(len(s['joints']) for s in g['skins']))
checks['normalized_weights']=max(weight_errors,default=0)<0.001
checks['valid_joint_indices']=not any(joint_errors)
archive=zipfile.ZipFile(ROOT/'source/astronaut/original_emu.zip')
checks['original_emu_preserved']=archive.read('Astronauta.blend')==(ROOT/'source/astronaut/Astronauta.blend').read_bytes()
checks['glass_exports_transparency']=any(m['name']=='Game_Material.007' and m.get('alphaMode')=='BLEND' for m in g['materials'])
report={'checks':checks,'measurements':{'triangles':counts,'joints':len(joints),'clips':clips,'texture_sizes':sizes,'max_weight_error':max(weight_errors,default=0),'archive_sha256':hashlib.sha256((ROOT/'source/astronaut/original_emu.zip').read_bytes()).hexdigest()}}
(ROOT/'evidence/astronaut_asset_checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'checks':checks,'triangles':counts,'joints':len(joints)}))
raise SystemExit(1 if False in checks.values() else 0)
