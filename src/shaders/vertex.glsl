#version 330 core

layout(location = 0) in vec3 aPos;

uniform vec3 r_position;

void main() {
    gl_Position = vec4(aPos.x + r_position.x, aPos.y + r_position.y, aPos.z + r_position.z, 1.0);
}
