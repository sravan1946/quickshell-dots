pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Backlight level, watched once for every bar (and the OSD).
Singleton {
    id: root

    readonly property string device: "amdgpu_bl1"   // ls /sys/class/backlight
    property int pct: 0

    // brightnessctl straight away (hyde-shell's wrapper is a bash + config source per
    // notch); --min-value keeps it from going fully black
    function step(dir) { Util.run(`brightnessctl -q -d ${device} --min-value=1 set 1%${dir > 0 ? "+" : "-"}`) }

    // slider drags: apply the latest value at most every 60ms instead of a process per pixel
    property int target: 0
    function set(p) { target = Math.max(1, Math.round(p)); if (!apply.running) apply.start() }
    Timer { id: apply; interval: 60; onTriggered: Util.run(`brightnessctl -q -d ${root.device} set ${root.target}%`) }

    function read() { cur.reload() }   // reload() is async; text() right after it is stale
    function update() {
        const m = parseInt(max.text())
        if (m > 0) pct = Math.round(100 * parseInt(cur.text()) / m)
    }

    FileView { id: cur; path: `/sys/class/backlight/${root.device}/brightness`; onLoaded: root.update() }
    FileView { id: max; path: `/sys/class/backlight/${root.device}/max_brightness`; blockLoading: true; onLoaded: root.update() }

    // sysfs can't be inotify-watched; the kernel sends a udev "change" event on
    // every brightness write instead (what waybar listens to).
    Process {
        id: monitor
        running: true
        command: ["stdbuf", "-oL", "udevadm", "monitor", "--kernel", "--subsystem-match=backlight"]   // kernel events skip udev rule processing; -oL: no pipe buffering
        stdout: SplitParser { onRead: line => { if (line.includes(root.device)) root.read() } }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: { root.read(); monitor.running = true } }
}
