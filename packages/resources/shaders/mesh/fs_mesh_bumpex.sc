$input v_texcoord0, v_lightdir, v_viewdir, v_normal

#include <common.sh>

#include "common/uniforms.sh"
#include "common/lighting.sh"
#include "common/shadow.sh"

SAMPLER2D(s_basecolor,  0);
SAMPLER2D(s_normal, 	1);

uniform vec4 u_specularColor;
uniform vec4 u_specularLight;

void main()
{
	vec4 ntexdata 	= texture2D(s_normal, v_texcoord0.xy);
	float gloss 	= ntexdata.z;
	vec3 normal 	= unproject_normal(remap_normal(ntexdata.xy));

	vec4 basecolor  = texture2D(s_basecolor, v_texcoord0.xy);
	vec4 lightcolor = u_directional_color * u_directional_intensity.x;
	
	gl_FragColor 	= saturate(calc_lighting_BH(normal, v_lightdir, v_viewdir, lightcolor, 
												basecolor, u_specularColor, gloss, u_specularLight.x));
}