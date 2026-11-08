import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs
import qs.islands

// The battery: charge and time, the last 12 hours, the power mode, and its health. Cycle
// count and the charge limit aren't in UPower, so they come from sysfs.
Panel {
    id: p
    implicitWidth: 290
    spacing: 9
    readonly property var bat: UPower.devices.values.find(d => d.isLaptopBattery) ?? UPower.displayDevice
    readonly property int cap: Math.round(bat.percentage <= 1 ? bat.percentage * 100 : bat.percentage)
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property bool draining: bat.state === UPowerDeviceState.Discharging
    readonly property int secs: charging ? bat.timeToFull : draining ? bat.timeToEmpty : 0
    readonly property string time: secs > 0 ? (secs >= 3600 ? `${Math.floor(secs / 3600)} h ` : "") + `${Math.floor(secs % 3600 / 60)} min` : ""
    readonly property color level: draining && cap <= Settings.batteryLow ? Look.alert
        : draining && cap <= Settings.batteryWarn ? Look.urgent : charging ? Look.good : Look.accent
    readonly property string sys: bat.nativePath ? "/sys/class/power_supply/" + bat.nativePath.split("/").pop() : ""
    FileView { id: cycleFile; path: p.sys ? p.sys + "/cycle_count" : "" }
    FileView { id: limitFile; path: p.sys ? p.sys + "/charge_control_end_threshold" : "" }
    readonly property int limit: parseInt(limitFile.text()) || 100

    // UPower's charge history over D-Bus: [time, percent, state] newest first; state 0 is a bogus boot sample
    readonly property int span: 12 * 3600
    property var hist: []
    Component.onCompleted: histGet.running = true
    Process {
        id: histGet
        command: ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower",
            "/org/freedesktop/UPower/devices/battery_" + p.sys.split("/").pop(),
            "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", String(p.span), "300"]
        stdout: StdioCollector {
            onStreamFinished: { try { p.hist = JSON.parse(text).data[0].filter(x => x[2] !== 0).reverse() } catch (e) { p.hist = [] } }
        }
    }

    Head { text: "Battery"; note: p.bat.healthSupported ? "health " + Math.round(p.bat.healthPercentage) + "%" : "" }
    Item {
        width: parent.width
        height: 26
        T { text: p.cap + "%"; font.pixelSize: 22; font.weight: Font.Bold; anchors.bottom: parent.bottom }
        T {
            anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 3 }
            text: p.charging ? "charging" + (p.time ? ` · full in ${p.time}` : "")
                : p.draining ? (p.time ? `${p.time} left` : "on battery")
                : p.bat.state === UPowerDeviceState.FullyCharged ? "fully charged" : "plugged in"
            color: Look.dim
            font.pixelSize: Look.small
        }
    }
    Rectangle {
        width: parent.width
        height: 8
        radius: 4
        color: Qt.alpha("white", 0.1)
        Rectangle { width: parent.width * p.cap / 100; height: parent.height; radius: 4; color: p.level; Behavior on width { Anim {} } }
        Rectangle { visible: p.limit < 100; x: parent.width * p.limit / 100 - 1; y: -2; width: 2; height: 12; radius: 1; color: Look.dim }
    }
    Canvas {
        id: graph
        width: parent.width
        height: 46
        readonly property var pts: p.hist.concat([[Date.now() / 1000, p.cap, p.charging ? 1 : 2]])
        onPtsChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const now = Date.now() / 1000, q = pts
            const x = t => width * (1 - (now - t) / p.span)
            const y = v => height - 2 - v / 100 * (height - 4)
            if (q.length < 2) return
            ctx.fillStyle = Qt.alpha(Look.good, 0.12)
            for (let i = 0; i < q.length - 1; i++) if (q[i][2] === 1) ctx.fillRect(x(q[i][0]), 0, x(q[i + 1][0]) - x(q[i][0]), height)
            const line = () => { ctx.beginPath(); q.forEach((s, i) => i ? ctx.lineTo(x(s[0]), y(s[1])) : ctx.moveTo(x(s[0]), y(s[1]))) }
            line(); ctx.lineTo(x(q[q.length - 1][0]), height); ctx.lineTo(x(q[0][0]), height); ctx.closePath()
            ctx.fillStyle = Qt.alpha(p.level, 0.2); ctx.fill()
            line(); ctx.strokeStyle = p.level; ctx.lineWidth = 1.5; ctx.lineJoin = "round"; ctx.stroke()
        }
    }
    GridLayout {
        width: parent.width
        columns: 2
        rowSpacing: 3
        Repeater {
            model: [
                [p.charging ? "Charging at" : "Power draw", Math.abs(p.bat.changeRate) > 0.05 ? Math.abs(p.bat.changeRate).toFixed(1) + " W" : "idle"],
                ["Cycles", parseInt(cycleFile.text()) || "–"],
                ["Charge limit", p.limit < 100 ? p.limit + "%" : "none"]]
            Item {
                required property var modelData
                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: 16
                T { text: parent.modelData[0]; color: Look.dim; font.pixelSize: Look.small }
                T { anchors.right: parent.right; text: String(parent.modelData[1]); font.pixelSize: Look.small }
            }
        }
    }
    // power mode (power-profiles-daemon)
    Rectangle {
        width: parent.width
        height: 32
        radius: 11
        color: Look.raise
        Row {
            anchors { fill: parent; margins: 3 }
            Repeater {
                model: [["Saver", PowerProfile.PowerSaver], ["Balanced", PowerProfile.Balanced], ["Performance", PowerProfile.Performance]]
                Rectangle {
                    required property var modelData
                    readonly property bool on: PowerProfiles.profile === modelData[1]
                    width: (parent.width) / 3
                    height: parent.height
                    radius: 8
                    color: on ? Look.accent : hov.hovered ? Look.hover : "transparent"
                    opacity: modelData[1] !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile ? 1 : 0.4
                    Behavior on color { Fade {} }
                    T { anchors.centerIn: parent; text: parent.modelData[0]; font.pixelSize: Look.small; color: parent.on ? Look.accentInk : Look.dim; font.weight: parent.on ? Font.DemiBold : Font.Normal }
                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: PowerProfiles.profile = parent.modelData[1] }
                }
            }
        }
    }
}
