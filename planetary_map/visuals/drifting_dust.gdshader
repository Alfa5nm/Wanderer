shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 dust_tint : source_color = vec4(0.769,0.635,0.525,1.0);
uniform float daylight=1.0;
uniform float opacity=0.12;
varying float particle_depth;
void vertex() {
    // Camera-facing particles, preserving particle scale and translation.
    mat4 billboard=mat4(INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz),
                        INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz),
                        INV_VIEW_MATRIX[2]*length(MODEL_MATRIX[2].xyz),MODEL_MATRIX[3]);
    MODELVIEW_MATRIX=VIEW_MATRIX*billboard;
    particle_depth=-(MODELVIEW_MATRIX*vec4(VERTEX,1.0)).z;
}
void fragment() {
    vec2 p=UV*2.0-1.0;
    float radial=exp(-dot(p,p)*4.0)*(1.0-smoothstep(0.60,1.0,length(p)));
    float scene_depth=texture(depth_texture,SCREEN_UV).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    float ndc_depth=scene_depth*2.0-1.0;
#else
    float ndc_depth=scene_depth;
#endif
    vec4 scene=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,ndc_depth,1.0);
    float separation=-scene.z/scene.w-particle_depth;
    float soft=smoothstep(0.0,0.65,separation);
    float near_fade=smoothstep(0.4,2.0,particle_depth);
    ALBEDO=dust_tint.rgb*0.32*daylight;
    ALPHA=radial*soft*near_fade*opacity*COLOR.a*daylight;
}
