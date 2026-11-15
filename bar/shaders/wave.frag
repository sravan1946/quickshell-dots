#version 440
// Each kick's wave (islands/Wave.qml), drawn over everything in the bar: the islands, their
// contents, the card and its panel. It lights one outline, the three islands plus the card
// merged with the island it hangs from (the same smooth minimum as goo.frag), so the light
// runs along the whole bar and, where the card hangs, down its sides and along its foot.
// How far the light has come is measured ALONG that outline: across the bar from the music
// (`ox`) until it meets the card, then round the card's edge from the neck nearer the music all
// the way to the far one, and only then on along the bar past it: the card holds it up by the
// way round it, never back over the card. (The island's floor between the necks is inside the
// card's surface: no way across.) A card hanging from right under the music sends it out from both necks: the two
// fronts go round it each way, through each other, and each carries on along the bar from the
// neck it comes up at.
// The item is a window onto the bar (`org`: where it sits in the bar's coordinates), so one
// strip over the islands and one box round the card share this shader.
// Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    vec2 org;        // item position in the bar's coordinates
    float dpr;
    float yb;        // the islands' floor (they all share it)
    vec4 i0; vec4 i1; vec4 i2;   // islands: x, y, w, h
    vec4 r0; vec4 r1; vec4 r2;   // their corner radii: tl, tr, br, bl
    vec4 body;       // the card: x, y, w, h (h 0: no card)
    vec4 bodyR;      // its corner radii: tl, tr, br, bl
    float attach;    // which island it hangs from (0..2), -1 none
    float goo;       // the merge's reach, px
    float fL;        // 0 = card edge flush with the island's, 1 = clear of it
    float fR;
    float ox;        // px: where the waves start
    float v0;        // px/s it leaves the music at (Visualizer.arrive: the same model)
    float v1;        // px/s it slows to and keeps
    float bend;      // px over which it slows
    float fade;      // px over which it dims to 1/e (0: never)
    float head;      // px: the head's length
    float tail;      // s: the line it leaves fades over this
    vec4 ages; vec4 ages2;         // the last eight beats, newest first: s since each
    vec4 punches; vec4 punches2;   // their strengths, 0..1
    vec4 kr; vec4 kg; vec4 kb;     // their colours, one channel per vec4
    vec4 kr2; vec4 kg2; vec4 kb2;
    vec4 c2;         // the cover's second colour: where the lines cool to
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

// The pulse (Visualizer.arrive, the beatglow plugin's shader: keep the three alike). Its speed d
// px along is v1 + (v0 - v1) e^(-d/bend): it leaves the music fast and settles to v1, so
// arrival is closed-form at any distance and zero at the music.
float arrive(float d) {
    return (d + bend * log((v1 + (v0 - v1) * exp(-d / bend)) / v0)) / v1;
}
float speed(float d) { return v1 + (v0 - v1) * exp(-d / bend); }

// one beat at a point d px along, its age and strength: the head is `head` px long behind the
// front whatever the speed (px behind = time since the front passed x the speed there), with a
// soft leading edge; it leaves a fainter line that fades over `tail` s; the whole pulse dims with
// the distance it has come. Adds (flash, line) to fa and its colour, weighted, to col.
void beat(float d, float age, float punch, float r, float g, float b, inout vec2 fa, inout vec4 col) {
    if (punch <= 0.0) return;
    float dt = age - arrive(d);
    float px = dt * speed(d);                    // px behind the front (< 0: ahead of it)
    if (px < -6.0) return;
    float amp = punch * smoothstep(-6.0, 0.0, px) * (fade > 0.0 ? exp(-d / fade) : 1.0);
    vec2 h = amp * vec2(exp(-max(px, 0.0) / head), 0.3 * exp(-max(dt, 0.0) / tail));
    fa += h;
    col += vec4(r, g, b, 1.0) * (h.x + h.y);
}
void beats(float d, inout vec2 fa, inout vec4 col) {
    beat(d, ages.x, punches.x, kr.x, kg.x, kb.x, fa, col);
    beat(d, ages.y, punches.y, kr.y, kg.y, kb.y, fa, col);
    beat(d, ages.z, punches.z, kr.z, kg.z, kb.z, fa, col);
    beat(d, ages.w, punches.w, kr.w, kg.w, kb.w, fa, col);
    beat(d, ages2.x, punches2.x, kr2.x, kg2.x, kb2.x, fa, col);
    beat(d, ages2.y, punches2.y, kr2.y, kg2.y, kb2.y, fa, col);
    beat(d, ages2.z, punches2.z, kr2.z, kg2.z, kb2.z, fa, col);
    beat(d, ages2.w, punches2.w, kr2.w, kg2.w, kb2.w, fa, col);
}

// the card's outline from neck to neck: down a side, round a corner, along the foot, round, up
float cardLen() {
    float R = min(min(bodyR.z, bodyR.w), 0.5 * min(body.z, body.w));
    return 2.0 * max(body.w - R, 0.0) + 3.1415927 * R + max(body.z - 2.0 * R, 0.0);
}

