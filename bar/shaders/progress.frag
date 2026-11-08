#version 440
// The track's progress under the bar's media item (islands/Progress.qml): a lit filament over
// a faint track, a shimmer running along it towards the head, the head a spark that swells
// with the bass and flares on each kick. Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    float pad;       // px at each end left for the spark's glow
    float frac;      // track progress, 0..1
    float t;         // s, the frame clock
    float bass;      // 0..1
    float kick;      // the latest kick, fading: 0..1
    float glow;      // 1 playing, 0 paused
    vec4 c1;         // the cover's vivid colour
    vec4 c3;         // its deep one
};

void main() {
    vec2 px = qt_TexCoord0 * res;
    float len = res.x - 2.0 * pad;
    float x = px.x - pad;
    float dy = px.y - res.y * 0.5;
    float head = len * frac;
    float inLine = step(0.0, x) * step(x, len);

    // the track, faint, and the played part over it
    float core = exp(-dy * dy / 0.5);
    float played = smoothstep(head + 0.6, head - 0.6, x) * inLine;
    float shimmer = 0.7 + 0.3 * sin(x * 0.45 - t * 7.0) * (0.5 + 0.5 * glow);
    float near = smoothstep(head - 30.0, head, x);           // brighter towards the head
    vec3 lc = mix(c3.rgb, mix(c1.rgb, vec3(1.0), 0.25), 0.35 + 0.65 * near);
    float la = core * played * (0.55 + 0.45 * near) * shimmer * (1.0 + 0.6 * kick);
    vec4 col = vec4(vec3(1.0) * core * 0.12 * inLine * (1.0 - played), core * 0.12 * inLine * (1.0 - played));
    col += vec4(lc * la, la);
    // a soft halo over the played part, lifting with each kick
    float halo = exp(-dy * dy / 4.0) * played * (0.15 + 0.35 * kick) * glow;
    col += vec4(c1.rgb * halo, halo);

    // the spark
    float r = 1.6 + 2.2 * bass * glow + 2.0 * kick;
    float d2 = (px.x - pad - head) * (px.x - pad - head) + dy * dy * 1.6;
    float spark = exp(-d2 / (r * r)) * (0.65 + 0.35 * glow);
    vec3 sc = mix(c1.rgb, vec3(1.0), 0.6 + 0.4 * exp(-d2 / 1.5));
    col = vec4(sc * spark, spark) + col * (1.0 - spark);

    fragColor = col * qt_Opacity;
}
