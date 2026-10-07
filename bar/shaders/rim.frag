#version 440
// Beat light on a bar pill's rim (components/Pill.qml): as each beat wave (Visualizer's
// waveFronts) runs along the bar, the rim lights up where it passes, a flash then an
// afterglow, so the light sweeps across the pill and the whole rim stays lit for a moment
// after (the wave itself crosses a pill in a few ms). A faint glow inside. Up to four at once.
// Rebuild after editing: shaders/build.sh, then bump ?v= in components/Pill.qml
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    vec4 radii;      // corner radii: bottom-right, top-right, bottom-left, top-left
    float ox;        // px: where the waves start, in this pill's coordinates
    vec4 ages;       // last four beats, newest in x: s since each
    vec4 punches;    // their strengths, 0..1
    float dur;       // the wave's run (Visualizer.waveDur, waveReach)
    float reach;
    vec4 c1;
};

// rounded box with per-corner radii (y down, so +y is the bottom)
float sdBox(vec2 p, vec2 b, vec4 r) {
    r.xy = p.x > 0.0 ? r.xy : r.zw;
    r.x = p.y > 0.0 ? r.x : r.y;
    vec2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

// how lit a point d px from the origin is, for one beat
float hit(float d, float age, float punch) {
    float at = dur * (1.0 - pow(max(0.0, 1.0 - d / reach), 1.0 / 3.0));   // when the front got here
    float dt = age - at;
    return dt < 0.0 ? 0.0 : punch * (0.6 * exp(-dt / 0.06) + 0.5 * exp(-dt / 0.4));
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float sd = sdBox(px - res * 0.5, res * 0.5, radii);
    float d = abs(px.x - ox);
    float h = min(1.0, hit(d, ages.x, punches.x) + hit(d, ages.y, punches.y)
                     + hit(d, ages.z, punches.z) + hit(d, ages.w, punches.w));
    float rim = smoothstep(1.5, 0.0, abs(sd + 0.75));
    float inner = exp(sd / 5.0) * step(sd, 0.0) * 0.18;
    float a = 0.65 * h * (rim * 0.85 + inner) * smoothstep(0.6, -0.6, sd);
    fragColor = vec4(mix(c1.rgb, vec3(1.0), 0.3 * h) * a, a) * qt_Opacity;
}
