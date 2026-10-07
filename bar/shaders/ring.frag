#version 440
// Radial spectrum (components/Ring.qml, fed by Visualizer.qml). 32 cava levels arrive
// packed as l0..l7, their slow-falling peaks as p0..p7, stereo layout (left treble ..
// bass | bass .. right treble). Bass sits at the top, the left channel runs down the
// left side, the right channel down the right, trebles meet at the bottom.
// Draws rounded spokes out from `inner` (root c3 -> tip c1), a glow hugging them, a
// smooth ghost line on the peaks (c2) and a halo just inside the ring that swells with
// the bass. Quiet spokes shrink to dots, so silence is a ring of beads.
// Rebuild after editing: shaders/build.sh, then bump ?v= in components/Ring.qml
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    float inner;     // px: radius the spokes grow out from
    float amp;       // px: spoke length at full level
    float spokes;    // spoke count around the circle
    float thick;     // spoke width as a fraction of its slot (at `inner`)
    float halo;      // 0..1: glow, ghost line and bass halo strength
    float spin;      // turns: rotates the whole ring
    vec4 c1; vec4 c2; vec4 c3;
    vec4 l0; vec4 l1; vec4 l2; vec4 l3; vec4 l4; vec4 l5; vec4 l6; vec4 l7;
    vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6; vec4 p7;
};

const int N = 32;
const float TAU = 6.2831853;

// no dynamic array indexing: the GLSL ES 100 target can't do it
float lv(int i, bool peak) {
    i = clamp(i, 0, N - 1);
    int q = i / 4;
    vec4 v = peak
        ? (q == 0 ? p0 : q == 1 ? p1 : q == 2 ? p2 : q == 3 ? p3 : q == 4 ? p4 : q == 5 ? p5 : q == 6 ? p6 : p7)
        : (q == 0 ? l0 : q == 1 ? l1 : q == 2 ? l2 : q == 3 ? l3 : q == 4 ? l4 : q == 5 ? l5 : q == 6 ? l6 : l7);
    return dot(v, vec4(equal(ivec4(i - q * 4), ivec4(0, 1, 2, 3))));
}

// catmull-rom through the bands at x (0..1 across all 32), 0..1
float curve(float x, bool peak) {
    float f = clamp(x, 0.0, 1.0) * float(N - 1);
    int i = int(floor(f));
    float t = f - float(i);
    float a = lv(i - 1, peak), b = lv(i, peak), c = lv(i + 1, peak), d = lv(i + 2, peak);
    float v = b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a)));
    return pow(clamp(v, 0.0, 1.0), 1.2);
}

// angle in turns (0 = top, clockwise) -> position across the bands, bass at the top
float band(float t) { return fract(t + 0.5); }

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * res;
    float r = length(p);
    float t = fract(atan(p.x, -p.y) / TAU + spin);

    // spoke: a capsule along the radius of this angular slot
    float slot = t * spokes;
    float si = floor(slot);
    float lvl = curve(band((si + 0.5) / spokes), false);
    float hw = 0.5 * thick * TAU * inner / spokes;
    float r0 = inner + hw;
    float r1 = r0 + lvl * amp;
    float across = (slot - si - 0.5) / spokes * TAU * r;
    float ds = length(vec2(across, r - clamp(r, r0, r1))) - hw;
    float sa = smoothstep(0.75, -0.75, ds);
    float h = clamp((r - inner) / max(amp, 1.0), 0.0, 1.0);
    vec3 scol = min(mix(c3.rgb, c1.rgb, smoothstep(0.0, 0.8, h)) * (0.75 + 0.4 * lvl), vec3(1.0));

    // glow from the smooth (unslotted) curve, so it reads as one aura
    float lc = curve(band(t), false);
    float edge = r0 + lc * amp;
    float ga = halo * 0.4 * lc * exp(-max(r - edge, 0.0) / (2.0 + 0.12 * amp)) * smoothstep(inner - 2.0, inner + 2.0, r);

    // ghost line riding the peaks
    float pk = curve(band(t), true);
    float rp = r0 + hw + pk * amp + 2.0;
    float pa = halo * 0.6 * smoothstep(1.1, 0.2, abs(r - rp)) * smoothstep(0.03, 0.1, pk);

    // bass halo just inside the ring
    float bass = 0.5 * (lv(N / 2 - 1, false) + lv(N / 2, false));
    float ba = halo * 0.55 * bass * exp(-abs(r - inner + 5.0) / 5.0);

    // back to front, premultiplied "over"
    vec4 c = vec4(c1.rgb * ba, ba);
    c = vec4(c2.rgb * ga, ga) + c * (1.0 - ga);
    c = vec4(c2.rgb * pa, pa) + c * (1.0 - pa);
    c = vec4(scol * sa, sa) + c * (1.0 - sa);
    fragColor = c * qt_Opacity;
}
