$input v_texcoord0

#include <bgfx_shader.sh>
#include "common/postprocess.sh"

void main()
{
    gl_FragColor = texture2D(s_postprocess_input0, v_texcoord0);
}