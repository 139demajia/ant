$input a_position, a_normal
$output v_normal, v_color0, v_viewdir
#include <bgfx_shader.sh>
#include "common/lighting.sh"

uniform vec4 u_color;

void main()
{
    vec3 pos = a_position;
    gl_Position = mul(u_modelViewProj, vec4(pos, 1.0));
    vec4 origin = mul(u_modelViewProj,vec4(0.0,0.0,0.0,1.0));
    if((gl_Position.z+gl_Position.w)/gl_Position.w > (origin.z+origin.w)*1.0001/origin.w)
        gl_Position.z = gl_Position.w+1;
    vec4 wpos = mul(u_model[0], vec4(pos, 1.0));
    
    v_viewdir = (u_eyepos - wpos).xyz;
    v_color0 = u_color;
    v_normal = a_normal;
}