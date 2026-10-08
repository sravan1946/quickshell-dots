#version 440
// Radial spectrum (components/Ring.qml, fed by Visualizer.qml). 32 cava levels arrive
// packed as l0..l7, their slow-falling peaks as p0..p7, stereo layout (left treble ..
// bass | bass .. right treble). Bass sits at the top, the left channel runs down the
// left side, the right channel down the right, trebles meet at the bottom.
// `style` picks how it's drawn; the default (0) is described below, the others at their branch.
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
    float style;     // Settings.panelStyle: 0 spokes, 1 aura, 2 liquid, 3 LED
    float time;      // s, Visualizer's frame clock (stops while paused)
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

vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * res;
    float r = length(p);
    float t = fract(atan(p.x, -p.y) / TAU + spin);
    float lc = curve(band(t), false);
    float bass = 0.5 * (lv(N / 2 - 1, false) + lv(N / 2, false));
    vec4 c = vec4(0.0);

    if (style < 0.5) {
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
        float edge = r0 + lc * amp;
        float ga = halo * 0.4 * lc * exp(-max(r - edge, 0.0) / (2.0 + 0.12 * amp)) * smoothstep(inner - 2.0, inner + 2.0, r);

        // ghost line riding the peaks
        float pk = curve(band(t), true);
        float rp = r0 + hw + pk * amp + 2.0;
        float pa = halo * 0.6 * smoothstep(1.1, 0.2, abs(r - rp)) * smoothstep(0.03, 0.1, pk);

        // bass halo just inside the ring
        float ba = halo * 0.55 * bass * exp(-abs(r - inner + 5.0) / 5.0);

        // back to front, premultiplied "over"
        c = vec4(c1.rgb * ba, ba);
        c = over(vec4(c2.rgb * ga, ga), c);
        c = over(vec4(c2.rgb * pa, pa), c);
        c = over(vec4(scol * sa, sa), c);
    } else if (style < 1.5) {
        // aura: a nebula ring. Eight soft clouds of the palette orbit just outside the
        // record, each swelling and brightening with its part of the spectrum, over a glow
        // that hugs the spectrum's curve; a slow shimmer of light runs round it and the
        // whole thing flares on the beat (halo)
        float ll = pow(lc, 0.55);
        float ga = halo * 0.5 * ll * exp(-max(r - inner, 0.0) / (8.0 + ll * amp * 0.7)) * smoothstep(inner - 4.0, inner + 2.0, r);
        c = vec4(c2.rgb * ga, ga);
        for (int i = 0; i < 8; i++) {
            float fi = float(i);
            float a = fi / 8.0 + time * 0.018 * (mod(fi, 2.0) < 0.5 ? 1.0 : -0.75) + 0.03 * sin(time * 0.4 + fi);
            float lb = pow(curve(band(fract(a)), false), 0.55);
            float R = inner + 12.0 + lb * amp * 0.55;
            vec2 bc = R * vec2(sin(a * TAU), -cos(a * TAU));
            float rad = 20.0 + lb * 34.0;
            float d2 = dot(p - bc, p - bc) / (rad * rad);
            vec3 col = mod(fi, 3.0) < 0.5 ? c1.rgb : mod(fi, 3.0) < 1.5 ? c2.rgb : c3.rgb;
            float ba = min(1.0, halo * exp(-d2 * 1.6) * (0.22 + 0.6 * lb)) * smoothstep(inner - 10.0, inner + 2.0, r);
            c = over(vec4(col * ba, ba), c);
        }
        float sh = pow(0.5 + 0.5 * cos((t - time * 0.08) * TAU * 3.0), 12.0);
        float sa = sh * 0.35 * ll * exp(-abs(r - (inner + 8.0 + ll * amp * 0.4)) / 6.0);
        c = over(vec4(mix(c1.rgb, vec3(1.0), 0.4) * sa, sa), c);
    } else if (style < 2.5) {
        // liquid: the spectrum as one smooth surface round the record: a gradient fill, a
        // bright contour (distance corrected for slope so it stays a hairline) with a dimmer
        // echo inside it, a wide halo outside, and the peaks' ghost line above
        float ll = pow(lc, 0.55);
        float r0 = inner + 2.0;
        float e = 0.002;
        float edge = r0 + ll * amp;
        float slope = (pow(curve(band(t + e), false), 0.55) - pow(curve(band(t - e), false), 0.55)) * amp / (2.0 * e * TAU * max(r, 1.0));
        float d = (r - edge) / sqrt(1.0 + slope * slope);
        float inside = smoothstep(0.6, -0.6, d) * smoothstep(inner - 1.0, inner + 1.0, r);
        float fa = halo * inside * (0.12 + 0.42 * clamp((r - r0) / max(edge - r0, 1.0), 0.0, 1.0));
        c = vec4(mix(c3.rgb, c2.rgb, ll) * fa, fa);
        float ha = halo * 0.45 * ll * exp(-max(d, 0.0) / 7.0) * step(0.0, d);
        c = over(vec4(c2.rgb * ha, ha), c);
        float echo = exp(-(d + 6.0) * (d + 6.0) / 0.8) * 0.35 * inside;
        c = over(vec4(c1.rgb * echo, echo), c);
        float ea = exp(-d * d / 0.9) * (0.65 + 0.35 * ll);
        c = over(vec4(mix(c1.rgb, vec3(1.0), 0.3 * ll) * ea, ea), c);
        float pk = pow(curve(band(t), true), 0.55);
        float pa = halo * 0.5 * smoothstep(1.0, 0.2, abs(r - (r0 + pk * amp + 4.0))) * smoothstep(0.03, 0.1, pk);
        c = over(vec4(c2.rgb * pa, pa), c);
    } else {
        // LED: each spoke a column of dots, lit up to its level like a hardware meter; the
        // top lit dot brightest, the rest of the column a faint unlit grid
        float n = floor(spokes * 0.5);
        float slot = t * n;
        float si = floor(slot);
        float lvl = curve(band((si + 0.5) / n), false);
        float hw = 0.5 * thick * TAU * inner / n * 0.8;
        float pitch = hw * 2.6;
        float r0 = inner + hw;
        float k = floor((r - r0) / pitch + 0.5);
        float kmax = floor(amp / pitch);
        float lit = floor(lvl * kmax + 0.5);
        float across = (slot - si - 0.5) / n * TAU * r;
        float dd = length(vec2(across, r - (r0 + k * pitch))) - hw;
        float cov = smoothstep(0.6, -0.6, dd) * step(0.0, k) * step(k, kmax);
        float isLit = step(k, lit - 0.5) * step(0.03, lvl);
        float top = isLit * step(lit - 1.5, k);
        vec3 col = mix(mix(c3.rgb, c1.rgb, k / max(kmax, 1.0)), vec3(1.0), 0.35 * top);
        float a = cov * mix(0.07, 0.95, isLit);
        float ga = halo * 0.3 * lc * exp(-max(r - (r0 + lc * amp), 0.0) / 5.0) * smoothstep(inner - 2.0, inner + 2.0, r);
        c = vec4(c2.rgb * ga, ga);
        c = over(vec4(col * a, a), c);
    }
    fragColor = c * qt_Opacity;
}
