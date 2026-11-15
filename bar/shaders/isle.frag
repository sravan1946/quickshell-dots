#version 440
// Light in the glass of the island the music is in (islands/Isle.qml), drawn between its
// surface and its contents: under the media item (`eq`, x0..x1) an aurora curtain rising off
// the floor, its hem the spectrum (cava stereo: bass under the middle, treble at the ends),
// folds drifting and rays shimmering through it. (Each kick's wave is wave.frag's, over everything.)
// Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    vec4 radii;      // corners: bottom-right, top-right, bottom-left, top-left
    float dpr;
    vec2 eq;         // px: the media item's span (x1 <= x0: none here)
    float t;         // s, the frame clock (the folds and rays drift with it)
    float glow;      // 1 playing, 0 paused
    vec4 c1;         // the cover's vivid colour: the tops of the light, the played line
    vec4 c2;         // a second cover colour: where the curtain folds
    vec4 c3;         // its deep one: the floor
    vec4 l0; vec4 l1; vec4 l2; vec4 l3; vec4 l4; vec4 l5; vec4 l6; vec4 l7;
    vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6; vec4 p7;   // each band's recent peak
};

float sdBox(vec2 p, vec2 b, vec4 r) {
    r.xy = p.x > 0.0 ? r.xy : r.zw;
    r.x = p.y > 0.0 ? r.x : r.y;
    vec2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}
// no dynamic array indexing: the GLSL ES 100 target can't do it
float pick(int i, vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h) {
    int q = i / 4;
    vec4 v = q == 0 ? a : q == 1 ? b : q == 2 ? c : q == 3 ? d : q == 4 ? e : q == 5 ? f : q == 6 ? g : h;
    return dot(v, vec4(equal(ivec4(i - q * 4), ivec4(0, 1, 2, 3))));
}
// band i, mostly against its own recent peak: raw, the bass dwarfs everything and the treble
// out at the ends barely lifts; this way every band moves to its own music
float lv(int i) {
    i = clamp(i, 0, 31);
    float v = pick(i, l0, l1, l2, l3, l4, l5, l6, l7);
    float p = pick(i, p0, p1, p2, p3, p4, p5, p6, p7);
    return mix(v, v / max(p, 0.12), 0.7);
}
// smooth through the bands (Catmull-Rom); x 0..1 across the stereo layout
float spec(float x) {
    float f = clamp(x, 0.0, 1.0) * 31.0;
    int i = int(floor(f));
    float s = f - float(i);
    float a = lv(i - 1), b = lv(i), c = lv(i + 1), d = lv(i + 2);
    return clamp(b + 0.5 * s * (c - a + s * (2.0 * a - 5.0 * b + 4.0 * c - d + s * (3.0 * (b - c) + d - a))), 0.0, 1.0);
}
// the aurora: a curtain whose hem follows the spectrum, folds drifting along it, fine rays
// shimmering up from a bright base. u 0..1 across, x px (for the rays), up px above the floor,
// H the room it may rise into. Premultiplied.
vec4 aurora(float u, float x, float up, float H) {
    float v = (spec(u - 0.02) + 2.0 * spec(u) + spec(u + 0.02)) * 0.25 * glow;
    float fold = 0.5 + 0.3 * sin(u * 7.0 + t * 0.9) + 0.2 * sin(u * 17.0 - t * 1.7);
    float h = H * (0.2 + 0.8 * v) * (0.7 + 0.6 * fold);
    float y = up / max(h, 1.0);
    float bend = 3.0 * sin(u * 5.0 + t * 0.6);
    float ray = 0.5 + 0.5 * sin(x * 0.55 + bend + t * 2.0) * (0.6 + 0.4 * sin(x * 0.21 - t * 1.3));
    float body = smoothstep(1.0, 0.0, y) * (0.35 + 0.65 * ray) * (1.0 - 0.5 * y);
    float base = exp(-up / (1.5 + 2.0 * v));
    float a = (0.2 + 0.8 * v) * glow * (0.8 * body + 0.9 * base);
    vec3 lo = mix(c1.rgb, vec3(1.0), 0.35 + 0.4 * base);
    vec3 hi = mix(c1.rgb, c2.rgb, 0.4 + 0.4 * fold);
    vec3 c = mix(lo, mix(hi, c3.rgb, smoothstep(0.5, 1.0, y)), smoothstep(0.0, 0.45, y));
    return vec4(c * a, a);
}
void main() {
    vec2 px = qt_TexCoord0 * res;
    float sd = sdBox(px - res * 0.5, res * 0.5, radii);
    float inside = clamp(0.5 - sd * dpr, 0.0, 1.0);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }
    float up = res.y - px.y;                       // px above the floor
    vec4 col = vec4(0.0);                          // premultiplied

    // ---- the music, under the media item ----
    float span = eq.y - eq.x;
    if (span > 1.0 && px.x > eq.x && px.x < eq.y) {
        float u = (px.x - eq.x) / span;
        float ends = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
        col += aurora(u, px.x * 2.2, up, res.y * 0.95) * ends * (1.0 - col.a);
    }
    fragColor = col * inside * qt_Opacity;
}
