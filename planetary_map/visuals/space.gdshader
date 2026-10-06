shader_type sky;
#include "res://planetary_map/visuals/dust_common.gdshaderinc"
uniform vec3 sun_direction;
uniform vec3 sun_color = vec3(1.0,0.94,0.86);
uniform float solar_radius = 0.003;
uniform float star_intensity = 0.35;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void sky() {
    vec3 ray=normalize(EYEDIR);
    float angle=acos(clamp(dot(ray,normalize(sun_direction)),-1.0,1.0));
    float disk=1.0-smoothstep(solar_radius*0.87,solar_radius*1.12,angle);
    float halo=0.025*exp(-angle/max(solar_radius*2.5,0.001));
    vec2 uv=vec2(atan(ray.x,ray.z)/6.2831853+0.5,asin(ray.y)/3.1415926+0.5);
    vec2 grid=uv*vec2(1600.0,800.0);
    vec2 cell=floor(grid);
    vec2 star=vec2(hash(cell+3.0),hash(cell+17.0))*0.6+0.2;
    float width=max(length(fwidth(grid))*0.45,0.06);
    float profile=exp(-dot(fract(grid)-star,fract(grid)-star)/(width*width));
    float exists=step(0.986,hash(cell));
    float intensity=pow(hash(cell+43.0),3.0)*0.7+0.3;
    vec3 tint=mix(vec3(0.74,0.83,1.0),vec3(1.0,0.87,0.73),hash(cell+9.0));
    vec3 stars=tint*exists*profile*intensity*star_intensity*smoothstep(0.015,0.09,angle);
    COLOR=stars+sun_color*(disk*3.0+halo);
}
