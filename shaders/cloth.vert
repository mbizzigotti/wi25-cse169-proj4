#version 330 core

layout(location=0) in vec3 v_position;
layout(location=1) in vec3 v_color;
layout(location=2) in vec3 v_normal;

out vec3 position;
out vec3 color;
out vec3 normal;

uniform mat4 u_Model;
uniform mat4 u_ViewProj;

void main() {
    vec4 world = u_Model * vec4(v_position, 1.0);
	gl_Position = u_ViewProj * vec4(world.xyz, 1.0);
    position = world.xyz;
	color    = v_color;
    normal   = v_normal;
}
