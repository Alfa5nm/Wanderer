shader_type spatial;
render_mode diffuse_burley;
uniform vec3 dust_color : source_color = vec3(0.34,0.20,0.12);
varying vec3 world_pos;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);
}
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz; }
void fragment(){
 float grain=noise(world_pos.xz*34.);
 float broad=noise(world_pos.xz*.17);
 float ridges=noise(world_pos.xz*2.1);
 ALBEDO=dust_color*(.74+.23*broad+.17*ridges+.10*grain);
 ROUGHNESS=.98;
}
