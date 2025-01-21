#version 330 core

in vec3 position;
out vec4 fragment;

uniform vec3 u_ViewPos;

struct Light {
    vec3 position;
    vec3 color;
    float intensity;
};

vec3 point_light(Light light, vec3 norm, vec3 viewDir) {
    vec3 lightDir = normalize(light.position - position);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * light.color;
    vec3 reflectDir = reflect(-lightDir, norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    vec3 specular = light.intensity * spec * light.color;
    return diffuse + specular;
}

#define M 1.0
#define m 0.2

#define S 0.01

float lensq(in vec2 x) { return dot(x,x); }

void main() {
    vec2 coord = floor((position.xz - mod(position.xz, S)) / S);
    vec3 color = vec3(step(1.0, mod(coord.x + coord.y, 2.0)));

    Light light0, light1, light2, light3, light4;

    light0.position  = vec3(0,5,0);
    light0.color     = vec3(M,M,M);
    light0.intensity = 0.5;

    light1.position  = vec3(5,-2,0);
    light1.color     = vec3(M,m,m);
    light1.intensity = 0.5;

    light2.position  = vec3(0,2,5);
    light2.color     = vec3(m,m,M);
    light2.intensity = 0.5;

    light3.position  = vec3(-5,-2,0);
    light3.color     = vec3(M,m,m);
    light3.intensity = 0.5;

    light4.position  = vec3(0,2,-5);
    light4.color     = vec3(m,m,M);
    light4.intensity = 0.5;

    vec3 norm = gl_FrontFacing? vec3(0,1,0) : vec3(0,-1,0);
    vec3 viewDir = normalize(u_ViewPos - position);
    fragment = vec4 (
       (point_light(light0, norm, viewDir) * 0.5
    +   point_light(light1, norm, viewDir) * 0.5
    +   point_light(light2, norm, viewDir) * 0.5
    +   point_light(light3, norm, viewDir) * 0.5
    +   point_light(light4, norm, viewDir) * 0.5)
    *   color
    ,   min(exp(-100.0 * lensq(position.xz - vec2(0.5))), 0.5)
    );
}
