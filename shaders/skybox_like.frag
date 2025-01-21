#version 330 core

in vec3 color;
out vec4 fragment;

void main() {
    vec3 u = normalize(color + 0.5);
    float brightness = 1.0 * smoothstep(-1.0, -0.25, dot(u, vec3(0.0, 1.0, 0.0)));
	fragment = vec4(brightness * abs(u), 1.0);
}

