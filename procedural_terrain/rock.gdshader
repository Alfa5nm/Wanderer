shader_type spatial;
uniform bool cinematic=true;
uniform float cosmetic_seed=7462.0;
uniform bool gravel=false;
uniform float fade_distance=55.0;
varying vec3 stone_position;
#include "res://procedural_terrain/track_mask.gdshaderinc"
varying float camera_distance;
float hash(vec3 p) {
    vec3 q=fract(p*0.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float noise(vec3 p) {
    vec3 c=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(c),hash(c+vec3(1,0,0)),f.x),mix(hash(c+vec3(0,1,0)),hash(c+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash(c+vec3(0,0,1)),hash(c+vec3(1,0,1)),f.x),mix(hash(c+vec3(0,1,1)),hash(c+vec3(1,1,1)),f.x),f.y),f.z);
}
uniform sampler2D rock_detail : filter_linear_mipmap_anisotropic, repeat_enable;
void vertex() {
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    stone_position=world;
    camera_distance=length(world-CAMERA_POSITION_WORLD);
    if (gravel) {
        if(tracks_enabled && sample_track(world.xz).b>0.15) VERTEX*=0.0;
        float fade=1.0-smoothstep(fade_distance*0.65,fade_distance,camera_distance);
        VERTEX*=fade;
    }
}
void fragment() {
    float variation=noise(stone_position*7.0+vec3(cosmetic_seed*0.071));
    float speck=noise(stone_position*57.0);
    ALBEDO=cinematic ? mix(vec3(0.14,0.10,0.075),vec3(0.31,0.235,0.175),variation)*(0.91+0.18*speck) : vec3(0.21,0.19,0.17);
    ROUGHNESS=cinematic ? 0.91+0.08*variation : 0.97;
    SPECULAR=0.045;
    if(cinematic) {
        vec4 detail=texture(rock_detail,stone_position.xz*0.8);
        vec3 wn=normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
        vec3 gradient=vec3(detail.r*2.0-1.0,0,detail.g*2.0-1.0);
        gradient-=wn*dot(gradient,wn);
        float footprint=max(length(dFdx(stone_position)),length(dFdy(stone_position)));
        NORMAL=normalize(mat3(VIEW_MATRIX)*(wn+gradient*0.35*(1.0-smoothstep(0.03,0.15,footprint))));
        ROUGHNESS=mix(ROUGHNESS,detail.a,0.5);
    }
}
