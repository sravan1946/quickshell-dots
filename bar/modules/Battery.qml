import QtQuick
import Quickshell.Services.UPower
import qs
import qs.components

// battery: click toggles time remaining.
Mod {
    readonly property var icons: [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
    readonly property var dev: UPower.displayDevice
    readonly property int cap: Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage)
    readonly property int st: dev.state
    readonly property bool plugged: st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge   // waybar "Full" uses the plain format
    readonly property string ico: Util.pick(icons, cap)
    readonly property int secs: st === UPowerDeviceState.Charging ? dev.timeToFull : dev.timeToEmpty
    readonly property string time: secs > 0 ? `${Math.floor(secs / 3600)} h ${Math.floor(secs % 3600 / 60)} min` : ""
    property bool alt: false
    // waybar battery states (Settings.batteryWarn / batteryLow) while discharging; the low notification is in shell.qml
    readonly property bool draining: st === UPowerDeviceState.Discharging

    fg: draining && cap <= Settings.batteryLow ? "#f7768e" : draining && cap <= Settings.batteryWarn ? "#e0af68" : Theme.mainFg

    visible: dev.isPresent
    minChars: 6   // "ico 100%": the right section is right-anchored, so 99 -> 100 would nudge the pills
    text: alt ? `${time} ${ico}` : plugged ? `${Theme.g(0xF1E6)} ${cap}%` : `${ico} ${cap}%`
    tip: st === UPowerDeviceState.Charging ? `Time to full: ${time}`
        : st === UPowerDeviceState.Discharging ? `Time to empty: ${time}` : UPowerDeviceState.toString(st)
    onClicked: b => { if (b === Qt.LeftButton) alt = !alt }
}
