#version 330 core

in vec4 v_color;
out vec4 o_color;

const float brightness = 0.25;

void main() {
	o_color = vec4(brightness * abs(normalize(v_color.rgb - 0.5)), 1.0);
}

