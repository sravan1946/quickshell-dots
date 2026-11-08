#version 440
// Light in an island's glass (islands/Isle.qml), drawn between its surface and its contents.
//  - Every island: each kick's wave (Visualizer's beat times, Settings' waveDur/waveReach) runs
//    out from the music across the whole bar like a comet along the island's lower edge: a
//    white-hot head blooming up off the floor, then a thin line in that kick's colour cooling
//    towards the cover's second colour.
//  - The island the music is in, under the media item (`eq`, x0..x1): an aurora curtain rising
//    off the floor, its hem the spectrum (cava stereo: bass under the middle, treble at the
//    ends), folds drifting and rays shimmering through it.
// Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    vec4 radii;      // corners: bottom-right, top-right, bottom-left, top-left
    float dpr;
    float ox;        // px: where the waves start, in this island's coordinates
    vec4 ages;       // the last four beats, newest in x: s since each
    vec4 punches;    // their strengths, 0..1
    float dur;       // the wave's run
    float reach;
    vec4 kr; vec4 kg; vec4 kb;   // each beat's colour, one channel per vec4
    vec2 eq;         // px: the media item's span (x1 <= x0: none here)
    vec4 cut;        // px: the span the card hangs from (x..y), z how far it's out, w the reach of its
                     // necks either side: no floor edge there, fading out across the necks
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
// one beat's light at a point d px from the origin, as (flash, afterglow). The front leaves the
// music fast and slows (an ease-out over `reach` px and `dur` s); as it passes, the point
// flashes (the comet's head, ~45 ms), then keeps a fainter line that fades over ~0.2 s, dark
// again before the next kick at most tempos.
vec2 hit(float d, float age, float punch) {
    float at = dur * (1.0 - pow(max(0.0, 1.0 - d / reach), 1.0 / 3.0));
    float dt = age - at;
    if (dt < -0.015) return vec2(0.0);
    float on = smoothstep(-0.015, 0.0, dt);   // a soft leading edge, not a step
    dt = max(dt, 0.0);
    return punch * on * vec2(exp(-dt / 0.045), 0.3 * exp(-dt / 0.22));
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float sd = sdBox(px - res * 0.5, res * 0.5, radii);
    float inside = clamp(0.5 - sd * dpr, 0.0, 1.0);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }
    float up = res.y - px.y;                       // px above the floor
    float low = smoothstep(res.y * 0.15, res.y, px.y);   // 0 at the top .. 1 at the floor
    vec4 col = vec4(0.0);                          // premultiplied

    // ---- the beat waves, on the lower glass edge ----
    float D = abs(px.x - ox);
    vec2 h0 = hit(D, ages.x, punches.x), h1 = hit(D, ages.y, punches.y), h2 = hit(D, ages.z, punches.z), h3 = hit(D, ages.w, punches.w);
    vec4 wt = vec4(h0.x + h0.y, h1.x + h1.y, h2.x + h2.y, h3.x + h3.y);
    float sum = wt.x + wt.y + wt.z + wt.w;
    float F = min(1.0, h0.x + h1.x + h2.x + h3.x);   // the heads passing here
    float A = min(1.0, h0.y + h1.y + h2.y + h3.y);   // the lines they've left
    // the head burns white; the line it leaves cools from the kick's colour towards the cover's second
    vec3 kc = vec3(dot(wt, kr), dot(wt, kg), dot(wt, kb)) / max(sum, 1e-4);
    vec3 lc = mix(kc, c2.rgb, 0.35 * A / (F + A + 1e-4));
    lc = clamp(mix(vec3(dot(lc, vec3(0.299, 0.587, 0.114))), lc, 1.6), 0.0, 1.0);   // the cover's pastels go muddy dim on the glass: more colour
    vec3 wc = mix(lc, vec3(1.0), 0.6 * F);
    if (sum > 0.002) {
        // under the card the floor is a seam inside the card's surface (goo.frag lights its outline)
        float under = cut.z * smoothstep(cut.x - cut.w - 1.0, cut.x, px.x) * smoothstep(cut.y + cut.w + 1.0, cut.y, px.x)
            * step(up, min(px.x, res.x - px.x));
        float edge = exp(-pow((sd + 0.8) * dpr, 2.0) / 1.4) * (0.25 + 0.75 * low) * (1.0 - under);
        float bloom = exp(-up / (2.5 + 5.0 * F)) * (1.0 - under);   // taller where the head is
        float a = (min(1.0, 0.9 * F + A) * 0.75 * edge + (0.45 * F + 0.12 * A) * bloom) * 0.85;
        col += vec4(wc * a, a);
    }

    // ---- the music, under the media item ----
    float span = eq.y - eq.x;
    if (span > 1.0 && px.x > eq.x && px.x < eq.y) {
        float u = (px.x - eq.x) / span;
        float ends = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
        col += aurora(u, px.x * 2.2, up, res.y * 0.95) * ends * (1.0 - col.a);
    }
    fragColor = col * inside * qt_Opacity;
}
