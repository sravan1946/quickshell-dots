// beatglow: the Quickshell bar's beat wave, carried onto the focused window's border.
//
// On each kick the bar (~/.config/quickshell/bar) sends `hyprctl beatglow beat ...`: the kick's
// strength, the wave's timing, the cover-art colours and where each screen's wave starts. The
// wave runs along the bar right above the window's top edge, so here it drops onto that edge
// below where it passes, splits, and runs both ways round the border to meet at the bottom: a
// white-hot comet head on the border line (~45 ms) with a bloom outside it, then a thin line in
// the kick's colour cooling towards the cover's second colour (~0.2 s), as the bar's islands
// draw it (shaders/wave.frag). Timed on its own clock from the kick, so nothing is sent per
// frame; the pulse is the bar's own model (Visualizer.arrive: launch speed easing to a cruise,
// a head of fixed length, a tail, dimming with distance), sent with each kick.
// While one of the bar's cards hangs down over the window, the bar also sends its box (`beatglow
// mask`), and the glow stays out of it: the card is see-through enough to show a border lit
// underneath it, which read as the bar's own wave running down the card from the wrong side.
//
// Build: make (see Makefile). Load: hyprctl plugin load ~/.config/hypr/plugins/beatglow/beatglow.so

#define WLR_USE_UNSTABLE

#include <array>
#include <chrono>
#include <cmath>
#include <map>
#include <sstream>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>

using Clock = std::chrono::steady_clock;
using namespace Render::GL;

static HANDLE PHANDLE = nullptr;

// ---- state from the bar ----------------------------------------------------------------------

struct SBeat {
    Clock::time_point at;
    float             strength = 0;
};

static struct {
    std::array<SBeat, 8>          beats;              // newest first
    // the pulse (the bar's Visualizer.arrive): px/s it leaves at, px/s it settles to and over how
    // many px, px it dims over (0 never), its head's length (px), its line's fade (s)
    float v0 = 4500, v1 = 1800, bend = 280, fade = 2000, head = 90, tail = 0.22f;
    std::array<float, 3>          c1 = {0.8f, 0.6f, 1.f}, c2 = {0.5f, 0.6f, 1.f};   // the kick's colour, the cover's second
    std::map<std::string, double> origins;            // monitor name -> global x the wave starts at
    std::map<std::string, std::array<float, 5>> masks; // monitor name -> the bar card's box: global x, y, w, h, corner radius
} g_state;

static constexpr float GLOW = 22.f;   // bloom reach outside the border, logical px

// when the pulse reaches d px along (as in the shader)
static float arrive(float d) {
    const auto& g = g_state;
    return (d + g.bend * std::log((g.v1 + (g.v0 - g.v1) * std::exp(-d / g.bend)) / g.v0)) / g.v1;
}
// s after which a beat can't light anything any more: round the largest window, tail gone
static float lifetime() {
    return arrive(4000) + 5 * g_state.tail;
}

static float ageOf(const SBeat& b) {
    return std::chrono::duration<float>(Clock::now() - b.at).count();
}

static bool anyLive() {
    for (const auto& b : g_state.beats)
        if (b.strength > 0 && ageOf(b) < lifetime())
            return true;
    return false;
}

// `beatglow beat <strength> <v0> <v1> <bend> <fade> <head> <tail> <r1> <g1> <b1> <r2> <g2> <b2> [monitor=x ...]`
// `beatglow mask <monitor> <x> <y> <w> <h> <radius>`: keep out of that box (global logical px);
// `beatglow mask <monitor>` alone: no box there any more
static IPC::Socket1::SResponse onCommand(const IPC::Socket1::SRequest& req) {
    std::istringstream in(req.command);
    std::string        cmd, sub;
    in >> cmd >> sub;
    if (sub == "mask") {
        std::string          mon;
        std::array<float, 5> m;
        if (!(in >> mon))
            return "error: no monitor";
        if (in >> m[0] >> m[1] >> m[2] >> m[3] >> m[4])
            g_state.masks[mon] = m;
        else
            g_state.masks.erase(mon);
        return "ok";
    }
    if (sub != "beat")
        return "usage: beatglow beat <strength> <v0> <v1> <bend> <fade> <head> <tail> <r1> <g1> <b1> <r2> <g2> <b2> [monitor=x ...] | beatglow mask <monitor> [x y w h radius]";

    SBeat b{Clock::now(), 0};
    float v0, v1, bend, fade, head, tail;
    if (!(in >> b.strength >> v0 >> v1 >> bend >> fade >> head >> tail >> g_state.c1[0] >> g_state.c1[1] >> g_state.c1[2] >> g_state.c2[0] >> g_state.c2[1] >> g_state.c2[2]))
        return "error: bad numbers";
    g_state.v0   = std::max(50.f, v0);
    g_state.v1   = std::clamp(v1, 20.f, g_state.v0);
    g_state.bend = std::max(1.f, bend);
    g_state.fade = std::max(0.f, fade);
    g_state.head = std::max(1.f, head);
    g_state.tail = std::max(0.01f, tail);
    for (std::string kv; in >> kv;) {
        const auto eq = kv.find('=');
        if (eq != std::string::npos)
            g_state.origins[kv.substr(0, eq)] = std::atof(kv.c_str() + eq + 1);
    }

    for (size_t i = g_state.beats.size() - 1; i > 0; --i)
        g_state.beats[i] = g_state.beats[i - 1];
    g_state.beats[0] = b;
    return "ok";
}

