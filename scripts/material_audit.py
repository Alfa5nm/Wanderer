import bpy
for name in ['tex_03_n','tex_01','tex_02','tex_03']:
 m=bpy.data.materials.get(name)
 if m:
  print(name)
  for l in m.node_tree.links:print(l.from_node.name,l.from_socket.name,'->',l.to_node.name,l.to_socket.name)
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE': print(n.name,n.image.name if n.image else None)
