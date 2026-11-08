pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs

// cava's spectrum of whatever is playing (scripts/cava.conf): 32 bands, stereo layout
// (left treble .. bass | bass .. right treble), handed out already packed as the vec4
// uniforms the shaders take: l0..l7 (this frame) and p0..p7 (peaks, falling slowly).
// Peaks are only pushed while something wants them (peakUsers, the panel's ring).
// `beat` fires on each kick (scripts/kicks.py), when it's heard: see `hold` below.
// cava runs only while an MPRIS player is playing.
Singleton {
    id: viz

    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    property bool active: false   // frames are arriving
    property real bass: 0         // 0..1, the four middle (lowest) bands
    property int peakUsers: 0
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
    property var pv2: new Array(32).fill(0)   // the frame before (timbre()'s rise runs over two)
    // kicks heard from kicks.py, waiting for their sound to come out of the speakers:
    // {at: t to fire, det: t found, s: strength, c: colour once cava has caught up with it}
    property var pending: []
    property int queued: 0       // pending.length, for bindings
    // The sink plays what kicks.py hears `lag` s later (PipeWire's own figure: 0.31 s on the
    // Bluetooth headphones, next to nothing on the speakers), so each kick waits `hold` s to land
    // with its sound. Measured 2026-10-27 (sink audio, logged kicks and 60 fps grabs of the bar):
    // found ~0.01 s after the sink has it, on screen ~0.05 s after it fires; held for lag - 0.07
    // the light leaves the music as it's heard (within ~0.02 s, by the song) and reaches the
    // bar's ends ~0.1 s later as it travels. Settings.kickOffset: + shows earlier.
    property real lag: 0
    readonly property real hold: Math.max(0, lag - 0.07 - Settings.kickOffset)

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
        pending = []
        queued = 0
    }

    // a kick found (strength s) that started `age` s ago (kicks.py watches each rise for its
    // peak first): it lands `hold` s after it started, coloured once cava has it
    function kick(s, age) {
        const now = Date.now() / 1000 - epoch - age
        pending.push({ at: now + hold, det: now, s: s, c: null })
        queued = pending.length
    }
    // cava sees a kick ~0.07 s after kicks.py does: colour the ones it has caught up with
    function colour() {
        for (const k of pending) if (!k.c && t >= k.det + 0.07) k.c = kickColor(timbre())
    }
    function release() {
        while (pending.length && pending[0].at <= t) {
            const k = pending.shift()
            queued = pending.length
            if (t - k.at > 0.1) continue   // held up (no frames yet): its moment has passed
            const c = k.c ?? kickColor(timbre())
            beatAt = k.at
            beatStrength = k.s
            beatAts = Qt.vector4d(k.at, beatAts.x, beatAts.y, beatAts.z)
            beatPows = Qt.vector4d(k.s, beatPows.x, beatPows.y, beatPows.z)
            beatCol = c
            beatR = Qt.vector4d(c.r, beatR.x, beatR.y, beatR.z)
            beatG = Qt.vector4d(c.g, beatG.x, beatG.y, beatG.z)
            beatB = Qt.vector4d(c.b, beatB.x, beatB.y, beatB.z)
            beat(k.s)
        }
    }

    // What a kick sounded like, 0 (all sub) .. 1 (all treble): where in the spectrum its
    // sudden energy landed, the centroid of each band's rise over two frames,
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

    // band i (0..31) for a binding: `lv` changes in place, which no binding sees; l0..l7 are
    // reassigned every frame
    function level(i) { const v = [l0, l1, l2, l3, l4, l5, l6, l7][i >> 2]; return [v.x, v.y, v.z, v.w][i & 3] }
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
        id: kp
        readonly property bool want: viz.playing && Settings.beatEffects
        onWantChanged: running = want
        Component.onCompleted: running = want
        // a new command only applies to the next start: restart for a moved setting
        onCommandChanged: if (running) { running = false; Qt.callLater(() => running = want) }
        command: ["python3", Qt.resolvedUrl("scripts/kicks.py").toString().replace("file://", ""),
                  String(Settings.kickFloor), String(Settings.kickGap), String(Settings.kickMargin)]
        onRunningChanged: if (running) lagQ.ask()
        stdout: SplitParser {
            onRead: line => { const [s, age] = line.split(" ").map(Number); viz.kick(Math.min(1, s || 0), age || 0) }
        }
    }
    // the default sink's latency (its Latency param's minNs), asked when kicks start or it changes
    readonly property var sink: Pipewire.defaultAudioSink
    onSinkChanged: lagQ.ask()
    Process {
        id: lagQ
        function ask() { if (viz.sink) { command = ["pw-cli", "enum-params", String(viz.sink.id), "Latency"]; running = true } }
        stdout: StdioCollector {
            onStreamFinished: {
                const ns = (text.match(/minNs[^\n]*\n\s*Long \d+/g) ?? []).map(m => Number(m.split("Long ")[1]))
                viz.lag = ns.length ? Math.max(...ns) / 1e9 : 0
            }
        }
    }
    // cava's frames come 30 times a second; while a wave is out (or a kick waits) the clock
    // runs with the screen instead, so the light moves every frame
    FrameAnimation {
        running: viz.active && (viz.queued > 0 || viz.t - viz.beatAt < viz.waveDur)
        onTriggered: { viz.t = Date.now() / 1000 - viz.epoch; viz.release() }
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
                viz.colour()
                viz.release()
                const old = viz.pv2   // recycle: pv2 <- pv1 <- this frame
                viz.pv2 = viz.pv1
                for (let k = 0; k < 32; k++) old[k] = lv[k]
                viz.pv1 = old
            }
        }
    }
}