// ---- shader ----------------------------------------------------------------------------------

// Draws over the border box grown by `range` on every side. Uniform names are the ones
// Hyprland's CShader looks up; `gradient` carries our data:
//   [0] [1] the eight beats' ages (s), newest first  [2] [3] their strengths  [4] c1  [5] c2
//   [6] x: wave origin, px from the border box's left  y: v0  z: v1  w: px per logical px
//   [7] x: bend  y: fade  z: head (logical px; fade 0 = never)  w: tail (s)
//   [8] the bar card to keep out of: x0, y0, x1, y1 in px of this box (x1 <= x0: none)  [9] x: its corner radius, px
static const char* VERT = R"(#version 300 es
uniform mat3 proj;
in vec2 pos;
in vec2 texcoord;
out vec2 v_texcoord;
void main() {
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
    v_texcoord = texcoord;
}
)";

static const char* FRAG = R"(#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform vec2  fullSize;
uniform float radius;     // border's outer corner radius, px
uniform float thick;      // border width, px
uniform float range;      // bloom margin, px
uniform float alpha;
uniform vec4  gradient[10];
layout(location = 0) out vec4 fragColor;

const float HPI = 1.5707963;

// clockwise arc length round a rounded box of size S, radius r, from the start of the top edge
float perim(vec2 p, vec2 S, float r) {
    float w = S.x - 2.0 * r, h = S.y - 2.0 * r, a = HPI * r;
    vec2 q = clamp(p, vec2(r), S - vec2(r));
    vec2 d = p - q;
    if (abs(d.x) < 1e-3 && abs(d.y) < 1e-3) {   // inside the straight part: nearest edge
        float t = p.y, b = S.y - p.y, l = p.x, rr = S.x - p.x;
        float m = min(min(t, b), min(l, rr));
        if (m == t) return clamp(p.x - r, 0.0, w);
        if (m == rr) return w + a + clamp(p.y - r, 0.0, h);
        if (m == b) return w + 2.0 * a + h + clamp(S.x - r - p.x, 0.0, w);
        return 2.0 * w + 3.0 * a + h + clamp(S.y - r - p.y, 0.0, h);
    }
    if (abs(d.x) < 1e-3) return d.y < 0.0 ? q.x - r : w + 2.0 * a + h + (S.x - r - q.x);
    if (abs(d.y) < 1e-3) return d.x > 0.0 ? w + a + (q.y - r) : 2.0 * w + 3.0 * a + h + (S.y - r - q.y);
    if (d.x > 0.0 && d.y < 0.0) return w + a * atan(d.x, -d.y) / HPI;
    if (d.x > 0.0 && d.y > 0.0) return w + a + h + a * atan(d.y, d.x) / HPI;
    if (d.x < 0.0 && d.y > 0.0) return 2.0 * w + 2.0 * a + h + a * atan(-d.x, d.y) / HPI;
    return 2.0 * w + 3.0 * a + 2.0 * h + a * atan(-d.y, -d.x) / HPI;
}

