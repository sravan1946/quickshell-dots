pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// The battery as the bar shows it: level, glyph and the colour it warns in.
Singleton {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property int cap: Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage)
    readonly property int st: dev.state
    // plugged in, so full-on-AC counts too: it stays green with the bolt
    readonly property bool charging: st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge
        || st === UPowerDeviceState.FullyCharged
    readonly property bool draining: st === UPowerDeviceState.Discharging
    readonly property int glyph: charging ? 0xF0084 : Util.batteryIcons[Math.max(0, Math.min(10, Math.floor(cap / 10)))]
    // the charge limit (sysfs; UPower doesn't have it), 100 when none is set
    readonly property var bat: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property string sys: bat?.nativePath ? "/sys/class/power_supply/" + bat.nativePath.split("/").pop() : ""
    FileView { id: lim; path: sys ? sys + "/charge_control_end_threshold" : ""; printErrors: false }
    readonly property int limit: parseInt(lim.text()) || 100
    readonly property color colour: draining && cap <= Settings.batteryLow ? Look.alert
        : draining && cap <= Settings.batteryWarn ? Look.urgent
        : charging ? Look.good : Qt.alpha(Look.text, 0.86)

    // the draw, smoothed: UPower's own swings 30-45 W from one second to the next, which made the
    // time left and the panel's projection jump. An average over about 5 minutes, sampled every
    // 10 s; it starts over when the charger goes in or out
    property real rate: 0
    property int samples: 0
    readonly property bool flowing: bat?.state === UPowerDeviceState.Charging || bat?.state === UPowerDeviceState.Discharging
    onFlowingChanged: { rate = 0; samples = 0 }
    onDrainingChanged: { rate = 0; samples = 0 }
    Timer {
        interval: 10000; repeat: true; triggeredOnStart: true
        running: root.flowing
        onTriggered: {
            const r = Math.abs(root.bat?.changeRate ?? 0)
            if (r < 0.05) return
            // a plain mean for the first 5 minutes, so one spike at the start doesn't stick
            root.samples = Math.min(30, root.samples + 1)
            root.rate += (r - root.rate) / root.samples
        }
    }
    // seconds to empty, or to the limit while charging, at that rate; 0 when it isn't moving
    readonly property int secs: !bat || rate <= 0 || !flowing ? 0
        : bat.state === UPowerDeviceState.Discharging ? bat.energy / rate * 3600
        : Math.max(0, bat.energyCapacity * limit / 100 - bat.energy) / rate * 3600
}
