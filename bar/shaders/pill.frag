#version 440
// Media pill backdrop (modules/Media.qml, fed by Visualizer.qml): an EQ seen through
// frosted glass. Soft columns of light rise from the floor, bass in the middle and trebles
// at both ends (cava stereo), over a diffuse glow that follows the same curve, so there
// are no hard edges for the title to fight. A glass highlight along the top, the track
// progress as a hairline with a glowing head along the bottom, and on each beat a light
// that runs round the rim from the bottom centre, where the bass sits. Up to four run at
// once, so quick kicks chase each other round instead of restarting one another. Masked to the pill's rounded shape.
// Rebuild after editing: shaders/build.sh, then bump ?v= in modules/Media.qml
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    float radius;    // pill corner radius, px
    float pitch;     // column spacing, px
    float frac;      // track progress 0..1
    vec2 textSpan;   // px: where the title/artist run, dimmed behind for contrast
    vec4 sweeps;     // last four beats, newest in x: 0..1 since each (1 = spent)
    vec4 punches;    // their strengths, 0..1
    float glow;      // 0..1, overall strength (dims while paused)
    vec4 bg;         // pill colour
    vec4 c1; vec4 c2; vec4 c3;
    vec4 l0; vec4 l1; vec4 l2; vec4 l3; vec4 l4; vec4 l5; vec4 l6; vec4 l7;
};

const int N = 32;

// no dynamic array indexing: the GLSL ES 100 target can't do it
float lv(int i) {
    i = clamp(i, 0, N - 1);
    int q = i / 4;
    vec4 v = q == 0 ? l0 : q == 1 ? l1 : q == 2 ? l2 : q == 3 ? l3 : q == 4 ? l4 : q == 5 ? l5 : q == 6 ? l6 : l7;
    return dot(v, vec4(equal(ivec4(i - q * 4), ivec4(0, 1, 2, 3))));
}

// catmull-rom through the bands at x (0..1 across all 32), 0..1
float curve(float x) {
    float f = clamp(x, 0.0, 1.0) * float(N - 1);
    int i = int(floor(f));
    float t = f - float(i);
    float a = lv(i - 1), b = lv(i), c = lv(i + 1), d = lv(i + 2);
    float v = b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a)));
    return pow(clamp(v, 0.0, 1.0), 0.8);   // <1 lifts mids and highs, which cava reports low
}

float sdBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }

// one beat light at path position s: a bright head with a fading tail, dimming as it runs.
// s = path length from the bottom centre (0 there, 1 at the ends, 2 at the top centre).
// Returns (alpha, head) so the caller can whiten the heads.
vec2 beam(float s, float sweep, float punch) {
    float front = sweep * 2.3;
    float head = exp(-pow((s - front) / 0.16, 2.0));
    float tail = step(s, front) * smoothstep(front - 0.9, front, s) * 0.45;
    float a = punch * (1.0 - sweep) * min(1.0, head + tail);
    return vec2(a, head * punch * (1.0 - sweep));
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float y = res.y - px.y;   // px above the bottom
    float sd = sdBox(px - res * 0.5, res * 0.5, radius);
    float mask = smoothstep(0.6, -0.6, sd);
    float H = res.y - 4.0;

    // spectrum spans the straight part of the pill, fading into the rounded ends
    float x = (px.x - radius * 0.5) / (res.x - radius);
    float ends = smoothstep(0.0, 0.08, x) * smoothstep(1.0, 0.92, x);

    vec4 c = vec4(bg.rgb, 1.0) * bg.a;

    // diffuse glow: taller and brighter where it's loud
    float lc = curve(x);
    float g = lc * exp(-y / (2.0 + lc * H * 0.6));
    float ga = glow * ends * 0.45 * g;
    c = over(vec4(mix(c2.rgb, c1.rgb, lc) * ga, ga), c);

    // frosted columns: soft-edged, soft-topped, brightening towards the tip
    float ci = floor(px.x / pitch);
    float lx = px.x - (ci + 0.5) * pitch;
    float xc = ((ci + 0.5) * pitch - radius * 0.5) / (res.x - radius);
    float lvl = curve(xc);
    float top = 1.5 + lvl * H;
    float col = smoothstep(pitch * 0.42, pitch * 0.12, abs(lx));
    float rise = clamp(y / max(top, 1.0), 0.0, 1.0);
    float body = step(y, top) * (0.45 + 0.55 * rise) + exp(-max(y - top, 0.0) / 2.0) * step(top, y);
    float ca = glow * ends * col * body * (0.35 + 0.65 * lvl) * 0.7 * smoothstep(0.0, 0.08, xc) * smoothstep(1.0, 0.92, xc);
    c = over(vec4(mix(c3.rgb, c1.rgb, rise) * ca, ca), c);

    // scrim behind the text: a soft dark band over its run, so the letters stay readable
    // while the bars keep their full glow above, below and either side of it
    float tx = smoothstep(textSpan.x - 6.0, textSpan.x + 3.0, px.x) * smoothstep(textSpan.y + 6.0, textSpan.y - 3.0, px.x);
    float ty = exp(-pow((px.y - res.y * 0.5) / (res.y * 0.3), 2.0));
    float sa = 0.6 * tx * ty;
    c = over(vec4(bg.rgb * sa, sa), c);

    // glass highlight just inside the top edge
    float hl = smoothstep(1.6, 0.0, abs(sd + 1.2)) * smoothstep(res.y * 0.5, res.y * 0.15, px.y) * 0.07;
    c = over(vec4(vec3(hl), hl), c);

    // progress: hairline along the bottom, brighter where played, a glowing head
    float inset = radius * 0.8;
    float span = res.x - 2.0 * inset;
    float headX = inset + frac * span;
    float onLine = smoothstep(1.4, 0.6, y) * step(inset, px.x) * step(px.x, res.x - inset);
    float played = step(px.x, headX);
    float la = onLine * mix(0.08, 0.75, played);
    c = over(vec4(mix(vec3(1.0), c1.rgb, played) * la, la), c);
    float hd = length(vec2(px.x - headX, y - 1.0));
    float ha = (smoothstep(2.2, 0.8, hd) * 0.9 + exp(-hd / 3.0) * 0.35) * step(0.001, frac);
    c = over(vec4(mix(c1.rgb, vec3(1.0), 0.4) * ha, ha), c);

    // beat lights: each starts at the bottom centre and runs both ways round the rim;
    // overlapping ones combine like light (screen), not by replacing each other
    float u = abs(px.x - res.x * 0.5) / (res.x * 0.5);
    float s = px.y > res.y * 0.5 ? u : 2.0 - u;
    vec2 b0 = beam(s, sweeps.x, punches.x), b1 = beam(s, sweeps.y, punches.y);
    vec2 b2 = beam(s, sweeps.z, punches.z), b3 = beam(s, sweeps.w, punches.w);
    float lit = 1.0 - (1.0 - b0.x) * (1.0 - b1.x) * (1.0 - b2.x) * (1.0 - b3.x);
    float heads = min(1.0, b0.y + b1.y + b2.y + b3.y);
    float rim = smoothstep(1.5, 0.0, abs(sd + 0.75));
    float ra = rim * lit * 0.85;
    c = over(vec4(mix(c1.rgb, vec3(1.0), 0.25 * heads) * ra, ra), c);

    fragColor = c * mask * qt_Opacity;
}