// px along the card's outline from its left neck: down the left side, round the corner, along
// the foot, up the right side; P its whole length. Points off the outline take the nearest part.
float alongCard(vec2 p, out float P) {
    vec2 q = p - body.xy;
    float w = body.z, h = body.w;
    float R = min(min(bodyR.z, bodyR.w), 0.5 * min(w, h));
    float a = max(h - R, 0.0), c = 1.5707963 * R, f = max(w - 2.0 * R, 0.0);
    P = 2.0 * a + 2.0 * c + f;
    if (q.y > h - R && q.x < R) {
        vec2 v = q - vec2(R, h - R);
        return a + R * clamp(atan(v.y, -v.x), 0.0, 1.5707963);
    }
    if (q.y > h - R && q.x > w - R) {
        vec2 v = q - vec2(w - R, h - R);
        return P - a - R * clamp(atan(v.y, v.x), 0.0, 1.5707963);
    }
    float dl = q.x, dr = w - q.x, df = h - q.y;
    if (df < min(dl, dr)) return a + c + clamp(q.x - R, 0.0, f);
    return dl < dr ? clamp(q.y, 0.0, a) : P - clamp(q.y, 0.0, a);
}

void main() {
    vec2 p = org + qt_TexCoord0 * res;
    bool card = attach >= 0.0 && body.w > 0.5;

    // ---- how far along the outline this point is from the music ----
    float D = abs(p.x - ox), D2 = -1.0;   // D2: a second front (round the card the other way)
    if (card) {
        float x0 = body.x, x1 = body.x + body.z;
        if (p.y > yb) {
            float P;
            float s = alongCard(p, P);
            float fromL = abs(x0 - ox) + s, fromR = abs(x1 - ox) + P - s;
            D = ox < x0 ? fromL : ox > x1 ? fromR : fromL;
            if (ox >= x0 && ox <= x1) D2 = fromR;
        }
        // the bar from the card on, away from the music: dark over the card (the light has gone
        // down into it), and past it only once the light has been round, on from the far neck
        else if (ox < x0 && p.x > x0) D = p.x > x1 ? x0 - ox + cardLen() + p.x - x1 : 1e6;
        else if (ox > x1 && p.x < x1) D = p.x < x0 ? ox - x1 + cardLen() + x0 - p.x : 1e6;
        else if (p.x > x1) D = ox - x0 + cardLen() + p.x - x1;   // music over the card: each front
        else if (p.x < x0) D = x1 - ox + cardLen() + x0 - p.x;   // comes up at the far neck
    }
    vec2 fa = vec2(0.0);
    vec4 kcol = vec4(0.0);   // the beats' colours, weighted by how much each lights here
    beats(D, fa, kcol);
    if (D2 >= 0.0) beats(D2, fa, kcol);
    if (kcol.a < 0.002) { fragColor = vec4(0.0); return; }

    // ---- the outline: islands, the card merged into its own ----
    float d0 = box(p, i0, r0), d1 = box(p, i1, r1), d2 = box(p, i2, r2);
    // the glow inwards (bloom) goes by the real edges only: where the card hangs, the island's
    // floor is a seam inside the one surface, and measuring from it drew a band along it
    float dB = 1e3;
    if (card && p.x > body.x && p.x < body.x + body.z) {
        vec4 iA = attach < 0.5 ? i0 : attach < 1.5 ? i1 : i2;
        vec4 rA = attach < 0.5 ? r0 : attach < 1.5 ? r1 : r2;
        dB = p.y > yb ? box(p, vec4(body.x, body.y - 40.0, body.z, body.w + 40.0), vec4(0.0, 0.0, bodyR.z, bodyR.w))
                      : box(p, vec4(iA.x, iA.y, iA.z, iA.w + 40.0), vec4(rA.x, rA.y, 0.0, 0.0));
    }
    if (card) {
        float b = box(p, body, bodyR);
        float gl = mix(fL, 1.0, clamp(abs(p.x - body.x) / goo, 0.0, 1.0));
        float gr = mix(fR, 1.0, clamp(abs(p.x - body.x - body.z) / goo, 0.0, 1.0));
        float k = max(goo * min(gl, gr), 0.001);
        if (attach < 0.5) d0 = smin(d0, b, k);
        else if (attach < 1.5) d1 = smin(d1, b, k);
        else d2 = smin(d2, b, k);
    }
    float d = min(d0, min(d1, d2));
    float inside = clamp(0.5 - d * dpr, 0.0, 1.0);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }

    float F = min(1.0, fa.x);   // the heads passing here
    float A = min(1.0, fa.y);   // the lines they've left
    // the head burns white; the line it leaves cools from the kick's colour towards the cover's second
    vec3 kc = kcol.rgb / kcol.a;
    vec3 lc = mix(kc, c2.rgb, 0.35 * A / (F + A + 1e-4));
    lc = clamp(mix(vec3(dot(lc, vec3(0.299, 0.587, 0.114))), lc, 1.6), 0.0, 1.0);   // the cover's pastels go muddy dim on the glass: more colour
    vec3 wc = mix(lc, vec3(1.0), 0.6 * F);

    // the islands catch it most along their floor; the card all round
    float low = p.y > yb ? 1.0 : smoothstep(i0.y + 0.15 * (yb - i0.y), yb, p.y);
    float edge = exp(-pow((d + 0.8) * dpr, 2.0) / 1.4);
    float bloom = exp(min(dB < 1e3 ? dB : d, 0.0) / (2.5 + 5.0 * F));   // inwards from the outline, deeper at the head
    float a = (min(1.0, 0.9 * F + A) * 0.75 * edge + (0.45 * F + 0.12 * A) * bloom) * (0.25 + 0.75 * low) * 0.85;
    fragColor = vec4(wc * a, a) * inside * qt_Opacity;
}
