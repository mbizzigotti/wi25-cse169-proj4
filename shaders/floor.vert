#version 330 core

uniform mat4 u_ViewProj;

out vec3 position;

const vec3 [] vertices = vec3 [] (
    vec3(-0.5, -0.5,  0.5),
    vec3( 0.5, -0.5,  0.5),
    vec3(-0.5, -0.5, -0.5),
    vec3( 0.5, -0.5, -0.5)
);

const int [] indices = int [] (
    0, 1, 2, 2, 1, 3
);

const vec3 size = vec3(30.0, 2.0, 30.0);

void main() {
    vec3 pos = vertices[indices[gl_VertexID]];
    gl_Position = u_ViewProj * vec4(size * pos, 1.0);
    position = pos + 0.5;
}
