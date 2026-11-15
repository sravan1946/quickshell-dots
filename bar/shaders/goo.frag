#version 440
// The card's surface as one liquid with the island it hangs from: the two rounded boxes are
// merged with a smooth minimum, so wherever they come close a neck of surface pulls between
// them (`goo` px of reach; ~18 reads as a fillet, 30+ as a stretched drop). The island is
// drawn by the island itself, so this draws the merged shape minus the island, and the two
// meet along the island's straight bottom edge, which sits on the pixel grid. Where a card
// edge runs flush with the island's (fL/fR near 0) the merge is turned off along that line:
// a smooth minimum of two collinear edges would bulge out at the seam.
// Each kick's wave round its outline is wave.frag's (islands/Wave.qml), drawn over the card.
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

void main() {
    vec2 p = qt_TexCoord0 * res;
    float i = box(p, isle, isleR);
    float gl = mix(fL, 1.0, clamp(abs(p.x - body.x) / goo, 0.0, 1.0));
    float gr = mix(fR, 1.0, clamp(abs(p.x - body.x - body.z) / goo, 0.0, 1.0));
    float d = body.w > 0.01 ? smin(i, box(p, body, bodyR), max(goo * min(gl, gr), 0.001)) : i;
    float cov = max(clamp(0.5 - d * dpr, 0.0, 1.0) - clamp(0.5 - i * dpr, 0.0, 1.0), 0.0);
    vec4 col = vec4(fill.rgb, 1.0) * fill.a;

    fragColor = col * cov * qt_Opacity;
}
