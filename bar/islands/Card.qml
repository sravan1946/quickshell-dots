import QtQuick
import QtQuick.Effects
import Quickshell
import qs

// The one card that grows out from under an island. It is sized for the content it is
// switching to (the next panel is loaded, then measured, in the same frame: rule 7) and slides
// from item to item while open. Its surface is drawn as one liquid with the island it hangs
// from (shaders/goo.frag): the two shapes merge with a smooth minimum, which rounds the inside
// corners where they meet (rule 22) and, with more reach, pulls a neck of surface between them.
// Opening and closing run on one progress value (rule 8): the card flows down out of the item
// as a bead of the island's surface, its neck thinning into the fillets as it fills out to
// full size, and closing draws it back up the same way. Its outline carries each kick's wave on
// from the island's edge (from `originX`, in the bar's coordinates, as the islands' Isles do).
Item {
    id: card

    property var ctl
    property var islands: []
    property Item it: null           // the Hit it hangs from
    property string key: ""          // which panel: the Hit's key, or what attach() was asked for
    property Item isl: null          // that Hit's island
    property real originX: 0
    property bool open: false
    property bool closing: false
    readonly property bool shown: open || closing
    property real p: 0               // 0 = closed, 1 = open (overshoots a little on the way)
    readonly property real beadW: 24 // how wide it starts, under the item's centre
    property real fromX: 0
    // the merge's reach in px: a thick neck while it is small, a fillet once it's out
    readonly property real goo: 30 - 12 * clamp(p, 0, 1)
    readonly property bool settled: open && !grow.running   // slides between items animate only now
    function grab(h) { fromX = h.mapToItem(parent, h.width / 2, 0).x - beadW / 2 }

    readonly property real padX: 14
    readonly property real padT: 12
    readonly property real padB: 14
    property Loader cur: la
    readonly property real targetW: snap((cur.item?.implicitWidth ?? 0) + 2 * padX)
    readonly property real targetH: snap((cur.item?.implicitHeight ?? 0) + padT + padB)
    readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    // ---- placement: centred on the item; a card that fits under its island stays under it ----
    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
    readonly property real targetX: {
        if (!it || !isl) return 0
        const w = targetW, p = it.mapToItem(isl, it.width / 2, 0).x
        const gx = isl.targetX, gw = isl.targetW
        // the item's centre once the island has finished resizing
        const cx = isl.align === "left" ? gx + p
            : isl.align === "right" ? gx + gw - (isl.width - p)
            : gx + gw / 2 + (p - isl.width / 2)
        let nx = cx - w / 2
        nx = w <= gw ? clamp(nx, gx, gx + gw - w) : clamp(nx, gx + 40 - w, gx + gw - 40)
        nx = clamp(nx, 4, parent.width - 4 - w)
        // an edge within a corner's reach of the island's edge goes flush with it
        if (Math.abs(nx - gx) < 18) nx = gx
        if (Math.abs(nx + w - (gx + gw)) < 18) nx = gx + gw - w
        return snap(nx)
    }

    x: snap(fromX + (targetX - fromX) * p)
    y: Look.top + Look.h
    width: snap(beadW + (targetW - beadW) * p)
    height: targetH * Math.max(0, p)
    visible: shown
    Behavior on x { enabled: card.settled; Anim {} }
    Behavior on width { enabled: card.settled; Anim {} }
    Behavior on height { enabled: card.settled; Anim {} }

    Anim { id: grow; target: card; property: "p"; to: 1; duration: 520 * Look.speed }
    Anim { id: shrink; target: card; property: "p"; to: 0; type: "exit"; duration: 240 * Look.speed }

    // ---- the join, measured live (mid-slide and mid-close too) ----
    readonly property real gapL: isl ? x - isl.x : 0                                // > 0: card edge inside the island
    readonly property real gapR: isl ? (isl.x + isl.width) - (x + width) : 0
    readonly property real overlap: isl ? Math.min(x + width, isl.x + isl.width) - Math.max(x, isl.x) : 0
    readonly property real k: !isl ? 0 : clamp(overlap / 30, 0, 1) * clamp(height / 14, 0, 1)
    function joinOf(i) { return i === isl ? k : 0 }
    // for the island's Isle: the span of its floor the card hangs from, in its coordinates, and
    // how far the necks reach out either side of it (the floor there is inside the card's surface too)
    function cutOf(i) { return i === isl ? Qt.vector4d(x - isl.x, x + width - isl.x, k, goo) : Qt.vector4d(0, 0, 0, 0) }
    // island bottom corners: square where the card runs flush or past, round where the card sits inside
    function cornerL(i) { return Look.h / 2 * (i === isl && gapL <= 1 ? 1 - k : 1) }
    function cornerR(i) { return Look.h / 2 * (i === isl && gapR <= 1 ? 1 - k : 1) }

    RectangularShadow {
        z: -1
        anchors.fill: parent
        offset.y: 14
        blur: 30
        spread: -8
        radius: 18
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: card.clamp(card.height / 40, 0, 1)
        cached: true
    }
    // the surface: the card merged with its island, minus the island (it draws itself)
    ShaderEffect {
        readonly property real m: 40                     // room for the neck and the fillets
        readonly property real y0: Look.top - 2         // from just above the islands
        x: -m
        y: y0 - card.y
        width: card.width + 2 * m
        height: card.y + card.height + m - y0
        visible: !!card.isl
        property vector4d body: Qt.vector4d(m, card.y - y0, card.width, card.height)
        property vector4d bodyR: Qt.vector4d(16 - 16 * (card.gapL >= -1 ? card.k : 0), 16 - 16 * (card.gapR >= -1 ? card.k : 0),
            Math.min(20, card.height / 2), Math.min(20, card.height / 2))
        property vector4d isle: card.isl ? Qt.vector4d(card.isl.x - card.x + m, card.isl.y - y0, card.isl.width, card.isl.height)
            : Qt.vector4d(0, 0, 0, 0)
        property vector4d isleR: card.isl ? Qt.vector4d(card.isl.topLeftRadius, card.isl.topRightRadius,
            card.isl.bottomRightRadius, card.isl.bottomLeftRadius) : Qt.vector4d(0, 0, 0, 0)
        property vector4d fill: Qt.vector4d(Look.surface.r, Look.surface.g, Look.surface.b, Look.surface.a)
        property vector2d res: Qt.vector2d(width, height)
        property real goo: card.goo
        property real dpr: card.dpr
        property real fL: card.clamp(Math.abs(card.gapL) / 8, 0, 1)
        property real fR: card.clamp(Math.abs(card.gapR) / 8, 0, 1)
        property real ox: card.originX - card.x + m
        property vector4d ages: {
            const a = Visualizer.beatAts, t = Visualizer.t
            return Qt.vector4d(t - a.x, t - a.y, t - a.z, t - a.w)
        }
        property vector4d punches: Visualizer.beatPows
        property real dur: Visualizer.waveDur
        property real reach: Visualizer.waveReach
        property vector4d kr: Visualizer.beatR
        property vector4d kg: Visualizer.beatG
        property vector4d kb: Visualizer.beatB
        property color c2: Player.c2
        fragmentShader: Qt.resolvedUrl("../shaders/goo.frag.qsb?v=33fbdde2")
    }

    Item {
        anchors.fill: parent
        clip: true
        Pane { id: la }
        Pane { id: lb }
    }

    // ---- opening, switching, closing ----
    readonly property var files: ({ sys: "Sys", ws: "Ws", wins: "Wins", media: "Media", caf: "Caf", cal: "Cal", meet: "Meet",
        net: "Net", priv: "Priv", tray: "Tray", bt: "Bt", bat: "Bat", bri: "Bri", vol: "Vol", notif: "Notif", quick: "Quick",
        toast: "Toast", level: "Level", clip: "Clip", auth: "Auth" })
    // the island the item lives in: its ancestor (a point test picked the left island for the
    // clock whenever a long window title ran the two islands edge to edge)
    function islandOf(h) {
        for (let p = h; p; p = p.parent) for (const i of islands) if (p === i) return i
        for (const i of islands) if (i.contains(i.mapFromItem(h, h.width / 2, h.height / 2))) return i
        return null
    }
    // `as`: a panel other than the Hit's own to hang from it (the bell's notification drop)
    function attach(h, as) {
        if (!h?.key) return
        const k = as ?? h.key
        if (open && !closing && h === it && k === key) return
        if (closing && h === it && k === key) { closing = false; open = true; endT.stop(); shrink.stop(); grow.start(); cur.fadeIn(0, 300); ctl.hot = h; return }
        const name = k.split(":")[0]
        const next = cur === la ? lb : la
        next.load(Qt.resolvedUrl(`panels/${files[name]}.qml`), { arg: h.arg ?? k.split(":")[1], ctl: ctl, hit: h })
        key = k
        const prev = cur
        const fresh = !open || closing
        endT.stop()
        if (fresh) {
            prev.clear()
            closing = false
            shrink.stop()
            grab(h); p = 0
            it = h; isl = islandOf(h); cur = next
            open = true
            grow.start()
            next.fadeIn(160, 480)
        } else {
            it = h; isl = islandOf(h); cur = next
            prev.fadeOut()
            next.fadeIn(80, 420)
        }
        ctl.hot = h
    }
    function detach() {
        if (!open) return
        grow.stop()
        if (it) grab(it)
        closing = true
        open = false
        cur.fadeOut()
        shrink.start()
        endT.restart()
    }
    Timer {
        id: endT
        interval: 270 * Look.speed
        onTriggered: {
            if (!card.closing) return
            card.closing = false
            la.clear(); lb.clear()
            card.it = null; card.isl = null; card.key = ""
            card.ctl.hot = null
        }
    }

    // one of the two panes the content cross-fades between. Coming in, it focuses from the
    // top down (shaders/reveal.frag): each line fades in, sharpens and drops into place in turn.
    // The effect layer exists only while that runs (rule 17).
    component Pane: Loader {
        id: pane
        x: card.padX
        y: card.padT
        property real reveal: 1
        opacity: 0
        visible: opacity > 0
        asynchronous: false
        layer.enabled: reveal < 1 && opacity > 0
        layer.effect: ShaderEffect {
            property real progress: pane.reveal
            property real band: 0.35
            property real blur: 7
            property real lift: 10
            property vector2d res: Qt.vector2d(pane.width, pane.height)
            fragmentShader: Qt.resolvedUrl("../shaders/reveal.frag.qsb?v=7f4a7165")
        }
        function load(url, props) { fade.stop(); opacity = 0; reveal = 0; setSource(url, props) }
        function clear() { fade.stop(); opacity = 0; source = "" }
        function fadeIn(delay, length) {
            fade.stop()
            wait.duration = delay * Look.speed
            to.to = 1; to.duration = 1
            sweep.from = 0; sweep.duration = length * Look.speed
            fade.start()
        }
        function fadeOut() {
            fade.stop()
            wait.duration = 0
            to.to = 0; to.duration = 90 * Look.speed
            sweep.from = reveal; sweep.duration = 0
            fade.start()
        }
        SequentialAnimation {
            id: fade
            PauseAnimation { id: wait }
            ParallelAnimation {
                NumberAnimation { id: to; target: pane; property: "opacity"; easing.type: Easing.BezierSpline; easing.bezierCurve: Look.curves.effects }
                NumberAnimation { id: sweep; target: pane; property: "reveal"; to: 1; easing.type: Easing.BezierSpline; easing.bezierCurve: Look.curves.enter }
            }
            ScriptAction { script: if (pane.opacity === 0 && pane !== card.cur) pane.source = "" }
        }
    }
}
