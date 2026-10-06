shader_type sky;
#include "res://planetary_map/visuals/dust_common.gdshaderinc"
uniform vec3 sun_direction;
uniform vec3 sun_color=vec3(1.0,0.94,0.86);
uniform float solar_radius=0.003;
uniform float star_intensity=0.35;
uniform float altitude_m=0.0;
float star_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void sky() {
    vec3 ray=normalize(EYEDIR), sun=normalize(sun_direction);
    float cosine=clamp(dot(ray,sun),-1.0,1.0);
    float angle=acos(cosine);
    vec4 transport=dust_solar_transport(altitude_m,sun.y);
    float day=dust_day(sun.y);
    float disk=(1.0-smoothstep(solar_radius*0.85,solar_radius*1.1,angle))*step(0.0,ray.y);
    float halo=exp(-angle/0.035)*0.08*day;
    vec3 atmosphere=dust_sky(ray,sun,vec3(0,1,0),altitude_m);
    vec2 uv=vec2(atan(ray.x,ray.z)/6.2831853+0.5,asin(ray.y)/3.1415926+0.5);
    vec2 grid=uv*vec2(1600,800), cell=floor(grid);
    vec2 star=vec2(star_hash(cell+3.0),star_hash(cell+17.0))*0.6+0.2;
    float width=max(length(fwidth(grid))*0.45,0.06);
    float point=exp(-dot(fract(grid)-star,fract(grid)-star)/(width*width));
    float stars=step(0.986,star_hash(cell))*point*star_intensity*(1.0-day)*step(0.0,ray.y);
    COLOR=atmosphere+sun_color*transport.rgb*(disk*3.0+halo)*day+vec3(stars);
}
