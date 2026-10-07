// beatglow: the Quickshell bar's beat wave, carried onto the focused window's border.
//
// On each kick the bar (~/.config/quickshell/bar) sends `hyprctl beatglow beat ...`: the kick's
// strength, the wave's timing, the cover-art colours and where each screen's wave starts. The
// wave runs along the bar right above the window's top edge, so here it drops onto that edge
// below where it passes, splits, and runs both ways round the border to meet at the bottom: a
// bright comet on the border line with a bloom outside it, then a short afterglow along the
// whole rim, the same flash + afterglow the bar's pills get. Timed on its own clock from the
// kick, so nothing is sent per frame; the front matches the bar's (same easing and speed).
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
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
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
    std::array<SBeat, 4>          beats;              // newest first
    float                         dur   = 1.0f;       // the bar wave: s to run `reach` px,
    float                         reach = 2600.f;     // easing out (cubic)
    std::array<float, 3>          c1 = {0.8f, 0.6f, 1.f}, c2 = {0.5f, 0.6f, 1.f};
    std::map<std::string, double> origins;            // monitor name -> global x the wave starts at
} g_state;

static constexpr float GLOW     = 22.f;   // bloom reach outside the border, logical px
static constexpr float LIFETIME = 3.f;    // s after which a beat can't light anything any more

static float ageOf(const SBeat& b) {
    return std::chrono::duration<float>(Clock::now() - b.at).count();
}

static bool anyLive() {
    for (const auto& b : g_state.beats)
        if (b.strength > 0 && ageOf(b) < LIFETIME)
            return true;
    return false;
}

