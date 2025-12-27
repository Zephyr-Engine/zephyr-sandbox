#version 330 core

out vec4 FragColor;

uniform float r_color;

void main() {
    FragColor = vec4(r_color, 0.2f, 0.2f, 1.0f);
}
