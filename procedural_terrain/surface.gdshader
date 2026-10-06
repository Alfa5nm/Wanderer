shader_type spatial;
render_mode cull_back;
uniform sampler2D imagery : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cavity_map : filter_linear_mipmap, repeat_disable;
uniform vec4 terrain_bounds;
uniform bool cinematic=true;
uniform bool detail_maps_ready=false;
uniform float cosmetic_seed=7462.0;
uniform float tint_strength=0.62;
uniform vec4 dust_color : source_color = vec4(0.706,0.471,0.314,1.0);
uniform float broad_scale=0.2;
uniform float sand_scale=40.0;
uniform float normal_strength=0.32;
uniform float base_roughness=0.94;
uniform float occlusion_strength=0.18;
uniform float base_specular=0.06;
varying vec3 local_metres;
#include "res://procedural_terrain/track_mask.gdshaderinc"
float hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*0.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float noise(vec2 p) {
    vec2 c=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(c),hash(c+vec2(1,0)),f.x),mix(hash(c+vec2(0,1)),hash(c+vec2(1,1)),f.x),f.y);
}
#include "res://procedural_terrain/detail_textures.gdshaderinc"
void vertex() {
    vec3 point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    if(track_overlay && tracks_enabled && cinematic) {
        vec4 imprint=sample_track(point.xz);
        VERTEX.y+=(imprint.g-128.0/255.0)*0.04;
    }
    local_metres=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    vec3 observed=texture(imagery,UV).rgb;
    vec2 p=local_metres.xz;
    vec4 imprint=sample_track(p);
    if(tracks_enabled && cinematic) {
        if(track_overlay && imprint.r<0.5) discard;
        if(!track_overlay && imprint.r>=0.5) discard;
    }
    float dust=noise(p*broad_scale+vec2(cosmetic_seed*0.071));
    vec3 ground=observed;
    float rough=base_roughness;
    if (cinematic) {
        // Illustrative hue preserves luminance, never claims measured surface color.
        float luminance=dot(observed,vec3(0.2126,0.7152,0.0722));
        vec3 tint=dust_color.rgb/max(dot(dust_color.rgb,vec3(0.2126,0.7152,0.0722)),0.001);
        ground=mix(observed,luminance*tint,tint_strength);
        float footprint=max(length(dFdx(p)),length(dFdy(p)));
        float detail_fade=1.0-smoothstep(0.025,0.20,footprint);
        float grain_fade=1.0-smoothstep(0.003,0.018,footprint);
        vec2 seed_offset=vec2(cosmetic_seed*0.071,cosmetic_seed*0.137);
        vec4 sand=stochastic_detail(sand_detail,p*max(sand_scale*0.04,0.01)+seed_offset);
        vec4 rock=stochastic_detail(rock_detail,p*0.45+seed_offset);
        float exposed=smoothstep(0.35,0.70,dust);
        float fine=(sand.a-0.90)*grain_fade;
        ground*=0.91+0.16*dust+0.07*(fine-0.5*grain_fade);
        // Rotate the world-space gradient into view space and project onto the tangent plane.
        vec3 detail_normal=normalize(mix(sand.rgb,rock.rgb,exposed)*2.0-1.0);
        vec3 gradient=vec3(-detail_normal.x,0,-detail_normal.y)/max(detail_normal.z,0.25);
        vec3 wn=normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
        gradient-=wn*dot(gradient,wn);
        if(detail_maps_ready) {
            NORMAL=normalize(mat3(VIEW_MATRIX)*(wn-gradient*normal_strength*detail_fade*(1.0-0.85*imprint.b)));
            rough=clamp(mix(base_roughness,mix(sand.a,rock.a,exposed),0.70),0.78,1.0);
        }
    }
    vec2 cavity_uv=(p-terrain_bounds.xy)/terrain_bounds.zw;
    float cavity=0.0;
    if (all(greaterThanEqual(cavity_uv,vec2(0))) && all(lessThanEqual(cavity_uv,vec2(1))))
        cavity=texture(cavity_map,cavity_uv).r;
    // Orbital imagery contains baked illumination. Occlude indirect lighting only.
    if(track_overlay && cinematic && tracks_enabled) {
        // The same sourced color and material continue across the track boundary.
        ground*=1.0-0.075*imprint.b;
        rough=mix(rough,0.97,imprint.b*0.65);
        vec2 step_m=track_bounds.zw/vec2(textureSize(track_mask,0));
        float dx=(sample_track(p+vec2(step_m.x,0)).g-sample_track(p-vec2(step_m.x,0)).g)*0.04/(2.0*step_m.x);
        float dz=(sample_track(p+vec2(0,step_m.y)).g-sample_track(p-vec2(0,step_m.y)).g)*0.04/(2.0*step_m.y);
        vec3 wn=normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
        NORMAL=normalize(mat3(VIEW_MATRIX)*(wn-vec3(dx,0,dz)));
    }
    ALBEDO=ground;
    AO=1.0-cavity*occlusion_strength;
    ROUGHNESS=rough;
    SPECULAR=cinematic ? base_specular : 0.04;
}
