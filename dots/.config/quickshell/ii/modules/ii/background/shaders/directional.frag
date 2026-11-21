#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
};

layout(binding = 1) uniform sampler2D fromImage;
layout(binding = 2) uniform sampler2D toImage;

const vec2 direction = vec2(0.0, 1.0);

vec4 transition (vec2 uv) {
  vec2 p = uv + progress * sign(direction);
  vec2 f = fract(p);
  return mix(
    texture(toImage, f),
    texture(fromImage, f),
    step(0.0, p.y) * step(p.y, 1.0) * step(0.0, p.x) * step(p.x, 1.0)
  );
}

void transitionMain() {
    fragColor = transition(qt_TexCoord0);
}

void main() {
    transitionMain();
    fragColor *= qt_Opacity;
}
