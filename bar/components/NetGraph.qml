import QtQuick
import qs

// Rate graph of NetStats.hist, newest sample on the right: download as a filled
// area, upload as a line. Scaled to the peak of what's shown, with a floor so an
// idle link draws flat instead of amplifying noise.
Canvas {
    id: g

    property int samples: 30
    property real floor: 50000
    property color down: "#99ffdd"
    property color up: "#ffcc66"
    property real fillAlpha: 0.45
    property real lineWidth: 1.2
    readonly property var data: NetStats.hist.slice(-samples)
    readonly property real peak: Math.max(0, ...data.map(p => Math.max(p[0], p[1])))

    onDataChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const h = data
        if (h.length < 2) return
        const top = Math.max(floor, peak) * 1.1
        const step = width / (samples - 1)
        const x = i => width - (h.length - 1 - i) * step
        const y = v => height - v / top * height
        const path = k => { ctx.beginPath(); h.forEach((p, i) => i ? ctx.lineTo(x(i), y(p[k])) : ctx.moveTo(x(i), y(p[k]))) }
        path(0)
        ctx.lineTo(width, height); ctx.lineTo(x(0), height); ctx.closePath()
        ctx.fillStyle = Qt.alpha(down, fillAlpha); ctx.fill()
        path(0)
        ctx.strokeStyle = down; ctx.lineWidth = lineWidth; ctx.stroke()
        path(1)
        ctx.strokeStyle = up; ctx.lineWidth = lineWidth; ctx.stroke()
    }
}
