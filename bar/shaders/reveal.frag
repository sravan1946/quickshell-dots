#version 440
// Focus-in, top to bottom: a soft band sweeps down the content; above it everything is sharp
// and in place, below it hidden. Inside the band each line fades in, sharpens out of a blur
// and drops the last few px into place, so a panel's rows arrive one after another.
// progress 0 = nothing, 1 = all in focus. Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float band;       // band height, as a fraction of the item
    float blur;       // px of blur at the band's leading edge
    float lift;       // px a line drops through as it lands
    vec2 res;         // item size in px
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    // 0 below the band, 1 above it
    float t = clamp((progress * (1.0 + band) - uv.y) / band, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float k = 1.0 - t;
    vec2 at = uv - vec2(0.0, k * lift / res.y);
    vec2 r = k * blur / res;
    vec4 c = texture(source, at) * 0.2
        + (texture(source, at + vec2(r.x, 0.0)) + texture(source, at - vec2(r.x, 0.0))
         + texture(source, at + vec2(0.0, r.y)) + texture(source, at - vec2(0.0, r.y))) * 0.125
        + (texture(source, at + r) + texture(source, at - r)
         + texture(source, at + vec2(r.x, -r.y)) + texture(source, at + vec2(-r.x, r.y))) * 0.075;
    fragColor = c * t * step(0.0, at.y) * qt_Opacity;
}