// `beatglow beat <strength> <dur> <reach> <r1> <g1> <b1> <r2> <g2> <b2> [monitor=x ...]`
static std::string onCommand(eHyprCtlOutputFormat, std::string req) {
    std::istringstream in(req);
    std::string        cmd, sub;
    in >> cmd >> sub;
    if (sub != "beat")
        return "usage: beatglow beat <strength> <dur> <reach> <r1> <g1> <b1> <r2> <g2> <b2> [monitor=x ...]";

    SBeat b{Clock::now(), 0};
    float dur, reach;
    if (!(in >> b.strength >> dur >> reach >> g_state.c1[0] >> g_state.c1[1] >> g_state.c1[2] >> g_state.c2[0] >> g_state.c2[1] >> g_state.c2[2]))
        return "error: bad numbers";
    g_state.dur   = std::max(0.05f, dur);
    g_state.reach = std::max(100.f, reach);
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
//   [0] beat ages (s)  [1] strengths  [2] c1  [3] c2
//   [4] x: wave origin, px from the border box's left  y: reach (logical px)  z: dur (s)  w: px per logical px
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
    float sc = gradient[4].w;
    float L  = 2.0 * (S.x + S.y - 4.0 * r) + 4.0 * HPI * r;
    float ex = clamp(gradient[4].x, r, S.x - r);
    float ds = abs(perim(p, S, r) - (ex - r));
    float pd = (abs(gradient[4].x - ex) + min(ds, L - ds)) / sc;

    // the bar's wave slows to a stop at `reach`; stretch it (same start speed) so it gets
    // all the way round this window
    float far   = (abs(gradient[4].x - ex) + 0.5 * L) / sc + 60.0;
    float reach = max(gradient[4].y, far);
    float dur   = gradient[4].z * reach / gradient[4].y;

    float flash = 0.0, after = 0.0;
    for (int k = 0; k < 4; k++) {
        float pw = gradient[1][k];
        if (pw <= 0.0 || pd >= reach) continue;
        float dt = gradient[0][k] - dur * (1.0 - pow(1.0 - pd / reach, 1.0 / 3.0));   // since the front passed
        if (dt < 0.0) {   // just ahead of it: a soft leading edge, no hard cut
            flash += pw * exp(dt / 0.012);
            continue;
        }
        flash += pw * exp(-dt / 0.05);
        after += pw * exp(-dt / 0.35);
    }
    flash = min(flash, 1.0);
    after = min(after, 1.0);
    if (flash + after < 0.003) discard;

    vec3  c1 = gradient[2].rgb, c2 = gradient[3].rgb;
    float aa = 0.75;
    // the border line itself: a white-hot head, the cover colour behind it
    float line = smoothstep(-thick - aa, -thick + aa, sd) * (1.0 - smoothstep(-aa, aa, sd));
    float la   = line * min(1.0, flash * 0.95 + after * 0.45);
    vec3  lc   = mix(c1, vec3(1.0), 0.55 * flash);
    // bloom outside it, mostly with the head
    float o    = max(sd, 0.0);
    float ba   = step(0.0, sd) * (exp(-o / (range * 0.22)) * 0.8 + exp(-o / (range * 0.55)) * 0.2)
               * smoothstep(range, range * 0.7, o) * (flash * 0.6 + after * 0.12);
    vec3  bc   = mix(c2, c1, flash);
    // a thin spill just inside, on the window's edge
    float ia   = step(sd, -thick) * exp((sd + thick) / (2.5 * sc)) * flash * 0.25;

    vec4 c = vec4(bc * ba, ba);
    c = vec4(c1 * ia, ia) + c * (1.0 - ia);
    c = vec4(lc * la, la) + c * (1.0 - la);
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
    CBeatGlowPass(CBeatGlow* deco, float a) : m_deco(deco), m_a(a) {}
    std::vector<UP<IPassElement>> draw() override;
    bool                          needsLiveBlur() override { return false; }
    bool                          needsPrecomputeBlur() override { return false; }
    const char*                   passName() override { return "CBeatGlowPass"; }
    ePassElementType              type() override { return EK_CUSTOM; }

  private:
    CBeatGlow* m_deco;
    float      m_a;
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
    CBox outerBox() {
        const auto w = m_window.lock();
        auto       box = CBox{w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT), w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)};
        if (w->m_workspace && !w->m_pinned)
            box.translate(w->m_workspace->m_renderOffset->value());
        box.translate(w->m_floatingOffset);
        return box.expand(w->getRealBorderSize() + GLOW);
    }

    void damageEntire() override {
        if (!validMapped(m_window))
            return;
        g_pHyprRenderer->damageBox(outerBox().expand(2));
    }

    bool shouldDraw() {
        const auto w = m_window.lock();
        return validMapped(w) && w == Desktop::focusState()->window() && w->m_monitor && g_state.origins.contains(w->m_monitor->m_name) && anyLive();
    }

    void draw(PHLMONITOR, float const& a) override {
        if (shouldDraw())
            g_pHyprRenderer->m_renderPass.add(makeUnique<CBeatGlowPass>(this, a));
    }

    void drawPass(float a) {
        const auto w   = m_window.lock();
        const auto mon = g_pHyprRenderer->m_renderData.pMonitor.lock();
        const auto sh  = shader();
        if (!w || !mon || !sh || !w->m_monitor || !g_state.origins.contains(w->m_monitor->m_name) || g_pHyprRenderer->m_renderData.damage.empty())
            return;

        const float sc     = mon->m_scale;
        const auto  border = w->getRealBorderSize();
        const auto  layout = outerBox();   // layout coords
        CBox        box    = layout.copy().translate(-mon->m_position).scale(sc).round();
        g_pHyprRenderer->m_renderData.renderModif.applyToBox(box);
        if (box.width < 1 || box.height < 1)
            return;

        const float rounding = w->rounding() > 0 ? (w->rounding() + border) * sc : 0;
        // wave origin (the window's own screen's, even where it spills onto another), px from
        // the border box's left edge
        const float ox = (g_state.origins.at(w->m_monitor->m_name) - (layout.x + GLOW)) * sc;

        std::vector<float> data(40, 0.f);
        for (size_t k = 0; k < 4; ++k) {
            data[k]     = ageOf(g_state.beats[k]);
            data[4 + k] = g_state.beats[k].strength;
        }
        for (size_t i = 0; i < 3; ++i) {
            data[8 + i]  = g_state.c1[i];
            data[12 + i] = g_state.c2[i];
        }
        data[11] = data[15] = 1;
        data[16] = ox;
        data[17] = g_state.reach;
        data[18] = g_state.dur;
        data[19] = sc;

        const bool blend = glIsEnabled(GL_BLEND);
        g_pHyprOpenGL->blend(true);
        g_pHyprOpenGL->useShader(sh);
        sh->setUniformMatrix3fv(SHADER_PROJ, 1, GL_TRUE, g_pHyprRenderer->projectBoxToTarget(box).getMatrix());
        sh->setUniformFloat2(SHADER_FULL_SIZE, box.width, box.height);
        sh->setUniformFloat(SHADER_RADIUS, rounding);
        sh->setUniformFloat(SHADER_THICK, border * sc);
        sh->setUniformFloat(SHADER_RANGE, GLOW * sc);
        sh->setUniformFloat(SHADER_ALPHA, a);
        sh->setUniform4fv(SHADER_GRADIENT, 10, data);

        glBindVertexArray(sh->getUniformLocation(SHADER_SHADER_VAO));
        CRegion region = g_pHyprRenderer->m_renderData.damage.copy().intersect(box);
        if (g_pHyprRenderer->m_renderData.clipBox.width != 0 && g_pHyprRenderer->m_renderData.clipBox.height != 0)
            region.intersect(g_pHyprRenderer->m_renderData.clipBox);
        region.forEachRect([](const auto& rect) {
            g_pHyprOpenGL->scissor(&rect, g_pHyprRenderer->m_renderData.transformDamage);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        });
        glBindVertexArray(0);
        g_pHyprOpenGL->scissor(nullptr);
        g_pHyprOpenGL->blend(blend);
    }

    PHLWINDOWREF m_window;
};

std::vector<UP<IPassElement>> CBeatGlowPass::draw() {
    m_deco->drawPass(m_a);
    return {};
}

// ---- plugin ----------------------------------------------------------------------------------

static void decorate(PHLWINDOW w) {
    if (std::ranges::any_of(w->m_windowDecorations, [](const auto& d) { return d->getDisplayName() == "beatglow"; }))
        return;
    HyprlandAPI::addWindowDecoration(PHANDLE, w, makeUnique<CBeatGlow>(w));
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

    HyprlandAPI::registerHyprCtlCommand(PHANDLE, SHyprCtlCommand{.name = "beatglow", .exact = false, .fn = onCommand});

    static auto onOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { decorate(w); });
    // keep frames coming on the focused window while a beat is still lighting it
    static auto onFrame = Event::bus()->m_events.render.pre.listen([](PHLMONITOR) {
        if (!anyLive())
            return;
        if (const auto w = Desktop::focusState()->window(); w && validMapped(w))
            for (const auto& d : w->m_windowDecorations)
                if (d->getDisplayName() == "beatglow")
                    d->damageEntire();
    });

    for (const auto& w : Desktop::windowState()->windows())
        if (w->m_isMapped && !w->isHidden())
            decorate(w);

    return {"beatglow", "The Quickshell bar's beat wave on the focused window's border", "sravan", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_pHyprRenderer->m_renderPass.removeAllOfType("CBeatGlowPass");
    g_shader.reset();
}
