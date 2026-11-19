import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs
import qs.islands

// The battery as a runway: how long it lasts (the bar already shows the percentage) and when
// it runs out or fills. The graph is the road ahead, sized to reach the end (1 to 6 hours),
// and as long again behind: the charge so far (charging stretches tinted), a hairline at now, and the
// projection from now at the present rate, a shaded wedge down to empty or up to the charge
// limit (a dashed line across), ringed where it gets there. Under it the
// facts in one line, then the power mode. Cycle count and the limit come from sysfs.
Panel {
    id: p
    implicitWidth: 320
    spacing: 12
    readonly property var bat: UPower.devices.values.find(d => d.isLaptopBattery) ?? UPower.displayDevice
    readonly property int cap: Math.round(bat.percentage <= 1 ? bat.percentage * 100 : bat.percentage)
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property bool draining: bat.state === UPowerDeviceState.Discharging
    // the smoothed estimate (BatState), not UPower's instant one, so it holds still
    readonly property int secs: charging || draining ? BatState.secs : 0
    readonly property string sys: bat.nativePath ? "/sys/class/power_supply/" + bat.nativePath.split("/").pop() : ""
    FileView { id: cycleFile; path: p.sys ? p.sys + "/cycle_count" : "" }
    FileView { id: limitFile; path: p.sys ? p.sys + "/charge_control_end_threshold" : "" }
    readonly property int limit: parseInt(limitFile.text()) || 100
    readonly property bool held: !charging && !draining && limit < 100 && cap >= limit - 1
    readonly property color tone: draining && cap <= Settings.batteryLow ? Look.alert
        : draining && cap <= Settings.batteryWarn ? Look.urgent : charging ? Look.good : Look.accent

    function dur(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60)
        return h ? `${h} h ${String(m).padStart(2, "0")} min` : `${m} min`
    }
    function clock(s) { return Qt.formatTime(new Date(Date.now() + s * 1000), Settings.clock24h ? "HH:mm" : "h:mm AP").toLowerCase() }

    // UPower's charge history over D-Bus: [time, percent, state] newest first; state 0 is a bogus boot sample
    // the same span each side of now, so a slope is drawn at its real rate (4h back and 1h ahead
    // made a 53-minute drain look like a cliff)
    readonly property int ahead: (secs > 0 ? Math.max(1, Math.min(6, Math.ceil(secs / 3600))) : 2) * 3600
    readonly property int back: ahead
    property var hist: []
    Component.onCompleted: histGet.running = true
    Process {
        id: histGet
        command: ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower",
            "/org/freedesktop/UPower/devices/battery_" + p.sys.split("/").pop(),
            "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", "86400", "300"]
        stdout: StdioCollector {
            onStreamFinished: { try { p.hist = JSON.parse(text).data[0].filter(x => x[2] !== 0).reverse() } catch (e) { p.hist = [] } }
        }
    }

    // ---- how long ----
    Item {
        width: parent.width
        height: 46
        Column {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            T {
                text: p.held ? `Held at ${p.limit}%` : p.secs > 0 ? p.dur(p.secs)
                    : p.bat.state === UPowerDeviceState.FullyCharged ? "Fully charged" : p.charging ? "Charging" : p.draining ? "On battery" : "Plugged in"
                font.pixelSize: 22
                font.weight: Font.Bold
                color: p.draining && p.tone !== Look.accent ? p.tone : Look.text
                Behavior on color { Fade {} }
            }
            T {
                text: p.charging ? (p.secs > 0 ? `to ${p.limit < 100 ? p.limit + "%" : "full"}  ·  ${p.clock(p.secs)}` : "charging")
                    : p.draining ? (p.secs > 0 ? `left  ·  empty around ${p.clock(p.secs)}` : "on battery")
                    : p.held ? "the charge limit keeps it here" : "plugged in"
                color: Look.dim
                font.pixelSize: Look.small
            }
        }
        // the level, beside it: the bar has it, the graph is drawn against it
        Row {
            anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
            spacing: 4
            G { visible: p.charging; glyph: 0xF140B; font.pixelSize: 15; color: Look.good; anchors.verticalCenter: parent.verticalCenter }
            T { text: p.cap + "%"; font.pixelSize: 17; font.weight: Font.DemiBold; color: p.tone; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ---- the runway ----
    Rectangle {
        width: parent.width
        height: 96
        radius: 12
        color: Look.raise
        Canvas {
            id: graph
            x: 10; y: 10
            width: parent.width - 20
            height: 64
            readonly property real now: Date.now() / 1000
            readonly property var pts: p.hist.concat([[now, p.cap, p.charging ? 1 : 2]])
            readonly property real nowX: width * p.back / (p.back + p.ahead)
            function tx(t) { return nowX + (t - now) / (p.back + p.ahead) * width }
            function vy(v) { return height - 1 - v / 100 * (height - 2) }
            // the tail: where the present rate takes it, and when
            readonly property var tail: {
                if (p.secs <= 0) return null
                const to = p.charging ? p.limit : 0
                return { t: now + p.secs, v: to }
            }
            onPtsChanged: requestPaint()
            onTailChanged: requestPaint()
            onWidthChanged: requestPaint()
            onNowXChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                // UPower logs only on change: carry the last reading before the window to its edge
                const before = pts.filter(s => s[0] < now - p.back).pop()
                const q = (before ? [[now - p.back, before[1], before[2]]] : []).concat(pts.filter(s => s[0] >= now - p.back))
                // quarters, faint, so the line has something to sit in
                ctx.fillStyle = Qt.alpha(Look.text, 0.05)
                for (const g of [25, 50, 75]) ctx.fillRect(0, Math.round(vy(g)), width, 1)
                // charging stretches
                ctx.fillStyle = Qt.alpha(Look.good, 0.12)
                for (let i = 0; i < q.length - 1; i++)
                    if (q[i][2] === 1) ctx.fillRect(tx(q[i][0]), 0, tx(q[i + 1][0]) - tx(q[i][0]), height)
                // the charge so far
                if (q.length > 1) {
                    const line = () => { ctx.beginPath(); q.forEach((s, i) => i ? ctx.lineTo(tx(s[0]), vy(s[1])) : ctx.moveTo(tx(s[0]), vy(s[1]))) }
                    line(); ctx.lineTo(tx(q[q.length - 1][0]), height); ctx.lineTo(tx(q[0][0]), height); ctx.closePath()
                    const g = ctx.createLinearGradient(0, 0, 0, height)
                    g.addColorStop(0, Qt.alpha(p.tone, 0.28)); g.addColorStop(1, Qt.alpha(p.tone, 0.02))
                    ctx.fillStyle = g; ctx.fill()
                    line(); ctx.strokeStyle = p.tone; ctx.lineWidth = 1.6; ctx.lineJoin = "round"; ctx.stroke()
                }
                // the charge limit, across
                if (p.limit < 100) {
                    ctx.setLineDash([3, 3]); ctx.strokeStyle = Qt.alpha(Look.text, 0.35); ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(0, Math.round(vy(p.limit)) + 0.5); ctx.lineTo(width, Math.round(vy(p.limit)) + 0.5); ctx.stroke()
                }
                // the projection, from now at the present rate: a wedge, then its edge dashed
                if (tail) {
                    const end = Math.min(tail.t, now + p.ahead)
                    const v = p.cap + (tail.v - p.cap) * (end - now) / (tail.t - now)
                    ctx.beginPath(); ctx.moveTo(nowX, vy(p.cap)); ctx.lineTo(tx(end), vy(v))
                    ctx.lineTo(tx(end), height); ctx.lineTo(nowX, height); ctx.closePath()
                    const w = ctx.createLinearGradient(nowX, 0, tx(end), 0)
                    w.addColorStop(0, Qt.alpha(p.tone, 0.16)); w.addColorStop(1, Qt.alpha(p.tone, 0.03))
                    ctx.fillStyle = w; ctx.fill()
                    ctx.setLineDash([4, 3]); ctx.strokeStyle = p.tone; ctx.lineWidth = 1.6
                    ctx.beginPath(); ctx.moveTo(nowX, vy(p.cap)); ctx.lineTo(tx(end), vy(v)); ctx.stroke()
                }
                ctx.setLineDash([])
                // now
                ctx.fillStyle = Qt.alpha(Look.text, 0.5)
                ctx.fillRect(Math.round(nowX), 0, 1, height)
            }
            // the level now, on the line
            Rectangle {
                x: graph.nowX - 4; y: graph.vy(p.cap) - 4
                width: 8; height: 8; radius: 4
                color: p.tone
                border.width: 2
                border.color: Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 1)
            }
            // where the projection gets there (the clock time is in the header)
            Rectangle {
                id: arrive
                visible: !!graph.tail && graph.tail.t <= graph.now + p.ahead
                x: visible ? graph.tx(graph.tail.t) - 4 : 0
                y: visible ? Math.min(graph.height - 8, Math.max(0, graph.vy(graph.tail.v) - 4)) : 0
                width: 8; height: 8; radius: 4
                color: Qt.rgba(Look.raise.r, Look.raise.g, Look.raise.b, 1)
                border.width: 1.6
                border.color: p.tone
            }
            // a tail that runs past the edge says how far
            T {
                visible: !!graph.tail && graph.tail.t > graph.now + p.ahead
                anchors { right: parent.right; top: parent.top }
                text: "↦ " + p.dur(p.secs).replace(/ \d+ min$/, "")
                color: p.tone
                font.pixelSize: 9
                font.weight: Font.Bold
            }
            T {
                visible: p.limit < 100
                anchors.right: parent.right
                y: graph.vy(p.limit) + 2
                text: p.limit + "%"
                color: Look.faint
                font.pixelSize: 9
            }
        }
        // the time axis
        Item {
            x: 10
            width: parent.width - 20
            anchors { bottom: parent.bottom; bottomMargin: 6 }
            height: 12
            T { text: "−" + p.back / 3600 + "h"; color: Look.faint; font.pixelSize: 9 }
            T { x: graph.nowX - width / 2; text: "now"; color: Look.dim; font.pixelSize: 9; font.weight: Font.DemiBold }
            T { anchors.right: parent.right; text: "+" + p.ahead / 3600 + "h"; color: Look.faint; font.pixelSize: 9 }
        }
    }

    // ---- the facts, one line ----
    Row {
        width: parent.width
        Repeater {
            model: [
                [BatState.rate > 0.05 ? BatState.rate.toFixed(1) + " W" : "idle", p.charging ? "charging" : "draw"],
                [String(parseInt(cycleFile.text()) || "–"), "cycles"],
                [p.bat.healthSupported ? Math.round(p.bat.healthPercentage) + "%" : "–", "health"],
                [p.limit < 100 ? p.limit + "%" : "none", "limit"]
            ]
            Column {
                required property var modelData
                width: parent.width / 4
                T { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData[0]; font.pixelSize: 13; font.weight: Font.DemiBold }
                T { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData[1]; color: Look.faint; font.pixelSize: 10 }
            }
        }
    }

    // ---- power mode (power-profiles-daemon) ----
    Rectangle {
        id: modes
        readonly property var list: [[0xF032A, "Saver", PowerProfile.PowerSaver], [0xF05D1, "Balanced", PowerProfile.Balanced], [0xF04C5, "Performance", PowerProfile.Performance]]
        readonly property int at: Math.max(0, list.findIndex(m => m[2] === PowerProfiles.profile))
        width: parent.width
        height: 36
        radius: 12
        color: Look.raise
        // the selection slides between them
        Rectangle {
            x: 3 + modes.at * (modes.width - 6) / 3
            y: 3
            width: (modes.width - 6) / 3
            height: modes.height - 6
            radius: 9
            color: Look.accent
            Behavior on x { Anim { type: "fast" } }
        }
        Row {
            x: 3; y: 3
            Repeater {
                model: modes.list
                Item {
                    id: mode
                    required property var modelData
                    required property int index
                    readonly property bool on: modes.at === index
                    readonly property bool avail: modelData[2] !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                    width: (modes.width - 6) / 3
                    height: modes.height - 6
                    opacity: avail ? 1 : 0.4
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        G { glyph: mode.modelData[0]; font.pixelSize: 13; color: mode.on ? Look.accentInk : mh.hovered ? Look.text : Look.dim; anchors.verticalCenter: parent.verticalCenter }
                        T {
                            anchors.verticalCenter: parent.verticalCenter
                            text: mode.modelData[1]
                            font.pixelSize: Look.small
                            font.weight: mode.on ? Font.DemiBold : Font.Normal
                            color: mode.on ? Look.accentInk : mh.hovered ? Look.text : Look.dim
                        }
                    }
                    HoverHandler { id: mh; cursorShape: mode.avail ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { onTapped: if (mode.avail) PowerProfiles.profile = mode.modelData[2] }
                }
            }
        }
    }
}
