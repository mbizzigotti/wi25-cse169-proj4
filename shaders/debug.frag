#version 330 core

out vec4 fragment;

const vec4 [] colors = vec4 [] (
    vec4(1.0, 0.0, 0.0, 1.0),
    vec4(0.0, 1.0, 0.0, 1.0),
    vec4(0.0, 0.0, 1.0, 1.0),
    vec4(1.0, 1.0, 0.0, 1.0),
    vec4(1.0, 0.0, 1.0, 1.0),
    vec4(1.0, 1.0, 0.0, 1.0),
    vec4(0.5, 0.5, 0.5, 1.0),
    vec4(1.0, 1.0, 1.0, 1.0)
);

void main() {
    fragment = colors[gl_PrimitiveID % 8];
}
