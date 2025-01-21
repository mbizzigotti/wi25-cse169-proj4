#version 330 core

uniform mat4 u_ViewProj;

out vec3 color;

const vec3 [] vertices = vec3 [] (
    vec3(-0.5, -0.5,  0.5), // 0 Front Bottom-left
    vec3( 0.5, -0.5,  0.5), // 1 Front Bottom-right
    vec3( 0.5,  0.5,  0.5), // 2 Front Top-right
    vec3(-0.5,  0.5,  0.5), // 3 Front Top-left
    vec3(-0.5, -0.5, -0.5), // 4 Back  Bottom-left
    vec3( 0.5, -0.5, -0.5), // 5 Back  Bottom-right
    vec3( 0.5,  0.5, -0.5), // 6 Back  Top-right
    vec3(-0.5,  0.5, -0.5)  // 7 Back  Top-left
);

const int [] indices = int [] (
    0, 1, 2, 2, 3, 0, // Front face
    4, 6, 5, 6, 4, 7, // Back face
    4, 0, 3, 3, 7, 4, // Left face
    1, 5, 6, 6, 2, 1, // Right face
    3, 2, 6, 6, 7, 3, // Top face
    4, 5, 1, 1, 0, 4  // Bottom face
);

void main() {
    vec3 pos = vertices[indices[gl_VertexID]];
    gl_Position = u_ViewProj * vec4(40.0 * pos, 1.0);
    color = pos + 0.5;
}
