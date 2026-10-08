import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// The panel the battery pill opens (modules/Battery.qml), laid out like the Wi-Fi and
// Bluetooth ones: the charge with what it's doing and how long it'll take, the power
// profile (power-profiles-daemon), then the battery's health, wear and draw. Cycle count and
// the charge limit aren't in UPower, so they're read from sysfs.
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
    onVisibleChanged: if (visible) { cycleFile.reload(); limitFile.reload() }

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
