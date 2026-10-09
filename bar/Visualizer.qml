pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs

// cava's spectrum of whatever is playing (scripts/cava.conf): 32 bands, stereo layout
// (left treble .. bass | bass .. right treble), handed out already packed as the vec4
// uniforms the shaders take: l0..l7 (this frame) and p0..p7 (peaks, falling slowly).
// Peaks are only pushed while something wants them (peakUsers, the panel's ring).
// `beat` fires on each kick: see the onset detector below.
// cava runs only while an MPRIS player is playing.
Singleton {
    id: viz

    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    property bool active: false   // frames are arriving
    property real bass: 0         // 0..1, the four middle (lowest) bands
    property int peakUsers: 0
    // The detector's working, for the live scope on Settings' Media page: the last 5 s of
    // frames (rise, the threshold it had to clear, and 1 beat / 2 over it but held back by the
    // min gap / 0 neither), the threshold's parts now, and the tempo the beats imply. Only
    // recorded while scopeUsers > 0; `scoped` fires per recorded frame.
    property int scopeUsers: 0
    property var scopeRise: []
    property var scopeThr: []
    property var scopeHit: []
    property var scopeBeats: []   // `t`s of the beats in the last 8 s
    property real scopeMean: 0
    property real scopeSd: 0
    property real scopeBpm: 0
    signal scoped()
    property double beatAt: -10   // `t` of the latest beat
    property real beatStrength: 0 // 0..1, how hard it hit relative to recent kicks
    // the last four beats, newest in x: their `t`s and strengths (for overlapping effects)
    property vector4d beatAts: Qt.vector4d(-10, -10, -10, -10)
    property vector4d beatPows: zero
    // ...and their colours, one channel per vec4 (newest in x), from what each kick sounded
    // like (timbre(), kickColor()); beatCol is the newest one's
    property vector4d beatR: zero
    property vector4d beatG: zero
    property vector4d beatB: zero
    property color beatCol: "white"
    // s since the shell started, time of the latest frame: a clock that ticks only while
    // frames arrive. Kept small: beat times also travel in vec4s, which are 32-bit floats
    // (epoch seconds would round to the nearest 128 s there).
    property double t: 0
    readonly property double epoch: Date.now() / 1000
    signal beat(real strength)    // 0..1

    // The beat wave every effect rides (media pill rim, bar edge, other pills' rims, the
    // window border): each kick sends one out both ways from the media pill, fast at first
    // and slowing. For the last four beats, newest in x: px its front has travelled, and how
    // bright it still is (0 once spent). Both stop changing once all four are spent.
    readonly property real waveDur: Settings.waveDur
    readonly property real waveReach: Settings.waveReach   // px travelled by the end
    readonly property vector4d waveFronts: {
        const a = beatAts
        const f = at => waveReach * (1 - Math.pow(1 - Math.min(1, Math.max(0, (t - at) / waveDur)), 3))
        return Qt.vector4d(f(a.x), f(a.y), f(a.z), f(a.w))
    }
    readonly property vector4d waveFades: {
        const a = beatAts, p = beatPows
        const f = (at, pw) => pw * Math.pow(1 - Math.min(1, Math.max(0, (t - at) / waveDur)), 1.5)
        return Qt.vector4d(f(a.x, p.x), f(a.y, p.y), f(a.z, p.z), f(a.w, p.w))
    }
    // global x (logical px) each screen's wave starts from, by screen name: set by its media pill
    property var origins: ({})

    readonly property vector4d zero: Qt.vector4d(0, 0, 0, 0)
    property vector4d l0: zero; property vector4d l1: zero; property vector4d l2: zero; property vector4d l3: zero
    property vector4d l4: zero; property vector4d l5: zero; property vector4d l6: zero; property vector4d l7: zero
    property vector4d p0: zero; property vector4d p1: zero; property vector4d p2: zero; property vector4d p3: zero
    property vector4d p4: zero; property vector4d p5: zero; property vector4d p6: zero; property vector4d p7: zero

    // working state, mutated in place (nothing binds to it)
    property var lv: new Array(32).fill(0)
    property var pk: new Array(32).fill(0)
    property var pv1: new Array(32).fill(0)   // last frame's levels
    property var pv2: new Array(32).fill(0)   // the frame before (the detector's rise runs over two)
    // onset detector state
    property real prevBass: 0    // last frame's
    property real prevBass2: 0   // the frame before
    property real riseMean: 0
    property real riseVar: 0
    property real riseMax: 0.05

    function clear() {
        lv.fill(0); pk.fill(0)
        l0 = l1 = l2 = l3 = l4 = l5 = l6 = l7 = zero
        p0 = p1 = p2 = p3 = p4 = p5 = p6 = p7 = zero
        bass = 0
        active = false
        beatAt = -10       // no beat light frozen mid-run while paused
        beatStrength = 0
        beatAts = Qt.vector4d(-10, -10, -10, -10)
        beatPows = zero
        beatR = beatG = beatB = zero
        prevBass = prevBass2 = 0
    }

    // Kick onsets from how fast the low bands rise, not how loud they are: in busy
    // sections the bass sits high and only dips between kicks, in sparse ones it swells
    // slowly, and a level threshold misfires on both. The rise is taken over two frames,
    // since cava's smoothing spreads a kick across them. It beats when it clears the recent
    // mean + beatSens sd (~9 s EMA) plus beatFloor, at most every beatGap s (Settings).
    // Strength is the rise against the biggest recent one.
    // Defaults tuned by scripts/kicktune.py against kicks heard in the raw audio (30 fps cava, noise_reduction 77).
    function detect(b) {
        const d = Math.max(0, b - prevBass2)
        prevBass2 = prevBass
        prevBass = b
        const sd = Math.sqrt(riseVar)
        const thr = riseMean + Settings.beatSens * sd + Settings.beatFloor
        const over = d > thr, open = t - beatAt >= Settings.beatGap
        if (scopeUsers > 0) record(d, thr, sd, over ? (open && Settings.beatEffects ? 1 : 2) : 0)
        if (over && open) {
            riseMax = Math.max(riseMax, d)
            const s = Math.min(1, d / riseMax)
            if (Settings.beatEffects) {
                beatAt = t
                beatStrength = s
                beatAts = Qt.vector4d(t, beatAts.x, beatAts.y, beatAts.z)
                beatPows = Qt.vector4d(s, beatPows.x, beatPows.y, beatPows.z)
                const k = kickColor(timbre())
                beatCol = k
                beatR = Qt.vector4d(k.r, beatR.x, beatR.y, beatR.z)
                beatG = Qt.vector4d(k.g, beatG.x, beatG.y, beatG.z)
                beatB = Qt.vector4d(k.b, beatB.x, beatB.y, beatB.z)
                beat(s)
            }
        }
        riseMax = Math.max(0.05, riseMax * 0.997)
        riseMean += (d - riseMean) / 270
        riseVar += ((d - riseMean) * (d - riseMean) - riseVar) / 270
    }

    // What a kick sounded like, 0 (all sub) .. 1 (all treble): where in the spectrum its
    // sudden energy landed, the centroid of each band's rise over the detector's two frames,
    // L and R folded together. Measured on real kicks (cava, monstercat on): a typical
    // kick drum lands 0.12-0.17, clicky or snare-ish hits up to ~0.55.
    function timbre() {
        let sum = 0, at = 0
        for (let k = 0; k < 16; k++) {   // k: 0 bass .. 15 treble
            const r = Math.max(0, (lv[15 - k] + lv[16 + k] - pv2[15 - k] - pv2[16 + k]) / 2)
            sum += r; at += k * r
        }
        return sum > 0 ? at / sum / 15 : 0
    }
    // timbre -> colour, kept to the cover's main colour (Player.c1): a typical kick (~0.17) is
    // that colour; deeper ones lean darker and round the hue one way, clickier
    // ones lighter and the other way. A greyscale cover keeps its (lack of) saturation.
    // (Settings.kickTimbre, kickHue in degrees, kickLight)
    function kickColor(c) {
        const b = Player.c1
        if (!Settings.kickTimbre) return b
        const x = Math.max(-1, Math.min(1, (c - 0.17) / 0.2))   // -1 deep .. 0 typical .. 1 clicky
        const l = Math.max(0.3, Math.min(0.85, b.hslLightness + Settings.kickLight * x))
        return Qt.hsla((Math.max(0, b.hslHue) + Settings.kickHue / 360 * x + 1) % 1, b.hslSaturation, l, 1)
    }

    function record(d, thr, sd, hit) {
        const push = (a, v) => { a.push(v); if (a.length > 150) a.shift() }   // 5 s at 30 fps
        push(scopeRise, d); push(scopeThr, thr); push(scopeHit, hit)
        scopeMean = riseMean
        scopeSd = sd
        if (hit === 1) scopeBeats.push(t)
        while (scopeBeats.length && t - scopeBeats[0] > 8) scopeBeats.shift()
        // tempo: the median gap between recent beats, folded into 70..180 BPM
        const gaps = scopeBeats.slice(1).map((b, i) => b - scopeBeats[i]).sort((a, b) => a - b)
        let bpm = gaps.length >= 3 ? 60 / gaps[gaps.length >> 1] : 0
        while (bpm > 0 && bpm < 70) bpm *= 2
        while (bpm > 180) bpm /= 2
        scopeBpm = bpm
        scoped()
    }

    function publish() {
        const V = (a, k) => Qt.vector4d(a[k], a[k + 1], a[k + 2], a[k + 3])
        l0 = V(lv, 0); l1 = V(lv, 4); l2 = V(lv, 8); l3 = V(lv, 12)
        l4 = V(lv, 16); l5 = V(lv, 20); l6 = V(lv, 24); l7 = V(lv, 28)
        if (peakUsers > 0) {
            p0 = V(pk, 0); p1 = V(pk, 4); p2 = V(pk, 8); p3 = V(pk, 12)
            p4 = V(pk, 16); p5 = V(pk, 20); p6 = V(pk, 24); p7 = V(pk, 28)
        }
    }

    // on pause the spectrum falls to rest (~300 ms) instead of vanishing in one frame
    FrameAnimation {
        id: fall
        onTriggered: {
            const k = Math.exp(-frameTime * 10)
            let top = 0
            for (let i = 0; i < 32; i++) { viz.lv[i] *= k; viz.pk[i] *= k; top = Math.max(top, viz.pk[i]) }
            viz.bass *= k
            if (top < 0.01) { stop(); viz.clear() }
            else viz.publish()
        }
    }

    Process {
        running: viz.playing
        command: ["cava", "-p", Qt.resolvedUrl("scripts/cava.conf").toString().replace("file://", "")]
        onRunningChanged: if (!running) fall.start()
        stdout: SplitParser {
            onRead: line => {
                viz.t = Date.now() / 1000 - viz.epoch
                const lv = viz.lv, pk = viz.pk
                let i = 0, v = 0
                for (let c = 0; c < line.length && i < 32; c++) {
                    const ch = line.charCodeAt(c)
                    if (ch === 59) { lv[i] = v / 100; pk[i] = Math.max(lv[i], pk[i] - 0.006); i++; v = 0 }   // ';'
                    else v = v * 10 + ch - 48
                }
                fall.stop()
                viz.publish()
                viz.active = true

                viz.bass = (lv[14] + lv[15] + lv[16] + lv[17]) / 4
                viz.detect((lv[13] + lv[14] + lv[15] + lv[16] + lv[17] + lv[18]) / 6)
                const old = viz.pv2   // recycle: pv2 <- pv1 <- this frame
                viz.pv2 = viz.pv1
                for (let k = 0; k < 32; k++) old[k] = lv[k]
                viz.pv1 = old
            }
        }
    }
}
