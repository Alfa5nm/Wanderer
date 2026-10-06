shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
    ALBEDO=vec3(0.85,0.67,0.39);
    ALPHA=smoothstep(0.0,0.18,UV.y)*smoothstep(0.0,0.18,1.0-UV.y)*smoothstep(0.0,0.04,UV.x)*smoothstep(0.0,0.04,1.0-UV.x)*0.72;
}
