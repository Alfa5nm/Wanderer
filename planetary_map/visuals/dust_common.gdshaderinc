// Shared ground-to-orbit RGB approximation. The transport table is project-authored;
// it is not a calibrated spectral atmosphere or a NASA weather product.
uniform sampler2D dust_transport : filter_linear, repeat_disable;
uniform bool has_dust_transport=false;
uniform float atmosphere_strength = 1.35;
uniform vec4 dust_color : source_color = vec4(0.769,0.635,0.525,1.0);
uniform float dust_g = 0.65;
uniform float scale_height_m = 10500.0;
uniform float extinction_per_m = 0.000085;
uniform float near_clear_m = 45.0;
float dust_day(float sun_height) { return smoothstep(-0.12,0.08,sun_height); }
vec4 dust_solar_transport(float height,float sun_height) {
    if(!has_dust_transport) {
        float tau=extinction_per_m*scale_height_m*exp(-max(height,0.0)/scale_height_m)/max(sun_height,0.08);
        return vec4(exp(-tau*vec3(0.65,0.87,1.3)),0.25+0.75*sqrt(max(sun_height,0.0)));
    }
    return texture(dust_transport,vec2(clamp(sun_height*0.5+0.5,0.0,1.0),clamp(height/85000.0,0.0,1.0)));
}
float dust_phase(float cosine) {
    float g=dust_g;
    return (1.0-g*g)/pow(max(1.0+g*g-2.0*g*cosine,0.01),1.5);
}
vec3 dust_sky(vec3 ray,vec3 sun,vec3 up,float height) {
    float mu=dot(ray,up), solar=dot(sun,up);
    float day=dust_day(solar);
    float air=exp(-max(height,0.0)/scale_height_m);
    float horizon=pow(1.0-max(mu,0.0),3.0);
    float cosine=dot(ray,sun);
    vec4 transport=dust_solar_transport(height,solar);
    float forward=clamp(dust_phase(cosine)*0.075,0.0,1.6);
    vec3 tan=dust_color.rgb*(0.65+0.90*horizon+0.20*forward);
    // Empirical blue solar aureole, constrained to twilight and the Sun's vicinity.
    float twilight=exp(-solar*solar/0.018);
    float aureole=pow(max(cosine,0.0),80.0)*twilight;
    vec3 sky=mix(tan,vec3(0.36,0.55,0.83),aureole*0.65);
    sky*=mix(0.35,1.0,transport.a)*day*air;
    sky*=1.0-exp(-atmosphere_strength*2.0);
    return sky;
}