void main() {
    vec2  S  = fullSize - vec2(2.0 * range);
    vec2  p  = v_texcoord * fullSize - vec2(range);
    float r  = min(radius, 0.5 * min(S.x, S.y));
    vec2  qq = abs(p - 0.5 * S) - 0.5 * S + r;
    float sd = length(max(qq, 0.0)) + min(max(qq.x, qq.y), 0.0) - r;   // > 0 outside the border

    // path distance (logical px) from where the wave started: along the bar to the top edge
    // right under it, then round the border both ways
    float sc = gradient[6].w;
    float L  = 2.0 * (S.x + S.y - 4.0 * r) + 4.0 * HPI * r;
    float ex = clamp(gradient[6].x, r, S.x - r);
    float h0 = abs(gradient[6].x - ex);
    float cw = mod(perim(p, S, r) - (ex - r), L);   // clockwise from the start
    float pd = (h0 + min(cw, L - cw)) / sc;

    // the bar's pulse (Visualizer.arrive, shaders/wave.frag: keep them alike): speed pd px along
    // is v1 + (v0 - v1) e^(-pd/bend), so it reaches the window's top corners with the bar's own
    // front and keeps going round at the cruise speed. The head is `head` px long behind the
    // front at any speed; the line it leaves fades over `tail` s; it dims over `fade` px.
    float v0 = gradient[6].y, v1 = gradient[6].z, bend = gradient[7].x, fade = gradient[7].y;
    float headPx = gradient[7].z, tail = gradient[7].w;
    float vhere = v1 + (v0 - v1) * exp(-pd / bend);
    float at = (pd + bend * log(vhere / v0)) / v1;
    float amp = fade > 0.0 ? exp(-pd / fade) : 1.0;

    float flash = 0.0, after = 0.0;
    for (int i = 0; i < 2; i++)
        for (int k = 0; k < 4; k++) {
            float pw = gradient[2 + i][k];
            if (pw <= 0.0) continue;
            float dt = gradient[i][k] - at;   // since the front passed
            float px = dt * vhere;             // px behind it (< 0: ahead)
            if (px < -6.0) continue;
            float on = smoothstep(-6.0, 0.0, px) * pw * amp;   // a soft leading edge, no hard cut
            flash += on * exp(-max(px, 0.0) / headPx);
            after += on * 0.3 * exp(-max(dt, 0.0) / tail);
        }
    flash = min(flash, 1.0);
    after = min(after, 1.0);
    if (flash + after < 0.003) discard;

    vec3  c1 = gradient[4].rgb, c2 = gradient[5].rgb;
    // the line cools from the kick's colour towards the cover's second, with more colour than the
    // cover's pastels have (they go muddy dim); the head burns white
    vec3  kc   = mix(c1, c2, 0.35 * after / (flash + after + 1e-4));
    kc         = clamp(mix(vec3(dot(kc, vec3(0.299, 0.587, 0.114))), kc, 1.6), 0.0, 1.0);
    float aa = 0.75;
    // the border line itself
    float line = smoothstep(-thick - aa, -thick + aa, sd) * (1.0 - smoothstep(-aa, aa, sd));
    float la   = line * min(1.0, flash * 0.95 + after);
    vec3  lc   = mix(kc, vec3(1.0), 0.6 * flash);
    // bloom outside it, mostly with the head
    float o    = max(sd, 0.0);
    float ba   = step(0.0, sd) * (exp(-o / (range * 0.22)) * 0.8 + exp(-o / (range * 0.55)) * 0.2)
               * smoothstep(range, range * 0.7, o) * (flash * 0.6 + after * 0.4);
    vec3  bc   = mix(kc, c1, flash);
    // a thin spill just inside, on the window's edge
    float ia   = step(sd, -thick) * exp((sd + thick) / (2.5 * sc)) * flash * 0.25;

    vec4 c = vec4(bc * ba, ba);
    c = vec4(kc * ia, ia) + c * (1.0 - ia);
    c = vec4(lc * la, la) + c * (1.0 - la);

    // nothing under the bar's card (it would show through it)
    vec4 mb = gradient[8];
    if (mb.z > mb.x) {
        vec2  pf = v_texcoord * fullSize;
        vec2  hs = 0.5 * (mb.zw - mb.xy);
        float mr = min(gradient[9].x, min(hs.x, hs.y));
        vec2  mq = abs(pf - 0.5 * (mb.xy + mb.zw)) - hs + mr;
        float md = length(max(mq, 0.0)) + min(max(mq.x, mq.y), 0.0) - mr;   // > 0 outside the card
        c *= smoothstep(-sc, sc, md);
    }
    fragColor = c * alpha;
}
)";

static SP<CShader> g_shader;
static bool        g_shaderFailed = false;

