#version 440
// Liquid spread: the source pours out of `origin` as one pool with a soft, wobbly
// edge (low-frequency noise drifting as it grows). At the edge a meniscus bends the
// content like a lens and catches a faint accent sheen. progress 1 -> 0 drains it
// back into the same point. hole = 1 runs it the other way round: the content is eaten
// away from `origin` outwards (progress 1 -> 0 grows the hole), for leaving by a point.
// Rebuild after editing: shaders/build.sh
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 = gone, 1 = fully shown
    float edge;       // meniscus width, as a fraction of the spread
    float bias;       // how round the pool is: 1 = circle, lower = more wobble
    float seed;
    float hole;       // 0: pool grows from origin; 1: hole grows from origin
    vec4 glow;        // sheen colour at the edge
    vec2 res;         // item size in px
    vec2 origin;      // spawn point, 0..1 item coordinates (may sit just outside)
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 o = origin * res;
    float far = max(max(length(o), length(o - vec2(res.x, 0.0))),
                    max(length(o - vec2(0.0, res.y)), length(o - res)));
    float d = length(px - o) / far;

    // big soft lobes, drifting while it spreads, so the rim ripples
    vec2 q = px / 110.0 + vec2(0.0, progress * 1.4);
    float wob = noise(q) * 0.65 + noise(q * 2.1 + 7.3) * 0.35 - 0.5;
    float th = d * bias + wob * (1.0 - bias);   // this pixel's arrival "time", about -0.1 .. 1.1

    // starts right at the earliest pixel (the origin can arrive at about -0.1), no dead time
    float p = hole > 0.5 ? 1.0 - progress : progress;
    float t = mix(-(1.0 - bias) * 0.5, 1.0 + (1.0 - bias) * 0.6 + edge, p);
    float aa = 1.5 / far;                       // ~1.5px antialiased rim
    float reached = smoothstep(th - aa, th + aa, t);
    float shown = hole > 0.5 ? 1.0 - reached : reached;

    // meniscus: just inside the visible side of the rim, bend the sample like a lens
    // (towards the origin for a pool, away from it for a hole)
    float inside = hole > 0.5 ? th - t : t - th;
    float rim = shown * (1.0 - smoothstep(0.0, edge, inside));
    vec2 dir = normalize(px - o + vec2(0.001)) * (hole > 0.5 ? -1.0 : 1.0);
    vec4 c = texture(source, (px - dir * rim * 9.0) / res);

    vec3 rgb = mix(c.rgb, glow.rgb * c.a, rim * 0.35);
    fragColor = vec4(rgb, c.a) * shown * qt_Opacity;
}
