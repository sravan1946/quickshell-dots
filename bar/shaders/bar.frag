#version 440
// Bar backdrop on the beat (Bar.qml, fed by Visualizer.qml): each kick's beat wave runs out
// from the media pill along the bar's bottom edge to both screen ends, a bright head
// with a fading wake and light lifting off the edge. Up to
// four run at once, so quick kicks chase each other out. Sits behind the modules.
// Rebuild after editing: shaders/build.sh, then bump ?v= in Bar.qml
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // item size in px
    float ox;        // px: where the waves start (the media pill's centre)
    vec4 fronts;     // last four beats' wave fronts, newest in x: px from ox
    vec4 fades;      // how bright each still is, 0..1
    vec4 c1; vec4 c2;
};

vec4 wave(vec2 px, float front, float fade) {
    float d = abs(px.x - ox);
    float y = res.y - px.y;   // px above the bottom
    float head = exp(-pow((d - front) / 28.0, 2.0));
    float wake = step(d, front) * exp(-(front - d) / 160.0) * 0.4;
    float edge = (head + wake) * exp(-y / 1.6);                                // the line on the edge
    float lift = (head * 0.55 + wake * 0.4) * exp(-y / (5.0 + 10.0 * head));   // light rising off it
    float a = 0.45 * fade * clamp(edge + lift, 0.0, 1.0);   // kept dim: the pills carry the punch
    vec3 col = mix(c2.rgb, mix(c1.rgb, vec3(1.0), 0.2 * head), clamp(head + 0.5, 0.0, 1.0));
    return vec4(col * a, a);
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    // light adds up where waves cross
    vec4 c = wave(px, fronts.x, fades.x) + wave(px, fronts.y, fades.y)
       + wave(px, fronts.z, fades.z) + wave(px, fronts.w, fades.w);
    fragColor = min(c, vec4(1.0)) * qt_Opacity;
}
