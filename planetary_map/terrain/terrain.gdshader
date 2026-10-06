shader_type spatial;
render_mode cull_back, ambient_light_disabled;
uniform sampler2D global_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo = true;
uniform sampler2D regional_image : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D local_image : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 regional_bounds = vec4(0.0);
uniform vec4 local_bounds = vec4(0.0);
uniform sampler2D stream_image_0 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D stream_image_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 stream_bounds_0 = vec4(0.0);
uniform vec4 stream_bounds_1 = vec4(0.0);
uniform sampler2D stream_image_2 : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 stream_bounds_2 = vec4(0.0);
uniform float imagery_blend = 1.0;
uniform float image_opacity_0 = 1.0;
uniform float image_opacity_1 = 1.0;
uniform float image_opacity_2 = 1.0;
uniform float image_opacity_3 = 1.0;
uniform float image_opacity_4 = 1.0;

uniform float regional_detail = 0.0;
uniform float morph = 1.0;
uniform float patch_extent = 1.0;
uniform float visual_detail_strength = 0.0;
float hash21(vec2 p) {
    p = fract(p*vec2(123.34,456.21));
    p += dot(p,p+45.32);
    return fract(p.x*p.y);
}
float value_noise(vec2 p) {
    vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    float a=hash21(i), b=hash21(i+vec2(1.0,0.0));
    float c=hash21(i+vec2(0.0,1.0)), d=hash21(i+vec2(1.0,1.0));
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
void vertex() {
    VERTEX += (COLOR.rgb - vec3(0.5)) * patch_extent * (1.0-morph);
}
vec4 projected_image(sampler2D source, vec4 bounds, vec2 geographic) {
    if (bounds.z <= 0.0 || bounds.w <= 0.0) return vec4(0.0);
    vec2 p = vec2((geographic.x-bounds.x)/bounds.z,1.0-(geographic.y-bounds.y)/bounds.w);
    if (p.x<0.0 || p.y<0.0 || p.x>1.0 || p.y>1.0) return vec4(0.0);
    vec4 image = texture(source,p);
    // A collar keeps valid regional data from ending as a hard rectangle.
    // Broad feathering applies only at a dataset footprint edge; contiguous
    // viewport atlases are already joined before filtering.
    float collar = smoothstep(0.0,0.34,min(min(p.x,1.0-p.x),min(p.y,1.0-p.y)));
    image.a *= collar*regional_detail;
    image.rgb *= 0.65; // Display reflectance; illumination is baked into the source imagery.
    return image;
}
void fragment() {
    vec3 color = has_albedo ? texture(global_albedo,vec2(fract(UV.x),UV.y)).rgb : vec3(0.52,0.25,0.13);
    vec2 geographic = vec2(UV.x*360.0-180.0,90.0-UV.y*180.0);
    vec4 regional = projected_image(regional_image,regional_bounds,geographic);
    vec4 local = projected_image(local_image,local_bounds,geographic);
    color = mix(color,regional.rgb,regional.a*imagery_blend*image_opacity_0);
    color = mix(color,local.rgb,local.a*imagery_blend*image_opacity_1);
    vec4 stream0 = projected_image(stream_image_0,stream_bounds_0,geographic);
    vec4 stream1 = projected_image(stream_image_1,stream_bounds_1,geographic);
    color = mix(color,stream0.rgb,stream0.a*imagery_blend*image_opacity_2);
    color = mix(color,stream1.rgb,stream1.a*imagery_blend*image_opacity_3);
    vec4 stream2 = projected_image(stream_image_2,stream_bounds_2,geographic);
    color = mix(color,stream2.rgb,stream2.a*imagery_blend*image_opacity_4);
    ALBEDO = color;
    // Visual microdetail is deliberately procedural and never enters sampled elevation.
    float macro = value_noise(geographic*0.18);
    float micro = value_noise(geographic*7.0);
    NORMAL = normalize(NORMAL + vec3((micro-0.5)*visual_detail_strength,(macro-0.5)*visual_detail_strength,0.0));
    ROUGHNESS = mix(0.93,0.995,macro);
    SPECULAR = 0.06;
}
