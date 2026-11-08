import QtQuick
import qs
import qs.islands

// CPU and memory: the two-minute graph, a bar per core, memory and swap. Click the rings for btop.
Panel {
    id: p
    implicitWidth: 290
    function gib(kb) { return (kb / 1048576).toFixed(1) }
    function since(t) {
        const d = Math.floor(t / 86400), h = Math.floor(t % 86400 / 3600), m = Math.floor(t % 3600 / 60)
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
    }

    Head { text: SysMon.model || "CPU"; note: "up " + p.since(SysMon.uptime) }
    Item {
        width: parent.width
        height: 26
        T { text: Math.round(SysMon.cpu) + "%"; font.pixelSize: 22; font.weight: Font.Bold; anchors.bottom: parent.bottom }
        T {
            anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 3 }
            text: (SysMon.temp > 0 ? Math.round(SysMon.temp) + "°C · " : "") + "load " + SysMon.load.map(l => l.toFixed(2)).join(" ")
            color: Look.dim
            font.pixelSize: Look.small
        }
    }
    Canvas {
        id: graph
        width: parent.width
        height: 54
        readonly property var data: SysMon.hist.slice(-60)
        onDataChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const h = data
            if (h.length < 2) return
            const step = width / 59
            const x = i => width - (h.length - 1 - i) * step
            const y = v => height - 1 - Math.min(100, v) / 100 * (height - 3)
            ctx.beginPath()
            h.forEach((s, i) => i ? ctx.lineTo(x(i), y(s[0])) : ctx.moveTo(x(i), y(s[0])))
            ctx.lineTo(width, height); ctx.lineTo(x(0), height); ctx.closePath()
            const g = ctx.createLinearGradient(0, 0, 0, height)
            g.addColorStop(0, Qt.alpha(Look.cpu, 0.45)); g.addColorStop(1, Qt.alpha(Look.cpu, 0))
            ctx.fillStyle = g; ctx.fill()
            ctx.beginPath()
            h.forEach((s, i) => i ? ctx.lineTo(x(i), y(s[0])) : ctx.moveTo(x(i), y(s[0])))
            ctx.strokeStyle = Look.cpu; ctx.lineWidth = 1.6; ctx.stroke()
        }
    }
    Row {
        id: cores
        width: parent.width
        height: 28
        spacing: 2
        Repeater {
            model: SysMon.cores.length
            Item {
                required property int index
                width: (cores.width - cores.spacing * (SysMon.cores.length - 1)) / SysMon.cores.length
                height: cores.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(2, parent.height * (SysMon.cores[parent.index] ?? 0) / 100)
                    topLeftRadius: 2; topRightRadius: 2
                    color: Look.cpu
                    opacity: 0.8
                    Behavior on height { Anim { type: "effects"; duration: 600 * Look.speed } }
                }
            }
        }
    }
    Head { text: "Memory"; T { text: `${p.gib(SysMon.memUsed)} of ${p.gib(SysMon.memTotal)} GB`; font.pixelSize: Look.small } }
    Rectangle {
        width: parent.width
        height: 7
        radius: 4
        color: Qt.alpha("white", 0.1)
        clip: true
        Rectangle { width: parent.width * SysMon.memUsed / Math.max(1, SysMon.memTotal); height: parent.height; radius: 4; color: Look.ram }
        Rectangle {
            x: parent.width * SysMon.memUsed / Math.max(1, SysMon.memTotal)
            width: parent.width * SysMon.memCache / Math.max(1, SysMon.memTotal)
            height: parent.height
            color: Qt.alpha(Look.ram, 0.3)
        }
    }
    T {
        text: `${p.gib(SysMon.memCache)} GB cache` + (SysMon.swapTotal > 0 ? ` · swap ${p.gib(SysMon.swapUsed)} of ${p.gib(SysMon.swapTotal)} GB` : "") + " · click for btop"
        color: Look.dim
        font.pixelSize: Look.small
    }
}
