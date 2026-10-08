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
    vec2 track;      // px: the progress line's ends (the text column, clear of the cover)
    float style;     // Settings.mediaStyle: 0 columns, 1 ambient field, 2 mini EQ, 3 spectrum strip, 4 waveform tail
    float time;      // s, Visualizer's frame clock (stops while paused)
    float eqX;       // px: where the mini EQ starts (style 2)
    vec2 wave;       // px: the waveform tail's span (style 4)
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
    return pow(clamp(v, 0.0, 1.0), 0.6);   // <1 lifts mids and highs, which cava reports low (~0.1-0.15 typical)
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

    float headX = mix(track.x, track.y, frac);
    float kick = punches.x * pow(1.0 - sweeps.x, 2.0);   // the newest beat, easing off
    if (style < 0.5) {
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
    } else if (style < 1.5) {
        // ambient field: five blobs of the palette drifting behind everything, each
        // swelling with its part of the spectrum and flaring on the beat, under a slow sheen
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float bx = 0.1 + 0.2 * fi;
            float lb = curve(bx);
            vec2 bc = vec2(bx * res.x + sin(time * 0.35 + fi * 1.7) * res.x * 0.07,
                           res.y * (0.5 + 0.35 * sin(time * 0.27 + fi * 2.3)));
            vec2 dd = (px - bc) / vec2(res.x * (0.12 + 0.08 * lb), res.y * (0.55 + 0.45 * lb));
            vec3 col = fi == 2.0 ? c1.rgb : mod(fi, 2.0) < 0.5 ? c2.rgb : c3.rgb;
            float a2 = glow * exp(-dot(dd, dd)) * (0.2 + 0.55 * lb + 0.25 * kick);
            c = over(vec4(col * a2, a2), c);
        }
        // a soft slanted band of light gliding across every ~7 s
        float sx = fract(time * 0.14) * (res.x + 80.0) - 40.0;
        float sh = exp(-pow((px.x - sx + (px.y - res.y * 0.5) * 0.6) / 14.0, 2.0)) * 0.09 * glow;
        c = over(vec4(vec3(1.0) * sh, sh), c);
    } else if (style < 2.5) {
        // mini EQ: five capsules beside the cover, mirrored about the middle, bass .. treble,
        // brightening towards their tips, each in a soft glow; they jump on the beat
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float lb = curve(0.5 - 0.1 * fi);
            float bxc = eqX + 1.4 + fi * 3.6;
            float r = 1.25;
            float hh = r + 0.6 + lb * (7.5 + 1.5 * kick);
            float yc = y - res.y * 0.5;
            float dc = length(vec2(px.x - bxc, yc - clamp(yc, -hh + r, hh - r))) - r;
            float tt = clamp(abs(yc) / max(hh, 1.0), 0.0, 1.0);
            vec3 col = mix(mix(c3.rgb, c1.rgb, 0.4 + 0.6 * lb), vec3(1.0), 0.35 * tt * lb);
            float g2 = exp(-max(dc, 0.0) / 2.2) * 0.35 * lb * glow;
            c = over(vec4(c2.rgb * g2, g2), c);
            float a2 = smoothstep(0.5, -0.5, dc) * (0.45 + 0.55 * glow);
            c = over(vec4(col * a2, a2), c);
        }
    } else if (style < 3.5) {
        // spectrum strip: the progress line made of fine bars; the played part rises from
        // the palette's root colour to its accent over a glow, the rest stays a quiet grey
        float pc = 2.6;
        float cs = floor((px.x - track.x) / pc);
        float cx = track.x + (cs + 0.5) * pc;
        float ls = curve((cx - track.x) / max(track.y - track.x, 1.0));
        float r = 0.75;
        float top = 1.0 + r + ls * (6.0 + 1.5 * kick);
        float dc = length(vec2(px.x - cx, y - clamp(y, 1.0 + r, top))) - r;
        float inside = step(track.x, cx) * step(cx, track.y);
        float pl = step(cx, headX);
        float g2 = step(track.x, px.x) * step(px.x, headX) * 0.22 * glow * exp(-y / 4.0) * (0.4 + 0.6 * ls);
        c = over(vec4(c2.rgb * g2, g2), c);
        float rise = clamp((y - 1.0) / 7.0, 0.0, 1.0);
        vec3 col = mix(vec3(0.75), mix(c3.rgb, c1.rgb, 0.3 + 0.7 * rise), pl);
        float a2 = smoothstep(0.5, -0.5, dc) * inside * mix(0.2, 0.95 * (0.45 + 0.55 * glow), pl);
        c = over(vec4(col * a2, a2), c);
    } else {
        // waveform tail: mirrored bars about a faint centre line in their own space after the
        // text, fading in and out at the ends, whitening at the tips, glowing; they swell on
        // the beat
        float pc = 3.0;
        float cw = floor((px.x - wave.x) / pc);
        float cx = wave.x + (cw + 0.5) * pc;
        float f = (cx - wave.x) / max(wave.y - wave.x, 1.0);
        float lw = curve(f);
        float r = 0.95;
        float hh = r + 0.5 + lw * (res.y * 0.5 - 5.0) * (1.0 + 0.2 * kick);
        float yc = y - res.y * 0.5;
        float dc = length(vec2(px.x - cx, yc - clamp(yc, -hh + r, hh - r))) - r;
        float inr = step(wave.x, cx - r) * step(cx + r, wave.y);
        float edge = smoothstep(0.0, 0.18, f) * smoothstep(1.0, 0.82, f);
        float line = exp(-yc * yc / 0.3) * 0.12 * edge * step(wave.x, px.x) * step(px.x, wave.y);
        c = over(vec4(vec3(1.0) * line, line), c);
        float g2 = 0.3 * lw * glow * exp(-max(dc, 0.0) / 3.0) * edge * inr;
        c = over(vec4(c2.rgb * g2, g2), c);
        float tt = clamp(abs(yc) / max(hh, 1.0), 0.0, 1.0);
        vec3 col = mix(mix(c3.rgb, c1.rgb, 0.35 + 0.65 * lw), vec3(1.0), 0.3 * tt * lw);
        float a2 = smoothstep(0.5, -0.5, dc) * inr * (0.4 + 0.6 * glow) * (0.55 + 0.45 * lw) * (0.35 + 0.65 * edge);
        c = over(vec4(col * a2, a2), c);
    }

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
    float strip = step(abs(style - 3.0), 0.5);   // style 3 draws its own line
    float onLine = smoothstep(1.4, 0.6, y) * step(track.x, px.x) * step(px.x, track.y) * (1.0 - strip);
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
