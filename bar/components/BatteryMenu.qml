import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// The panel the battery pill opens (modules/Battery.qml), laid out like the Wi-Fi and
// Bluetooth ones: the charge with what it's doing and how long it'll take, the power
// last 12 hours of charge (UPower's own history), the power profile (power-profiles-daemon),
// then the battery's health, wear and draw. Cycle count and the charge limit aren't in UPower,
// so they're read from sysfs.
Dropdown {
    id: menu

    // the laptop battery itself: the display device is an aggregate without health
    readonly property var bat: UPower.devices.values.find(d => d.isLaptopBattery) ?? UPower.displayDevice
    readonly property int cap: Math.round(bat.percentage <= 1 ? bat.percentage * 100 : bat.percentage)
    readonly property int st: bat.state
    readonly property bool charging: st === UPowerDeviceState.Charging
    readonly property bool draining: st === UPowerDeviceState.Discharging
    readonly property int secs: charging ? bat.timeToFull : draining ? bat.timeToEmpty : 0
    readonly property string time: secs > 0 ? (secs >= 3600 ? `${Math.floor(secs / 3600)} h ` : "") + `${Math.floor(secs % 3600 / 60)} min` : ""
    readonly property color level: draining && cap <= Settings.batteryLow ? "#f7768e"
        : draining && cap <= Settings.batteryWarn ? "#e0af68" : Theme.actBg

    // sysfs, read while open: power_supply/<battery>/{cycle_count, charge_control_end_threshold}
    readonly property string sys: bat.nativePath ? "/sys/class/power_supply/" + bat.nativePath.split("/").pop() : ""
    readonly property int cycles: parseInt(cycleFile.text()) || 0
    readonly property int limit: parseInt(limitFile.text()) || 100
    FileView { id: cycleFile; path: menu.sys ? menu.sys + "/cycle_count" : "" }
    FileView { id: limitFile; path: menu.sys ? menu.sys + "/charge_control_end_threshold" : "" }
    onVisibleChanged: if (visible) { cycleFile.reload(); limitFile.reload(); histGet.running = true }

    // UPower's charge history over D-Bus (its files under /var/lib/upower are root-only):
    // [time, percent, state] newest first, logged on every change. State 0 ("unknown") is a
    // bogus sample upower writes at boot, so it's dropped.
    readonly property int span: 12 * 3600
    property var hist: []
    Process {
        id: histGet
        command: ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower",
            "/org/freedesktop/UPower/devices/battery_" + menu.sys.split("/").pop(),
            "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", String(menu.span), "300"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { menu.hist = JSON.parse(text).data[0].filter(p => p[2] !== 0).reverse() } catch (e) { menu.hist = [] }
            }
        }
    }

    closeOnOutsideClick: true
    padX: 12
    padY: 12

    Column {
        width: 320
        spacing: 12

        // ---- the charge ----
        Card {
            accent: menu.charging
            width: parent.width
            height: charge.implicitHeight + 24
            Column {
                id: charge
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10
                RowLayout {
                    width: parent.width
                    spacing: 12
                    Text {
                        text: menu.charging ? Theme.g(0xF0084) : Util.pick(Util.batteryIcons, menu.cap)   // battery-charging
                        color: menu.level
                        font { family: Theme.font; pixelSize: 30 }
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: menu.cap + "%"
                            color: Theme.mainFg
                            font { family: Theme.font; pixelSize: 22; bold: true }
                        }
                        Text {
                            width: parent.width
                            text: menu.charging ? "Charging" + (menu.time ? ` · ${menu.time} to full` : "")
                                : menu.draining ? "On battery" + (menu.time ? ` · ${menu.time} left` : "")
                                : menu.st === UPowerDeviceState.FullyCharged ? "Fully charged"
                                : menu.st === UPowerDeviceState.PendingCharge ? "Plugged in, not charging"
                                : UPowerDeviceState.toString(menu.st)
                            color: Theme.mainFg
                            opacity: 0.6
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                }
                Rectangle {   // the level
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.alpha(Theme.mainFg, 0.1)
                    Rectangle {
                        width: parent.width * menu.cap / 100
                        height: parent.height
                        radius: 3
                        color: menu.level
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {   // where charging stops, when a limit is set
                        visible: menu.limit < 100
                        x: parent.width * menu.limit / 100 - 1
                        y: -2
                        width: 2
                        height: parent.height + 4
                        radius: 1
                        color: Theme.mainFg
                        opacity: 0.6
                    }
                }
            }
        }

        // ---- the last 12 hours: charge over time, shaded where it was charging ----
        ListHeader { width: parent.width; text: "Last 12 hours" }
        Column {
            width: parent.width
            spacing: 4
            Canvas {
                id: graph
                width: parent.width
                height: 64
                // hist plus where it is right now (upower logs nothing while the level holds)
                readonly property var pts: menu.hist.concat([[Date.now() / 1000, menu.cap, menu.charging ? 1 : 2]])
                onPtsChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const now = Date.now() / 1000, p = pts
                    const x = t => width * (1 - (now - t) / menu.span)
                    const y = v => height - 2 - v / 100 * (height - 4)
                    // gridlines at 0 / 50 / 100
                    ctx.fillStyle = Qt.alpha(Theme.mainFg, 0.08)
                    for (const v of [0, 50, 100]) ctx.fillRect(0, Math.round(y(v)), width, 1)
                    if (p.length < 2) return
                    // charging stretches (state 1) as faint bands
                    ctx.fillStyle = Qt.alpha(Theme.actBg, 0.14)
                    for (let i = 0; i < p.length - 1; i++)
                        if (p[i][2] === 1) ctx.fillRect(x(p[i][0]), 0, x(p[i + 1][0]) - x(p[i][0]), height)
                    const line = () => { ctx.beginPath(); p.forEach((q, i) => i ? ctx.lineTo(x(q[0]), y(q[1])) : ctx.moveTo(x(q[0]), y(q[1]))) }
                    line()
                    ctx.lineTo(x(p[p.length - 1][0]), height); ctx.lineTo(x(p[0][0]), height); ctx.closePath()
                    ctx.fillStyle = Qt.alpha(menu.level, 0.25); ctx.fill()
                    line()
                    ctx.strokeStyle = menu.level; ctx.lineWidth = 1.6; ctx.lineJoin = "round"; ctx.stroke()
                }
            }
            Item {
                width: parent.width
                height: 12
                Repeater {
                    model: ["12h ago", "6h", "now"]
                    Text {
                        required property string modelData
                        required property int index
                        x: index === 0 ? 0 : index === 1 ? (parent.width - width) / 2 : parent.width - width
                        text: modelData
                        color: Theme.mainFg
                        opacity: 0.45
                        font { family: Theme.font; pixelSize: 10 }
                    }
                }
            }
        }

        // ---- power profile ----
        ListHeader { width: parent.width; text: "Power mode" }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            Round {
                icon: 0xF032A   // leaf
                label: "Saver"
                on: PowerProfiles.profile === PowerProfile.PowerSaver
                onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
            }
            Round {
                icon: 0xF05D1   // scale-balance
                label: "Balanced"
                on: PowerProfiles.profile === PowerProfile.Balanced
                onClicked: PowerProfiles.profile = PowerProfile.Balanced
            }
            Round {
                icon: 0xF14DE   // rocket-launch
                label: "Performance"
                on: PowerProfiles.profile === PowerProfile.Performance
                enabled: PowerProfiles.hasPerformanceProfile
                onClicked: PowerProfiles.profile = PowerProfile.Performance
            }
        }

        // ---- the battery itself ----
        ListHeader { width: parent.width; text: "Battery" }
        GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: 6
            rowSpacing: 6
            Cell {
                label: "Health"
                value: menu.bat.healthSupported ? Math.round(menu.bat.healthPercentage) + "% of new" : ""
            }
            Cell { label: "Cycles"; value: menu.cycles ? String(menu.cycles) : "" }
            Cell {
                label: menu.charging ? "Charging at" : "Draw"
                value: Math.abs(menu.bat.changeRate) > 0.05 ? Math.abs(menu.bat.changeRate).toFixed(1) + " W" : "idle"
            }
            Cell {
                label: "Energy"
                value: menu.bat.energyCapacity > 0 ? `${menu.bat.energy.toFixed(1)} / ${menu.bat.energyCapacity.toFixed(1)} Wh` : ""
            }
            Cell {
                visible: menu.limit < 100
                Layout.columnSpan: 2
                label: "Charge limit"
                value: menu.limit + "% (to spare the battery)"
            }
        }
    }
}
