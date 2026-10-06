shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
#include "res://planetary_map/visuals/dust_common.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 sun_direction;
uniform float base_altitude_m=0.0;
uniform int sample_count=8;
uniform float haze_weight=1.0;
void vertex() { POSITION=vec4(VERTEX.xy,1.0,1.0); }
void fragment() {
    float depth=texture(depth_texture,SCREEN_UV).r;
    // Compatibility uses [-1,1] depth reconstruction, not Vulkan's [0,1].
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    float ndc_depth=depth*2.0-1.0;
#else
    float ndc_depth=depth;
#endif
    vec4 view=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,ndc_depth,1.0);
    vec3 surface=view.xyz/view.w;
    float distance_m=length(surface);
    vec3 ray=normalize(mat3(INV_VIEW_MATRIX)*surface);
    vec3 eye=INV_VIEW_MATRIX[3].xyz;
    float drift=TIME*0.035;
    float path=max(distance_m-near_clear_m,0.0), optical=0.0;
    for(int i=0;i<8;i++) {
        if(i>=sample_count) break;
        float t=near_clear_m+path*(float(i)+0.5)/float(sample_count);
        float height=clamp(base_altitude_m+eye.y+ray.y*t,-10000.0,85000.0);
        vec3 location=eye+ray*t;
        // Illustrative low dust banks: stable world coordinates provide motion parallax.
        float banks=0.5+0.5*sin(location.x*0.013+sin(location.z*0.009)+drift);
        float low_dust=exp(-max(location.y-eye.y+2.0,0.0)/18.0);
        float layers=1.0+1.4*banks*low_dust;
        optical+=layers*exp(-height/scale_height_m)*path/float(sample_count)*extinction_per_m*atmosphere_strength;
    }
    vec3 radiance=dust_sky(ray,normalize(sun_direction),vec3(0,1,0),base_altitude_m+eye.y);
    ALBEDO=radiance;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    bool has_surface=depth<0.999999;
#else
    bool has_surface=depth>0.000001;
#endif
    ALPHA=has_surface ? clamp(1.0-exp(-optical*haze_weight),0.0,0.90) : 0.0;
}
