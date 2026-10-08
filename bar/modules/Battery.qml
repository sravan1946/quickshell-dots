import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.components

// battery: click opens the battery panel (components/BatteryMenu).
Mod {
    id: battery
    readonly property var dev: UPower.displayDevice
    readonly property int cap: Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage)
    readonly property int st: dev.state
    readonly property bool plugged: st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge   // waybar "Full" uses the plain format
    readonly property string ico: Util.pick(Util.batteryIcons, cap)
    readonly property int secs: st === UPowerDeviceState.Charging ? dev.timeToFull : dev.timeToEmpty
    readonly property string time: secs > 0 ? `${Math.floor(secs / 3600)} h ${Math.floor(secs % 3600 / 60)} min` : ""
    // waybar battery states (Settings.batteryWarn / batteryLow) while discharging; the low notification is in shell.qml
    readonly property bool draining: st === UPowerDeviceState.Discharging

    fg: draining && cap <= Settings.batteryLow ? "#f7768e" : draining && cap <= Settings.batteryWarn ? "#e0af68" : Theme.mainFg

    visible: dev.isPresent
    minChars: 6   // "ico 100%": the right section is right-anchored, so 99 -> 100 would nudge the pills
    text: plugged ? `${Theme.g(0xF1E6)} ${cap}%` : `${ico} ${cap}%`
    tip: st === UPowerDeviceState.Charging ? `Time to full: ${time}`
        : st === UPowerDeviceState.Discharging ? `Time to empty: ${time}` : UPowerDeviceState.toString(st)
    onClicked: b => { if (b === Qt.LeftButton) panel.item.toggle() }
    LazyLoader { id: panel; active: battery.visible; BatteryMenu { target: battery } }
}
