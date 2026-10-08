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
    property double beatAt: -10   // `t` of the latest beat
    property real beatStrength: 0 // 0..1, how hard it hit relative to recent kicks
    // the last four beats, newest in x: their `t`s and strengths (for overlapping effects)
    property vector4d beatAts: Qt.vector4d(-10, -10, -10, -10)
    property vector4d beatPows: zero
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
    // onset detector state
    property real prevBass: 0
    property real riseMean: 0
    property real riseVar: 0
    property real riseMax: 0.05
    property bool armed: true

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
        prevBass = 0
        armed = true
    }

    // Kick onsets from how fast the low bands rise, not how loud they are: in busy
    // sections the bass sits high and only dips between kicks, in sparse ones it swells
    // slowly, and a level threshold misfires on both. A rise beats when it clears the
    // recent mean + 0.9 sd (~1.5 s EMA) plus a floor, once per rise (re-armed after it
    // settles), at most every 200 ms. Strength is the rise against the biggest recent one.
    // Tuned offline on recorded cava frames (30 fps, noise_reduction 77).
    function detect(b) {
        const d = Math.max(0, b - prevBass)
        prevBass = b
        const sd = Math.sqrt(riseVar)
        if (armed && d > riseMean + 0.9 * sd + 0.025 && t - beatAt >= 0.2) {
            riseMax = Math.max(riseMax, d)
            const s = Math.min(1, d / riseMax)
            if (s > 0.2 && Settings.beatEffects) {
                beatAt = t
                beatStrength = s
                beatAts = Qt.vector4d(t, beatAts.x, beatAts.y, beatAts.z)
                beatPows = Qt.vector4d(s, beatPows.x, beatPows.y, beatPows.z)
                armed = false
                beat(s)
            }
        }
        if (d < riseMean + 0.3 * sd) armed = true
        riseMax = Math.max(0.05, riseMax * 0.997)
        riseMean += (d - riseMean) / 45
        riseVar += ((d - riseMean) * (d - riseMean) - riseVar) / 45
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
            }
        }
    }
}
