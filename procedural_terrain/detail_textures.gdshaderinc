uniform sampler2D sand_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_detail : filter_linear_mipmap_anisotropic, repeat_enable;
// Three randomized offsets on a triangular lattice. Packed maps are linear data;
// RGB encodes local X, Z, Up normals, alpha roughness. Never displaces geometry.
vec4 stochastic_detail(sampler2D detail_map,vec2 p) {
    vec2 skew=vec2(p.x-p.y*0.57735027,p.y*1.15470054);
    vec2 cell=floor(skew), f=fract(skew);
    vec2 a=cell, b=cell+vec2(1,0), c=cell+vec2(0,1);
    vec3 weights=vec3(1.0-f.x-f.y,f.x,f.y);
    if(f.x+f.y>1.0) {
        a=cell+vec2(1,1); b=cell+vec2(0,1); c=cell+vec2(1,0);
        weights=vec3(f.x+f.y-1.0,1.0-f.x,1.0-f.y);
    }
    vec2 oa=vec2(hash(a),hash(a+19.0));
    vec2 ob=vec2(hash(b),hash(b+19.0));
    vec2 oc=vec2(hash(c),hash(c+19.0));
    // Explicit derivatives avoid mip seams at random-offset cell boundaries.
    vec2 dx=dFdx(p), dy=dFdy(p);
    return textureGrad(detail_map,p+oa,dx,dy)*weights.x+
           textureGrad(detail_map,p+ob,dx,dy)*weights.y+
           textureGrad(detail_map,p+oc,dx,dy)*weights.z;
}