static SP<CShader> shader() {
    if (!g_shader && !g_shaderFailed) {
        auto s = makeShared<CShader>();
        // dynamic: a bad shader logs and returns false instead of taking Hyprland down
        if (s->createProgram(VERT, FRAG, true))
            g_shader = s;
        else {
            g_shaderFailed = true;
            HyprlandAPI::addNotification(PHANDLE, "[beatglow] shader failed to compile, see the Hyprland log", CHyprColor{1.0, 0.3, 0.3, 1.0}, 8000);
        }
    }
    return g_shader;
}

// ---- decoration ------------------------------------------------------------------------------

class CBeatGlow;

class CBeatGlowPass : public IPassElement {
  public:
    CBeatGlowPass(CBeatGlow* deco, float a, const Render::SWindowRenderPresentation& pres) : m_deco(deco), m_a(a), m_pres(pres) {}
    std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override;
    bool                          needsLiveBlur(Render::CRenderContext&) override { return false; }
    bool                          needsPrecomputeBlur(Render::CRenderContext&) override { return false; }
    const char*                   passName() override { return "CBeatGlowPass"; }
    ePassElementType              type() override { return EK_CUSTOM; }

  private:
    CBeatGlow*                        m_deco;
    float                             m_a;
    Render::SWindowRenderPresentation m_pres;
};

class CBeatGlow : public IHyprWindowDecoration {
  public:
    CBeatGlow(PHLWINDOW w) : IHyprWindowDecoration(w), m_window(w) {}
    ~CBeatGlow() override { damageEntire(); }

    SDecorationPositioningInfo getPositioningInfo() override {
        SDecorationPositioningInfo info;
        info.policy         = DECORATION_POSITION_ABSOLUTE;
        info.edges          = DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP;
        const double e      = GLOW + 8;
        info.desiredExtents = {{e, e}, {e, e}};
        return info;
    }
    void             onPositioningReply(const SDecorationPositioningReply&) override {}
    eDecorationType  getDecorationType() override { return DECORATION_CUSTOM; }
    eDecorationLayer getDecorationLayer() override { return DECORATION_LAYER_OVER; }
    uint64_t         getDecorationFlags() override { return DECORATION_NON_SOLID; }
    std::string      getDisplayName() override { return "beatglow"; }
    void             updateWindow(PHLWINDOW) override { damageEntire(); }

