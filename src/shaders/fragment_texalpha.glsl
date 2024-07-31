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
    float alpha = col.r * vert_color.a;
    if (alpha == 0) {
        discard;
    }
    frag_color = vec4(vert_color.rgb, col.r*vert_color.a);
    if (desaturate) {
        float bw = (vert_color.r + vert_color.g + vert_color.b) / 3;
        frag_color = vec4(bw, bw, bw, col.r*vert_color.a);
    }
} 
