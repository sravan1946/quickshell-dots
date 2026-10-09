//@ pragma UseQApplication
// Quickshell port of the HyDE waybar layout. Run: qs -c bar
// Layout lives in Config.qml, colours in Theme.qml, one file per module in modules/.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

ShellRoot {
    // qs -c bar ipc call bar toggle   (replaces `waybar.py --hide`)
    // qs -c bar ipc call bar reload   (what systemd/quickshell-bar-reload.path runs on edits)
    IpcHandler {
        target: "bar"
        function toggle(): void { Config.barVisible = !Config.barVisible }
        function reload(): void { Quickshell.reload(false) }
    }
    // Quickshell's own watcher misses every other save made by renaming a new file over the
    // old one (sed -i, most editors): reloads come from quickshell-bar-reload.path instead
    Component.onCompleted: Quickshell.watchFiles = false

    Notifications {}
    Osd {}
    NowPlaying {}

    // one critical notification per discharge once the battery hits Settings.batteryLow (the pill turns red too)
    Connections {
        target: UPower.displayDevice
        property bool warned: false
        function onPercentageChanged() {
            const d = UPower.displayDevice
            const cap = d.percentage <= 1 ? d.percentage * 100 : d.percentage
            if (d.state !== UPowerDeviceState.Discharging) warned = false
            else if (cap <= Settings.batteryLow && !warned) {
                warned = true
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Battery", "-i", "battery-caution", "Battery low", `${Math.round(cap)}% left, plug in`])
            }
        }
    }

    BeatGlow {}

    // one settings GUI for all monitors; opens on the focused one via Config.openSettings()
    SettingsPanel {}
    PowerMenu {}

    IpcHandler {
        target: "quick"
        function toggle(): void { Config.toggleQuick() }
    }

    Variants {
        model: Quickshell.screens
        Bar {}
    }
    Variants {
        model: Quickshell.screens
        QuickSettings {}
    }
}