    // the window's box on the layout, with its border and our bloom margin
    CBox outerBox(const Render::SWindowRenderPresentation& pres) {
        const auto w = m_window.lock();
        auto       box = CBox{w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT), w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)};
        box.translate(pres.workspaceOffset).translate(pres.floatingOffset);
        return box.expand(w->presentation().borderSize() + GLOW);
    }

    void damageEntire() override {
        if (!validMapped(m_window))
            return;
        g_pHyprRenderer->damageBox(outerBox(m_window->presentation().renderPresentation()).expand(2));
    }

    bool shouldDraw() {
        const auto w = m_window.lock();
        return validMapped(w) && w == Desktop::focusState()->window() && w->m_monitor && g_state.origins.contains(w->m_monitor->m_name) && anyLive();
    }

    void draw(Render::CRenderContext& ctx, PHLMONITOR, float const& a, const Render::SWindowRenderPresentation& pres) override {
        if (shouldDraw())
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CBeatGlowPass>(this, a, pres));
    }

    void drawPass(Render::CRenderContext& ctx, float a, const Render::SWindowRenderPresentation& pres) {
        const auto w   = m_window.lock();
        const auto mon = ctx.m_data.pMonitor.lock();
        const auto sh  = shader();
        if (!w || !mon || !sh || !w->m_monitor || !g_state.origins.contains(w->m_monitor->m_name) || ctx.m_data.damage.empty())
            return;

        const float sc     = mon->m_scale;
        const auto  border = w->presentation().borderSize();
        const auto  layout = outerBox(pres);   // layout coords
        CBox        box    = layout.copy().translate(-mon->m_position).scale(sc).round();
        ctx.m_data.renderModif.applyToBox(box);
        if (box.width < 1 || box.height < 1)
            return;

        const float rounding = w->presentation().rounding() > 0 ? (w->presentation().rounding() + border) * sc : 0;
        // wave origin (the window's own screen's, even where it spills onto another), px from
        // the border box's left edge
        const float ox = (g_state.origins.at(w->m_monitor->m_name) - (layout.x + GLOW)) * sc;

        std::vector<float> data(40, 0.f);
        for (size_t k = 0; k < 8; ++k) {
            data[k]     = ageOf(g_state.beats[k]);
            data[8 + k] = g_state.beats[k].strength;
        }
        for (size_t i = 0; i < 3; ++i) {
            data[16 + i] = g_state.c1[i];
            data[20 + i] = g_state.c2[i];
        }
        data[19] = data[23] = 1;
        data[24] = ox;
        data[25] = g_state.v0;
        data[26] = g_state.v1;
        data[27] = sc;
        data[28] = g_state.bend;
        data[29] = g_state.fade;
        data[30] = g_state.head;
        data[31] = g_state.tail;
        if (const auto m = g_state.masks.find(w->m_monitor->m_name); m != g_state.masks.end()) {
            const auto& [mx, my, mw, mh, mr] = m->second;
            data[32] = (mx - layout.x) * sc;
            data[33] = (my - layout.y) * sc;
            data[34] = (mx + mw - layout.x) * sc;
            data[35] = (my + mh - layout.y) * sc;
            data[36] = mr * sc;
        }

        const bool blend = glIsEnabled(GL_BLEND);
        g_pHyprOpenGL->blend(true);
        g_pHyprOpenGL->useShader(sh);
        sh->setUniformMatrix3fv(SHADER_PROJ, 1, GL_TRUE, g_pHyprRenderer->projectBoxToTarget(ctx, box).getMatrix());
        sh->setUniformFloat2(SHADER_FULL_SIZE, box.width, box.height);
        sh->setUniformFloat(SHADER_RADIUS, rounding);
        sh->setUniformFloat(SHADER_THICK, border * sc);
        sh->setUniformFloat(SHADER_RANGE, GLOW * sc);
        sh->setUniformFloat(SHADER_ALPHA, a);
        sh->setUniform4fv(SHADER_GRADIENT, 10, data);

        glBindVertexArray(sh->getUniformLocation(SHADER_SHADER_VAO));
        CRegion region = ctx.m_data.damage.copy().intersect(box);
        if (ctx.m_data.clipBox.width != 0 && ctx.m_data.clipBox.height != 0)
            region.intersect(ctx.m_data.clipBox);
        region.forEachRect([&ctx](const auto& rect) {
            g_pHyprOpenGL->scissor(ctx, &rect, ctx.m_data.transformDamage);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        });
        glBindVertexArray(0);
        g_pHyprOpenGL->scissor(ctx, nullptr);
        g_pHyprOpenGL->blend(blend);
    }

    PHLWINDOWREF m_window;
};

std::vector<UP<IPassElement>> CBeatGlowPass::draw(Render::CRenderContext& ctx) {
    m_deco->drawPass(ctx, m_a, m_pres);
    return {};
}

// ---- plugin ----------------------------------------------------------------------------------

static void decorate(PHLWINDOW w) {
    if (std::ranges::any_of(w->presentation().decorations(), [](const auto& d) { return d->getDisplayName() == "beatglow"; }))
        return;
    HyprlandAPI::addWindowDecoration(PHANDLE, w, makeShared<CBeatGlow>(w));
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash()) {
        HyprlandAPI::addNotification(PHANDLE, "[beatglow] built against a different Hyprland, rebuild it", CHyprColor{1.0, 0.3, 0.3, 1.0}, 8000);
        throw std::runtime_error("[beatglow] version mismatch");
    }

    HyprlandAPI::registerHyprCtlCommand(PHANDLE, IPC::Socket1::SCommand{.name = "beatglow", .match = IPC::Socket1::COMMAND_MATCH_PREFIX, .handler = onCommand});

    static auto onOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { decorate(w); });
    // keep frames coming on the focused window while a beat is still lighting it
    static auto onFrame = Event::bus()->m_events.render.pre.listen([](PHLMONITOR) {
        if (!anyLive())
            return;
        if (const auto w = Desktop::focusState()->window(); w && validMapped(w))
            for (const auto& d : w->presentation().decorations())
                if (d->getDisplayName() == "beatglow")
                    d->damageEntire();
    });

    for (const auto& w : Desktop::windowState()->windows())
        if (w->mapped() && !w->isHidden())
            decorate(w);

    return {"beatglow", "The Quickshell bar's beat wave on the focused window's border", "sravan", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    Render::IHyprRenderer::currentPass(g_pHyprRenderer->context()).removeAllOfType("CBeatGlowPass");
    g_shader.reset();
}
