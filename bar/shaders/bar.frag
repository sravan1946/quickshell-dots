#version 440
// Bar backdrop on the beat (Bar.qml, fed by Visualizer.qml): each kick's beat wave runs out
// from the media pill along the bar's bottom edge to both screen ends, a bright head
// with a fading wake and light lifting off the edge. Up to
// four run at once, so quick kicks chase each other out. Sits behind the modules.
// Each is coloured by what its kick sounded like (Visualizer.kickColor).
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
    vec4 kr; vec4 kg; vec4 kb;   // each beat's colour (Visualizer.kickColor), one channel per vec4
    float reach;     // px the fronts travel, over dur s (Visualizer.waveReach, waveDur)
    float dur;
};

vec4 wave(vec2 px, float front, float fade, vec3 kc) {
    float d = abs(px.x - ox);
    float y = res.y - px.y;   // px above the bottom
    // The fronts only move when a cava frame lands (30 fps), up to ~260 px a step early on, so
    // the head is smeared back over one step's travel, a motion streak that shortens as it
    // slows (front = reach * (1 - (1 - p)^3): speed = 3 reach (1 - p)^2 / dur). The wake
    // fades in across the streak instead of switching on at the front.
    float q = max(0.0, 1.0 - front / max(reach, 1.0));                    // (1 - p)^3
    float streak = 3.0 * reach * pow(q, 2.0 / 3.0) / max(dur, 0.05) / 30.0;  // px per frame
    float x = d - front;                                                   // + ahead, - behind
    float head = exp(-pow(x / (x > 0.0 ? 16.0 : 16.0 + streak), 2.0));
    float wake = smoothstep(16.0, -16.0 - streak, x) * exp(-max(0.0, -x) / 160.0) * 0.4;
    float edge = (head + wake) * exp(-y / 1.6);                                // the line on the edge
    float lift = (head * 0.3 + wake * 0.4) * exp(-y / (4.0 + 4.0 * head));   // light rising off it, kept low
    float a = 0.45 * fade * clamp(edge + lift, 0.0, 1.0);   // kept dim: the pills carry the punch
    vec3 col = mix(kc * 0.55, mix(kc, vec3(1.0), 0.2 * head), clamp(head + 0.5, 0.0, 1.0));   // dimmer wake
    return vec4(col * a, a);
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    // light adds up where waves cross
    vec4 c = wave(px, fronts.x, fades.x, vec3(kr.x, kg.x, kb.x)) + wave(px, fronts.y, fades.y, vec3(kr.y, kg.y, kb.y))
       + wave(px, fronts.z, fades.z, vec3(kr.z, kg.z, kb.z)) + wave(px, fronts.w, fades.w, vec3(kr.w, kg.w, kb.w));
    fragColor = min(c, vec4(1.0)) * qt_Opacity;
}
