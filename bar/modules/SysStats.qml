import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.components

// cpu / ram / temp: arc gauges, numbers rolling to each sample. A gauge warms from its colour
// to amber and red, glowing more as it goes; cpu and ram pulse past 90%. Hover: a card
// with the graph, per-core bars, the memory breakdown and load, poured out of the point where
// the pointer rested and eaten away from where it left (components/HoverCard). Click: btop.
// Sampled once in SysMon.qml for every bar. Keep the roll short: every animation frame
// repaints the whole bar (700ms cost ~4% qs CPU, 300ms is in the noise).
Mod {
    id: s

    readonly property color colCpu: Theme.color(Settings.sysColCpu, "#7dcfff")
    readonly property color colRam: Theme.color(Settings.sysColRam, "#bb9af7")
    readonly property color colTemp: Theme.color(Settings.sysColTemp, "#9ece6a")
    readonly property color amber: "#e0af68"
    readonly property color red: "#f7768e"

    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    // own colour up to `warm`, amber by `hot`, red 15 past that
    function heat(base, v, warm = 60, hot = 80) {
        return v < warm ? base : v < hot ? mix(base, amber, (v - warm) / (hot - warm))
            : mix(amber, red, Math.min(1, (v - hot) / 15))
    }
    function gib(kb) { return (kb / 1048576).toFixed(1) }
    function since(t) {
        const d = Math.floor(t / 86400), h = Math.floor(t % 86400 / 3600), m = Math.floor(t % 3600 / 60)
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
    }

    implicitWidth: gauges.implicitWidth + 12
    onClicked: b => { hover.close(); if (b === Qt.LeftButton) Util.run("kitty -e btop") }

    Row {
        id: gauges
        anchors.centerIn: parent
        spacing: 5
        Gauge { value: SysMon.cpu; base: s.colCpu; glyph: 0xF0EE0 }
        Gauge { value: SysMon.ram; base: s.colRam; glyph: 0xEFC5 }
    }

    // ---- hover card ----
    HoverCard { id: hover; content: card; glow: s.colCpu }
    Component {
        id: card
        Column {
            width: 270
            spacing: 9

            RowLayout {
                width: parent.width
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: SysMon.model || "CPU"
                    color: Theme.mainFg
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
                Chip {
                    visible: SysMon.temp > 0
                    col: s.heat(s.colTemp, SysMon.temp, 90, 100)
                    text: Theme.g(0xF050F) + " " + Math.round(SysMon.temp) + "°C"
                }
            }

            // two-minute graph
            Rectangle {
                width: parent.width
                height: 84
                radius: 9
                color: Qt.alpha(Theme.mainFg, 0.06)
                clip: true
                // lines start below the legend so they never cross it
                Spark { anchors { fill: parent; topMargin: 24 } samples: 60; lineWidth: 1.5; fillAlpha: 0.45 }
                Row {
                    x: 8; y: 5
                    spacing: 8
                    Text { text: "● cpu " + Math.round(SysMon.cpu) + "%"; color: s.colCpu; font { family: Theme.font; pixelSize: 10; bold: true } }
                    Text { text: "● ram " + Math.round(SysMon.ram) + "%"; color: s.colRam; font { family: Theme.font; pixelSize: 10; bold: true } }
                    Text { visible: SysMon.temp > 0; text: "● temp " + Math.round(SysMon.temp) + "°"; color: s.colTemp; font { family: Theme.font; pixelSize: 10; bold: true } }
                }
                Text {
                    anchors { right: parent.right; top: parent.top; topMargin: 6; rightMargin: 8 }
                    text: "2 min"
                    color: Theme.mainFg
                    opacity: 0.4
                    font { family: Theme.font; pixelSize: 9 }
                }
            }

            // one bar per core
            Item {
                width: parent.width
                height: 30
                Row {
                    id: cores
                    anchors.fill: parent
                    spacing: 3
                    Repeater {
                        model: SysMon.cores.length
                        Rectangle {
                            required property int index
                            readonly property real v: SysMon.cores[index] ?? 0
                            width: (cores.width - cores.spacing * (SysMon.cores.length - 1)) / SysMon.cores.length
                            height: parent.height
                            radius: 3
                            color: Qt.alpha(Theme.mainFg, 0.08)
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: Math.max(2, parent.height * parent.v / 100)
                                radius: 3
                                gradient: Gradient {
                                    GradientStop { position: 0; color: s.heat(s.colCpu, v) }
                                    GradientStop { position: 1; color: Qt.alpha(s.heat(s.colCpu, v), 0.35) }
                                }
                                Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // memory: used | cache | free
            Column {
                width: parent.width
                spacing: 4
                RowLayout {
                    width: parent.width
                    Text { text: "Memory"; color: Theme.mainFg; opacity: 0.6; font { family: Theme.font; pixelSize: 11 } }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: `${s.gib(SysMon.memUsed)} / ${s.gib(SysMon.memTotal)} GiB`
                        color: s.colRam
                        font { family: Theme.font; pixelSize: 11; bold: true }
                    }
                }
                Meter {
                    used: SysMon.memUsed / Math.max(1, SysMon.memTotal)
                    cache: SysMon.memCache / Math.max(1, SysMon.memTotal)
                }
                Text {
                    text: `cache ${s.gib(SysMon.memCache)} GiB · free ${s.gib(SysMon.memTotal - SysMon.memUsed - SysMon.memCache)} GiB`
                    color: Theme.mainFg
                    opacity: 0.5
                    font { family: Theme.font; pixelSize: 10 }
                }
            }

            Column {
                visible: SysMon.swapTotal > 0
                width: parent.width
                spacing: 4
                RowLayout {
                    width: parent.width
                    Text { text: "Swap"; color: Theme.mainFg; opacity: 0.6; font { family: Theme.font; pixelSize: 11 } }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: `${s.gib(SysMon.swapUsed)} / ${s.gib(SysMon.swapTotal)} GiB`
                        color: Theme.mainFg
                        font { family: Theme.font; pixelSize: 11; bold: true }
                    }
                }
                Meter { height: 4; used: SysMon.swapUsed / Math.max(1, SysMon.swapTotal) }
            }

            Text {
                width: parent.width
                text: `load ${SysMon.load.map(l => l.toFixed(2)).join("  ")}  ·  up ${s.since(SysMon.uptime)}`
                color: Theme.mainFg
                opacity: 0.55
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 10 }
            }
        }
    }

    // ---- pieces ----

    // 270° arc with the icon inside and the number beside it; full arc at `max`
    component Gauge: Row {
        id: g
        property real value: 0
        property color base
        property int glyph
        property string unit: "%"
        property real min: 0
        property real max: 100
        property real warm: 60
        property real hot: 80
        property bool pulses: true
        // rolls only when the shown integer changes: each roll repaints the bar for 300ms
        property real shown: Math.round(value)
        readonly property real frac: Math.max(0, Math.min(1, (shown - min) / (max - min)))
        Behavior on shown { enabled: Settings.numberRoll; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        readonly property color col: s.heat(base, shown, warm, hot)
        // breathes past 90%
        property real pulse: 0
        SequentialAnimation on pulse {
            running: g.pulses && g.value >= 90
            loops: Animation.Infinite
            onRunningChanged: if (!running) g.pulse = 0
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 600; easing.type: Easing.InOutSine }
        }

        spacing: 3
        anchors.verticalCenter: parent?.verticalCenter

        Item {
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter
            // drawn 6px larger each side so the glow isn't clipped by the layer
            Shape {
                anchors.centerIn: parent
                width: 32
                height: 32
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: g.col
                    shadowBlur: 0.8
                    blurMax: 10
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    // faint at rest, strong when pegged
                    shadowOpacity: 0.15 + 0.75 * Math.max(0, (g.frac - 0.4) / 0.6) * (1 - 0.4 * g.pulse)
                }
                ShapePath {
                    strokeColor: Qt.alpha(g.base, 0.18)
                    strokeWidth: 2.2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 16; centerY: 16; radiusX: 8.6; radiusY: 8.6; startAngle: 135; sweepAngle: 270 }
                }
                ShapePath {
                    strokeColor: g.col
                    strokeWidth: 2.2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 16; centerY: 16; radiusX: 8.6; radiusY: 8.6; startAngle: 135; sweepAngle: 270 * Math.max(0.005, g.frac) }
                }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 0.5
                text: Theme.g(g.glyph)
                color: g.col
                font { family: Theme.font; pixelSize: 9 }
            }
        }
        // plain text, not StyledText: styled Text takes hover, which robbed the module's
        // MouseArea underneath and closed the card with the pointer over the number
        Item {
            anchors.verticalCenter: parent.verticalCenter
            // fixed so neighbours don't shift; a rare 100% just nudges them
            width: Math.max(num.implicitWidth + unit.implicitWidth, pctMetrics.advanceWidth("99%"))
            height: num.implicitHeight
            Text {
                id: num
                text: Math.round(g.shown)
                color: Theme.menuFg
                font: pctMetrics.font
            }
            Text {
                id: unit
                x: num.implicitWidth
                text: g.unit
                color: Qt.alpha(Theme.menuFg, 0.45)
                font: pctMetrics.font
            }
            FontMetrics { id: pctMetrics; font { family: Theme.font; pixelSize: Theme.fontSize + 1; bold: true } }
        }
    }

    // cpu as a gradient-filled area, ram and temp (°C on the same axis) as lines; fixed 0..100 scale
    component Spark: Canvas {
        property int samples: 30
        property real lineWidth: 1.2
        property real fillAlpha: 0.6
        readonly property var data: SysMon.hist.slice(-samples)
        onDataChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const h = data
            if (h.length < 2) return
            const step = width / (samples - 1)
            const x = i => width - (h.length - 1 - i) * step
            const y = v => height - lineWidth - Math.min(100, v) / 100 * (height - 2 * lineWidth)
            // temp reads 0 until the sensor is found: start its line at the first real sample
            const path = k => {
                ctx.beginPath()
                let on = false
                h.forEach((p, i) => {
                    if (k === 2 && !(p[2] > 0)) return
                    on ? ctx.lineTo(x(i), y(p[k])) : ctx.moveTo(x(i), y(p[k]))
                    on = true
                })
            }
            path(0)
            ctx.lineTo(width, height); ctx.lineTo(x(0), height); ctx.closePath()
            const grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Qt.alpha(s.colCpu, fillAlpha))
            grad.addColorStop(1, Qt.alpha(s.colCpu, 0.03))
            ctx.fillStyle = grad; ctx.fill()
            path(0)
            ctx.strokeStyle = s.colCpu; ctx.lineWidth = lineWidth; ctx.stroke()
            path(1)
            ctx.strokeStyle = s.colRam; ctx.lineWidth = lineWidth; ctx.stroke()
            if (SysMon.temp > 0) {
                path(2)
                ctx.setLineDash([3, 2])   // dashed: a different unit from the two % lines
                ctx.strokeStyle = s.colTemp; ctx.lineWidth = lineWidth; ctx.stroke()
            }
        }
    }

    // segmented bar: used (solid), cache (faint), rest is track
    component Meter: Rectangle {
        id: mt
        property real used: 0
        property real cache: 0
        width: parent.width
        height: 7
        radius: height / 2
        color: Qt.alpha(Theme.mainFg, 0.08)
        clip: true
        Rectangle {
            x: mt.width * mt.used
            width: mt.width * mt.cache
            height: parent.height
            color: Qt.alpha(s.colRam, 0.3)
            Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            width: mt.width * mt.used
            height: parent.height
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(s.colRam, 0.6) }
                GradientStop { position: 1; color: s.heat(s.colRam, mt.used * 100, 70, 85) }
            }
            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
    }

    component Chip: Rectangle {
        property alias text: t.text
        property color col
        implicitWidth: t.implicitWidth + 14
        implicitHeight: t.implicitHeight + 6
        radius: height / 2
        color: Qt.alpha(col, 0.15)
        border { width: 1; color: Qt.alpha(col, 0.4) }
        Text { id: t; anchors.centerIn: parent; color: parent.col; font { family: Theme.font; pixelSize: 11; bold: true } }
    }
}
