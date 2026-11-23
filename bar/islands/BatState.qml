pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// The battery as the bar shows it: level, glyph and the colour it warns in, and the battery
// notifications (in place of HyDE's batterynotify): see "alerts" below.
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
    onDrainingChanged: {
        rate = 0; samples = 0
        // a new charge or discharge: its alerts can fire again
        if (!draining) { warned = 101; suspendT.stop() }
        check()
    }
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
    // ---- alerts, to the bar's own notification daemon ----
    // Charger in / out. Discharging: a notification at Settings.batteryWarn, a critical one at
    // batteryLow, and at batterySuspend a critical one and a suspend 2 minutes later unless the
    // charger goes in. Charging: once at the charge limit (80 % when none is set: "you can
    // unplug"), and once full when there's no limit: only when it gets there while charging, not
    // when the charger goes in past it. Each fires once per charge or discharge.
    function note(urgency, icon, title, body) {
        Quickshell.execDetached(["notify-send", "-u", urgency, "-a", "Battery", "-i", icon, title, body])
    }
    readonly property int chargeAt: limit < 100 ? limit : 80   // "you can unplug" from here
    property int warned: 101            // the lowest threshold announced this discharge
    property int seen: -1               // the level at the last check while charging; -1 when not
    property bool ready: false          // the state the bar starts in isn't news
    // at start-up a low battery is announced; charging milestones already passed aren't
    Timer { interval: 5000; running: true; onTriggered: { root.ready = true; root.check() } }
    onChargingChanged: if (ready) note("normal", charging ? "battery-good-charging" : "battery-good",
        charging ? "Charger plugged in" : "Charger unplugged", `Battery at ${cap}%`)
    onCapChanged: check()
    onStChanged: check()
    function check() {
        if (!ready || !dev.isPresent) return
        const s = Settings
        if (draining) {
            if (cap <= s.batterySuspend && warned > s.batterySuspend) {
                warned = cap
                note("critical", "battery-empty", "Battery critical", `${cap}% left. Suspending in 2 minutes unless you plug in.`)
                suspendT.restart()
            } else if (cap <= s.batteryLow && warned > s.batteryLow) {
                warned = cap
                note("critical", "battery-caution", "Battery low", `${cap}% left, plug in`)
            } else if (cap <= s.batteryWarn && warned > s.batteryWarn) {
                warned = cap
                note("normal", "battery-low", "Battery getting low", `${cap}% left`)
            }
        } else if (charging) {
            // a milestone counts when the level crosses it during a charge, never on the first
            // look (start-up, or the charger going in past it: "plugged in · 100%" says it)
            const before = seen
            seen = cap
            if (before < 0) return
            if (before < chargeAt && cap >= chargeAt)
                note("normal", "battery-good-charging", limit < 100 ? "Charged to the limit" : "You can unplug", `Battery at ${cap}%`)
            if (limit === 100 && before < 100 && cap >= 100)
                note("normal", "battery-full-charged", "Battery full", "You can unplug the charger")
        }
        if (!charging) seen = -1
    }
    Timer {
        id: suspendT
        interval: 120000
        onTriggered: if (root.draining && root.cap <= Settings.batterySuspend)
            Quickshell.execDetached(["systemctl", "suspend"])
    }

    // seconds to empty, or to the limit while charging, at that rate; 0 when it isn't moving
    readonly property int secs: !bat || rate <= 0 || !flowing ? 0
        : bat.state === UPowerDeviceState.Discharging ? bat.energy / rate * 3600
        : Math.max(0, bat.energyCapacity * limit / 100 - bat.energy) / rate * 3600
}
