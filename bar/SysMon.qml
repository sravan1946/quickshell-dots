pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU, memory and temperature, sampled once for every bar. modules/SysStats.qml draws it.
Singleton {
    id: root

    readonly property int interval: Settings.sysInterval

    property real cpu: 0           // %, all cores
    property var cores: []         // % per core
    property real ram: 0           // % used (MemTotal - MemAvailable)
    property real memTotal: 0      // KiB
    property real memUsed: 0
    property real memCache: 0      // reclaimable page cache + buffers
    property real swapTotal: 0
    property real swapUsed: 0
    property real temp: 0          // °C, k10temp Tctl / coretemp package
    property var load: [0, 0, 0]
    property real uptime: 0        // s
    property string model: ""
    property var hist: []          // last 60 [cpu, ram, temp] samples (2 min), for the graphs
    property var prev: []          // [busy, total] jiffies per cpu line of the last sample

    // reload() is async (text() right after it is stale): parse in each onLoaded
    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            // cpu  user nice system idle iowait irq softirq steal
            const rows = text().split("\n").filter(l => l.startsWith("cpu")).map(l => {
                const f = l.trim().split(/\s+/).slice(1, 9).map(Number)
                const total = f.reduce((a, b) => a + b, 0)
                return [total - f[3] - f[4], total]
            })
            const pct = rows.map((r, i) => {
                const p = root.prev[i]
                return p && r[1] > p[1] ? 100 * (r[0] - p[0]) / (r[1] - p[1]) : 0
            })
            if (root.prev.length) {
                root.cpu = pct[0]
                root.cores = pct.slice(1)
                root.hist = root.hist.concat([[root.cpu, root.ram, root.temp]]).slice(-60)
            }
            root.prev = rows
        }
    }
    FileView {
        id: mem
        path: "/proc/meminfo"
        onLoaded: {
            const t = text()
            const kb = k => +(t.match(new RegExp(`^${k}:\\s+(\\d+)`, "m"))?.[1] ?? 0)
            const total = kb("MemTotal"), used = total - kb("MemAvailable")
            root.memTotal = total
            root.memUsed = used
            root.memCache = Math.min(total - used, kb("Buffers") + kb("Cached") + kb("SReclaimable") - kb("Shmem"))
            root.ram = total ? 100 * used / total : 0
            root.swapTotal = kb("SwapTotal")
            root.swapUsed = root.swapTotal - kb("SwapFree")
        }
    }
    FileView { id: loadavg; path: "/proc/loadavg"; onLoaded: root.load = text().split(" ").slice(0, 3).map(Number) }
    FileView { id: up; path: "/proc/uptime"; onLoaded: root.uptime = parseFloat(text()) }
    FileView { id: thermal; printErrors: false; onLoaded: root.temp = parseInt(text()) / 1000 }
    FileView {
        path: "/proc/cpuinfo"
        onLoaded: root.model = (text().match(/^model name\s*:\s*(.*)$/m)?.[1] ?? "")
            .replace(/\s+\d+-Core Processor|\s+with .*|\(R\)|\(TM\)/g, "").trim()
    }

    // hwmon numbering moves between boots: find the CPU sensor by name once
    Process {
        running: true
        command: ["sh", "-c", "grep -lE '^(k10temp|coretemp|zenpower)$' /sys/class/hwmon/*/name | head -1"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) thermal.path = text.trim().replace(/name$/, "temp1_input") }
    }

    Timer {
        interval: root.interval; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { mem.reload(); stat.reload(); loadavg.reload(); up.reload(); if (thermal.path) thermal.reload() }
    }
}
