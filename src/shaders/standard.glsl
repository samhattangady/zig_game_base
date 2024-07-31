@vs vs
layout (location = 0) in vec3 position;
layout (location = 1) in vec4 in_color;
layout (location = 2) in vec2 in_texCoord;

out vec4 vert_color;
out vec2 vert_texCoord;

void main()
{
    gl_Position = vec4(position, 1.0);
    vert_color = in_color;
    vert_texCoord = in_texCoord;
}
@end

@vs vertex_frame
layout (location = 0) in vec3 position;
layout (location = 1) in vec4 in_color;
layout (location = 2) in vec2 in_texCoord;

layout (std140) uniform Frame {
  vec2 frame_origin;
  vec2 viewport_size;
  float viewport_zoom;
  float frame_zoom;
};

out vec4 vert_color;
out vec2 vert_texCoord;

void main()
{
    float zoom = frame_zoom * viewport_zoom;
    float width = viewport_size.x / zoom;
    float height = viewport_size.y / zoom;
    float top = frame_origin.y;
    float left = frame_origin.x;
    float x = (position.x - left) / width;
    float y = (position.y - top) / height;
    gl_Position = vec4((x-0.5)*2, (y-0.5)*-2, position.z, 1.0);
    vert_color = in_color;
    vert_texCoord = in_texCoord;
}
@end


@fs fs
layout(location = 0) out vec4 frag_color;

in vec4 vert_color;
in vec2 vert_texCoord;

uniform texture2D tex;
uniform sampler smp;

void main()
{
    vec4 col = texture(sampler2D(tex, smp), vert_texCoord.xy);
    float alpha = col.r * vert_color.a;
    if (alpha == 0) {
        discard;
    }
    frag_color = vec4(vert_color.rgb, alpha);
} 
@end

@fs sprite_shader
layout(location = 0) out vec4 frag_color;

in vec4 vert_color;
in vec2 vert_texCoord;

uniform texture2D tex;
uniform sampler smp;

void main()
{
    frag_color = texture(sampler2D(tex, smp), vert_texCoord.xy);
} 
@end


@program shd vs fs
@program terrain vertex_frame sprite_shader
@program terrain_use_pallette vertex_frame fs
