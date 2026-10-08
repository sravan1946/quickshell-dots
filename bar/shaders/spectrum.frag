#version 440
// Straight spectrum (components/Spectrum.qml, fed by Visualizer.qml) for the Now Playing
// panel's layouts other than the turntable. 32 cava levels arrive packed as l0..l7, their
// slow-falling peaks as p0..p7, stereo layout (left treble .. bass | bass .. right treble),
// so every style is mirrored about the middle with the bass there. `style`:
//   0 poster bars: capsules rising from the floor, laid over the bottom of the cover art
//   1 waveform: bars standing on a baseline over their own reflection, the played part
//     (frac) lit and glowing, a playhead where it meets the rest
//   2 matrix: an LED panel lit up to each column's level, cool at the floor and white-hot
//     at the top, with a peak LED riding above
//   3 aurora: curtains of light swaying over a mountain ridge under twinkling stars
// Rebuild after editing: shaders/build.sh, then bump ?v= in components/Spectrum.qml
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    float style;
    float frac;      // track progress 0..1 (waveform)
    float time;      // s, Visualizer's frame clock (stops while paused)
    float glow;      // 0..1, overall strength (sinks while paused)
    float kick;      // 0..1, the latest beat, easing off
    vec4 c1; vec4 c2; vec4 c3;
    vec4 l0; vec4 l1; vec4 l2; vec4 l3; vec4 l4; vec4 l5; vec4 l6; vec4 l7;
    vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6; vec4 p7;
};

const int N = 32;

// no dynamic array indexing: the GLSL ES 100 target can't do it
float lv(int i, bool peak) {
    i = clamp(i, 0, N - 1);
    int q = i / 4;
    vec4 v = peak
        ? (q == 0 ? p0 : q == 1 ? p1 : q == 2 ? p2 : q == 3 ? p3 : q == 4 ? p4 : q == 5 ? p5 : q == 6 ? p6 : p7)
        : (q == 0 ? l0 : q == 1 ? l1 : q == 2 ? l2 : q == 3 ? l3 : q == 4 ? l4 : q == 5 ? l5 : q == 6 ? l6 : l7);
    return dot(v, vec4(equal(ivec4(i - q * 4), ivec4(0, 1, 2, 3))));
}

// catmull-rom through the bands at x (0..1 across all 32), 0..1; the power lifts the
// mids and highs, which cava reports low (~0.1-0.15 typical against ~0.4 for bass)
float curve(float x, bool peak) {
    float f = clamp(x, 0.0, 1.0) * float(N - 1);
    int i = int(floor(f));
    float t = f - float(i);
    float a = lv(i - 1, peak), b = lv(i, peak), c = lv(i + 1, peak), d = lv(i + 2, peak);
    float v = b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a)));
    return pow(clamp(v, 0.0, 1.0), 0.6);
}

vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float y = res.y - px.y;   // px above the bottom
    float u = px.x / res.x;
    vec4 c = vec4(0.0);
    float lift = 0.35 + 0.65 * glow;

    if (style < 0.5) {
        // poster bars: a soft glow following the curve, capsules over it, lit tips
        float lc = curve(u, false);
        float ga = 0.5 * lc * exp(-y / (8.0 + lc * res.y * 0.5)) * lift;
        c = vec4(c2.rgb * ga, ga);
        float pitch = res.x / 44.0;
        float ci = floor(px.x / pitch);
        float cx = (ci + 0.5) * pitch;
        float lvl = curve(cx / res.x, false);
        float br = pitch * 0.28;
        float y0 = 10.0 + br;
        float y1 = y0 + lvl * (res.y - y0 - br - 6.0);
        float dc = length(vec2(px.x - cx, y - clamp(y, y0, y1))) - br;
        float rise = clamp((y - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
        float a = smoothstep(0.6, -0.6, dc) * (0.55 + 0.45 * lvl) * lift * smoothstep(0.02, 0.06, lvl);
        vec3 col = mix(mix(c3.rgb, c1.rgb, rise), vec3(1.0), 0.35 * exp(-(y1 - y) / 2.0) * lvl);
        c = over(vec4(col * a, a), c);
    } else if (style < 1.5) {
        // waveform: rounded bars standing on a baseline, a dim reflection under it; the
        // played part in the palette (whitening at the tips) over a glow, the rest a quiet
        // grey, a glowing playhead between them
        float pitch = 4.0;
        float ci = floor(px.x / pitch);
        float cx = (ci + 0.5) * pitch;
        float lvl = curve(cx / res.x, false);
        float r = 1.3;
        float base = res.y * 0.64;
        float yy = px.y - base;   // + below the baseline
        float up = r + 0.5 + lvl * (base - 8.0) * (1.0 + 0.15 * kick);
        float dn = r + 0.5 + lvl * (res.y - base - 6.0) * 0.85;
        float dx = px.x - cx;
        float dT = length(vec2(dx, yy - clamp(yy, -up + r, -r))) - r;
        float dR = length(vec2(dx, yy - clamp(yy, 1.5 + r, 1.5 + dn - r))) - r;
        float played = step(cx / res.x, frac);
        float h = clamp(-yy / max(up, 1.0), 0.0, 1.0);
        vec3 on = mix(mix(c3.rgb, c1.rgb, 0.3 + 0.7 * h), vec3(1.0), 0.35 * h * h * lvl);
        vec3 col = mix(mix(vec3(0.62), c3.rgb, 0.25), on, played);
        float g = played * 0.3 * lvl * exp(-max(dT, 0.0) / 6.0) * lift * step(yy, 0.0);
        c = vec4(c2.rgb * g, g);
        float aR = smoothstep(0.6, -0.6, dR) * mix(0.1, 0.3 * lift, played) * (1.0 - clamp((yy - 1.5) / max(dn, 1.0), 0.0, 1.0));
        c = over(vec4(col * aR, aR), c);
        float aT = smoothstep(0.6, -0.6, dT) * mix(0.32, 0.95 * lift, played);
        c = over(vec4(col * aT, aT), c);
        float bl = exp(-yy * yy / 0.4) * 0.12;
        c = over(vec4(vec3(1.0) * bl, bl), c);
        float ph = exp(-pow((u - frac) * res.x / 1.0, 2.0)) * smoothstep(-base, -base + 10.0, yy) * smoothstep(res.y - base, res.y - base - 10.0, yy) * 0.85;
        float phg = exp(-abs((u - frac) * res.x) / 5.0) * 0.25 * smoothstep(res.y * 0.5, 0.0, abs(yy));
        c = over(vec4(c1.rgb * phg, phg), c);
        c = over(vec4(vec3(1.0) * ph, ph), c);
    } else if (style < 2.5) {
        // matrix: an LED panel behind glass. Rounded-square LEDs lit to each column's level,
        // a heat ramp c3 -> c2 -> c1 up the rows with the top lit LED white-hot, a peak LED
        // riding above, bloom that kicks on the beat, faint scanlines and a glass sheen
        float dP = sdBox(px - res * 0.5, res * 0.5, 10.0);
        float pa = smoothstep(0.6, -0.6, dP) * 0.3;
        c = vec4(0.0, 0.0, 0.0, 1.0) * pa;
        float cols = 26.0, rows = 13.0;
        vec2 inset = vec2(6.0, 6.0);
        vec2 sz = res - 2.0 * inset;
        vec2 q = vec2(px.x - inset.x, y - inset.y);
        vec2 cell = sz / vec2(cols, rows);
        vec2 ij = floor(q / cell);
        vec2 lp = q - (ij + 0.5) * cell;
        float inGrid = step(0.0, ij.x) * step(ij.x, cols - 1.0) * step(0.0, ij.y) * step(ij.y, rows - 1.0);
        float lvl = curve((ij.x + 0.5) / cols, false);
        float pk = curve((ij.x + 0.5) / cols, true);
        float lit = floor(lvl * rows + 0.5);
        float pr = min(rows - 1.0, floor(pk * rows + 0.5));
        float d = sdBox(lp, cell * 0.37, min(cell.x, cell.y) * 0.18);
        float led = smoothstep(0.6, -0.6, d) * inGrid;
        float on = step(ij.y, lit - 1.0);
        float isPeak = step(abs(ij.y - pr), 0.5) * step(lit, pr) * step(0.04, pk);
        float h = ij.y / (rows - 1.0);
        vec3 heat = h < 0.5 ? mix(c3.rgb, c2.rgb, h * 2.0) : mix(c2.rgb, c1.rgb, h * 2.0 - 1.0);
        float top = on * step(lit - 1.5, ij.y);
        vec3 col = mix(heat, vec3(1.0), 0.45 * top);
        col = mix(col, mix(c1.rgb, vec3(1.0), 0.6), isPeak);
        float bloom = max(on, isPeak) * inGrid * (0.35 + 0.35 * kick) * lift * exp(-max(d, 0.0) / 4.0);
        c = over(vec4(col * bloom, bloom), c);
        float a = led * max(mix(0.05, 0.95 * lift, on), 0.95 * lift * isPeak);
        c = over(vec4(col * a, a), c);
        float scan = (0.5 + 0.5 * sin(px.y * 3.14159)) * 0.04 * smoothstep(0.6, -0.6, dP);
        c = over(vec4(0.0, 0.0, 0.0, scan), c);
        float sheen = smoothstep(res.y * 0.5, 0.0, px.y) * 0.05 * smoothstep(0.6, -0.6, dP);
        c = over(vec4(vec3(1.0) * sheen, sheen), c);
    } else {
        // aurora: stars twinkling overhead (brighter with the treble), four curtains of light
        // swaying above a mountain ridge, rising and brightening with the music, a glow
        // along the horizon, and two ridges in front, the far one hazed
        float treble = 0.5 * (curve(0.04, false) + curve(0.96, false));
        vec2 g = floor(px / 7.0);
        float hs = hash(g);
        vec2 sp = (g + 0.2 + 0.6 * vec2(hash(g + 1.7), hash(g + 3.1))) * 7.0;
        float tw = 0.5 + 0.5 * sin(time * (1.5 + 2.0 * hs) + hs * 40.0);
        float st = step(0.93, hs) * smoothstep(1.2, 0.3, length(px - sp)) * tw * (0.35 + 0.65 * treble)
                 * smoothstep(res.y * 0.75, res.y * 0.2, px.y) * (0.4 + 0.6 * glow);
        c = vec4(vec3(1.0) * st, st);
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float lc = curve(fract(u + fk * 0.13), false);
            float base = res.y * (0.36 + 0.11 * fk)
                       + sin(px.x * 0.018 + time * (0.45 + 0.1 * fk) + fk * 1.9) * 12.0
                       + sin(px.x * 0.041 - time * 0.3 + fk) * 5.0;
            float above = y - base;
            float tall = 18.0 + lc * res.y * 0.5 * (1.0 + 0.3 * kick);
            float curtain = above > 0.0 ? exp(-above / tall) : exp(-above * above / 10.0);
            float rays = 0.55 + 0.45 * sin(px.x * 0.16 + time * (0.9 + 0.3 * fk) + fk * 3.0);
            vec3 col = mix(k == 0 ? c3.rgb : k == 1 ? c2.rgb : k == 2 ? c1.rgb : mix(c1.rgb, vec3(1.0), 0.3), vec3(1.0), 0.15);
            float a = min(1.0, curtain * rays * (0.3 + 0.9 * lc) * lift) * smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
            c = over(vec4(col * a, a), c);
        }
        float bass = curve(0.5, false);
        float far = res.y * 0.25 + 10.0 * sin(px.x * 0.017 + 1.3) + 6.0 * sin(px.x * 0.043 + 0.4) + 2.5 * sin(px.x * 0.11);
        float near = res.y * 0.14 + 9.0 * sin(px.x * 0.023 + 2.1) + 4.0 * sin(px.x * 0.071 + 1.0) + 2.0 * sin(px.x * 0.17 + 0.3);
        float hz = exp(-max(y - far, 0.0) / 10.0) * step(far, y) * 0.3 * (0.4 + 0.6 * bass) * lift;
        c = over(vec4(c2.rgb * hz, hz), c);
        float fa = smoothstep(0.8, -0.8, y - far) * 0.85;
        c = over(vec4(mix(vec3(0.05, 0.06, 0.09), c3.rgb, 0.18) * fa, fa), c);
        float na = smoothstep(0.8, -0.8, y - near) * 0.97;
        c = over(vec4(vec3(0.03, 0.035, 0.05) * na, na), c);
    }
    fragColor = c * qt_Opacity;
}
