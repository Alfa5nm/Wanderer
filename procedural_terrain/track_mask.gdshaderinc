uniform bool tracks_enabled=false;
uniform bool track_overlay=false;
uniform sampler2D track_mask : filter_linear, repeat_disable;
uniform vec4 track_bounds=vec4(0.0,0.0,16.0,16.0);
vec4 sample_track(vec2 point) {
    vec2 uv=(point-track_bounds.xy)/track_bounds.zw;
    if(!tracks_enabled || any(lessThan(uv,vec2(0))) || any(greaterThan(uv,vec2(1))))
        return vec4(0.0,128.0/255.0,0.0,1.0);
    return textureLod(track_mask,uv,0.0);
}
