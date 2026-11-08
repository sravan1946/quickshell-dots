#version 440
// The card's surface as one liquid with the island it hangs from: the two rounded boxes are
// merged with a smooth minimum, so wherever they come close a neck of surface pulls between
// them (`goo` px of reach; ~18 reads as a fillet, 30+ as a stretched drop). The island is
// drawn by the island itself, so this draws the merged shape minus the island, and the two
// meet along the island's straight bottom edge, which sits on the pixel grid. Where a card
// edge runs flush with the island's (fL/fR near 0) the merge is turned off along that line:
// a smooth minimum of two collinear edges would bulge out at the seam.
// Its outline catches each kick's wave as the islands' edges do (shaders/isle.frag), the wave
// running on from the island's floor down the card's sides and along its foot.
// Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 body;        // x, y, w, h in item px
    vec4 bodyR;       // corner radii: tl, tr, br, bl
    vec4 isle;
    vec4 isleR;
    vec4 fill;        // rgb, a
    vec2 res;         // item size in px
    float goo;
    float dpr;
    float fL;         // 0 = the card's left edge is flush with the island's, 1 = clear of it
    float fR;
    float ox;         // px: where the waves start, in this item's coordinates
    vec4 ages;        // the last four beats, newest in x: s since each
    vec4 punches;     // their strengths, 0..1
    float dur;        // the wave's run
    float reach;
    vec4 kr; vec4 kg; vec4 kb;   // each beat's colour, one channel per vec4
    vec4 c2;          // the cover's second colour: where the lines cool to
};

float box(vec2 p, vec4 b, vec4 r) {
    vec2 h = b.zw * 0.5;
    p -= b.xy + h;
    float rr = p.x > 0.0 ? (p.y > 0.0 ? r.z : r.y) : (p.y > 0.0 ? r.w : r.x);
    rr = min(rr, min(h.x, h.y));
    vec2 q = abs(p) - h + rr;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr;
}

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// as in isle.frag: one beat's (flash, afterglow) at a point d px from the origin
vec2 hit(float d, float age, float punch) {
    float at = dur * (1.0 - pow(max(0.0, 1.0 - d / reach), 1.0 / 3.0));
    float dt = age - at;
    if (dt < -0.015) return vec2(0.0);
    float on = smoothstep(-0.015, 0.0, dt);   // a soft leading edge, not a step
    dt = max(dt, 0.0);
    return punch * on * vec2(exp(-dt / 0.045), 0.3 * exp(-dt / 0.22));
}

void main() {
    vec2 p = qt_TexCoord0 * res;
    float i = box(p, isle, isleR);
    float gl = mix(fL, 1.0, clamp(abs(p.x - body.x) / goo, 0.0, 1.0));
    float gr = mix(fR, 1.0, clamp(abs(p.x - body.x - body.z) / goo, 0.0, 1.0));
    float d = body.w > 0.01 ? smin(i, box(p, body, bodyR), max(goo * min(gl, gr), 0.001)) : i;
    float cov = max(clamp(0.5 - d * dpr, 0.0, 1.0) - clamp(0.5 - i * dpr, 0.0, 1.0), 0.0);
    vec4 col = vec4(fill.rgb, 1.0) * fill.a;

    // the beat waves on the outline: across the bar to here, then down from the island's floor
    float D = abs(p.x - ox) + max(0.0, p.y - isle.y - isle.w);
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
        float edge = exp(-pow((d + 0.8) * dpr, 2.0) / 1.4);
        float halo = exp(min(d, 0.0) / (2.0 + 4.0 * F));   // inwards from the outline, deeper at the head
        float ga = (min(1.0, 0.9 * F + A) * 0.7 * edge + 0.3 * F * halo) * 0.85;
        col = vec4(wc * ga, ga) + col * (1.0 - ga);
    }
    fragColor = col * cov * qt_Opacity;
}
