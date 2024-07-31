#version 330 core

layout(location = 0) out vec4 frag_color;

in vec4 vert_color;
in vec2 vert_texCoord;

uniform sampler2D tex;
uniform bool desaturate;

void main()
{
    vec4 col;
    col = vec4(1, 1, 1, 1);
    frag_color = col;
    // frag_color = vec4(vec3(gl_FragCoord.z), vert_color.a);
} 
