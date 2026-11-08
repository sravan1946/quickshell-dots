//@ pragma UseQApplication
// Quickshell port of the HyDE waybar layout. Run: qs -c bar
// Layout lives in Config.qml, colours in Theme.qml, one file per module in modules/.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.islands

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

    // Quickshell can miss a device that connects while it first syncs with BlueZ (the mouse at
    // boot, a second after the bar) and keep it "disconnected" until restarted. So once, a bit
    // after start, check BlueZ's own list and restart if they disagree; the stamp in /run (gone
    // at reboot) keeps a lasting disagreement from turning into a restart loop
    Timer { interval: 10000; running: true; onTriggered: btCheck.running = true }
    Process {
        id: btCheck
        command: ["bluetoothctl", "devices", "Connected"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ours = Bluetooth.devices.values.filter(d => d.connected).map(d => d.address)
                const missed = text.split("\n").map(l => l.split(" ")[1]).filter(a => a && !ours.includes(a))
                if (missed.length) Quickshell.execDetached(["sh", "-c",
                    'f="$XDG_RUNTIME_DIR/qs-bar-bt-resync"; [ -e "$f" ] || { touch "$f"; systemctl --user --no-block restart quickshell-bar; }'])
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

    // the island bar (islands/IslandBar.qml): its music card replaces the Now Playing panel
    Variants {
        model: Quickshell.screens
        IslandBar {}
    }
}
