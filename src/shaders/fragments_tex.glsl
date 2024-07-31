#version 330 core

layout(location = 0) out vec4 frag_color;

in vec4 vert_color;
in vec2 vert_texCoord;

uniform sampler2D tex;
uniform bool desaturate;

void main()
{
    vec4 col;
    col = texture(tex, vert_texCoord.xy);
    frag_color = vec4(col.xyz, col.a * vert_color.a);
    // frag_color = vec4(vec3(gl_FragCoord.z), vert_color.a);
} 
