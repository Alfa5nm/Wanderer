shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
#include "res://planetary_map/visuals/dust_common.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 eye_origin;
uniform vec3 sun_direction;
uniform float physical_radius_m=3396190.0;
uniform float ground_radius = 1.0;
uniform float shell_height = 0.02;
uniform float render_scale = 1000.0;
uniform int sample_count = 8;
vec2 sphere(vec3 origin,vec3 ray,float radius) {
    float b=dot(origin,ray);
    float h=b*b-dot(origin,origin)+radius*radius;
    if(h<0.0) return vec2(-1.0);
    return vec2(-b-sqrt(h),-b+sqrt(h));
}
void vertex() { POSITION=vec4(VERTEX.xy,1.0,1.0); }
void fragment() {
    vec2 uv=SCREEN_UV;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    float far_depth=1.0;
#else
    float far_depth=0.00001;
#endif
    vec4 far_view=INV_PROJECTION_MATRIX*vec4(uv*2.0-1.0,far_depth,1.0);
    vec3 ray=normalize((INV_VIEW_MATRIX*vec4(normalize(far_view.xyz/far_view.w),0.0)).xyz);
    vec2 shell=sphere(eye_origin,ray,ground_radius+shell_height);
    float start=max(shell.x,0.0);
    float end=shell.y;
    vec2 ground=sphere(eye_origin,ray,ground_radius);
    if(ground.x>0.0) end=min(end,ground.x);
    float depth=texture(depth_texture,uv).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    float ndc_depth=depth*2.0-1.0;
#else
    float ndc_depth=depth;
#endif
    vec4 surface_view=INV_PROJECTION_MATRIX*vec4(uv*2.0-1.0,ndc_depth,1.0);
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    bool has_surface=depth<0.999999;
#else
    bool has_surface=depth>0.000001;
#endif
    if(has_surface) end=min(end,length(surface_view.xyz/surface_view.w)/render_scale);
    float optical=0.0;
    vec3 light=vec3(0.0);
    float step_length=max(end-start,0.0)/float(sample_count);
    vec3 sun=normalize(sun_direction);
    float cosine=dot(ray,sun);
    float phase=0.20+min(dust_phase(cosine)*0.065,1.5);
    for(int i=0;i<8;i++) {
        if(i>=sample_count) break;
        vec3 p=eye_origin+ray*(start+(float(i)+0.5)*step_length);
        float height=max(length(p)-ground_radius,0.0);
        float height_m=height*physical_radius_m;
        float local_density=exp(-height_m/scale_height_m)*extinction_per_m*physical_radius_m*atmosphere_strength;
        vec2 shadow=sphere(p,sun,ground_radius);
        float lit=shadow.y>0.0 && shadow.x>0.0 ? 0.0 : 1.0;
        vec4 transport=dust_solar_transport(height_m,dot(normalize(p),sun));
        vec3 sky=dust_sky(ray,sun,normalize(p),height_m);
        light+=(dust_color.rgb*transport.rgb*phase+sky*0.5)*local_density*step_length*exp(-optical)*lit;
        optical+=local_density*step_length;
    }
    float alpha=1.0-exp(-optical);
    ALBEDO=clamp(light/max(alpha,0.00001),vec3(0.0),dust_color.rgb);
    ALPHA=shell.y>start ? min(alpha,0.75) : 0.0;
}
