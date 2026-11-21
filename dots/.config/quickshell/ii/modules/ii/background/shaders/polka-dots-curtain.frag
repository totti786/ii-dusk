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

const float SQRT_2 = 1.414213562373;
const float dots = 20.0;
const vec2 center = vec2(0, 0);

vec4 transition(vec2 uv) {
  if (progress >= 1.0) return texture(toImage, uv);
  bool nextImage = distance(fract(uv * dots), vec2(0.5, 0.5)) < ( progress / distance(uv, center));
  return nextImage ? texture(toImage, uv) : texture(fromImage, uv);
}

void transitionMain() {
    fragColor = transition(qt_TexCoord0);
}

void main() {
    transitionMain();
    fragColor *= qt_Opacity;
}
