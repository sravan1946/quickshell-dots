pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs

// The battery as the bar shows it: level, glyph and the colour it warns in.
Singleton {
    readonly property var dev: UPower.displayDevice
    readonly property int cap: Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage)
    readonly property int st: dev.state
    // plugged in, so full-on-AC counts too: it stays green with the bolt
    readonly property bool charging: st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge
        || st === UPowerDeviceState.FullyCharged
    readonly property bool draining: st === UPowerDeviceState.Discharging
    readonly property int glyph: charging ? 0xF0084 : Util.batteryIcons[Math.max(0, Math.min(10, Math.floor(cap / 10)))]
    readonly property color colour: draining && cap <= Settings.batteryLow ? Look.alert
        : draining && cap <= Settings.batteryWarn ? Look.urgent
        : charging ? Look.good : Qt.alpha(Look.text, 0.86)
}
