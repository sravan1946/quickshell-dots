pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User-tunable values, edited live by SettingsPanel.qml and persisted to
// ~/.config/quickshell-bar/settings.json. Referenced bare as `Settings.*` (import qs).
// The beat detector's sensitivity, floor and min gap are exposed; its EMA window and strength
// decay (Visualizer.qml) stay internal: they were tuned offline against recorded cava frames.
//
// To add one: a key in `defaults` and a matching property. Saving, loading and reset()
// all walk `defaults`, so nothing else needs touching.
Singleton {
    id: root

    // ---- defaults: the single source of truth (first run + reset) ----
    readonly property var defaults: ({
        // colours: "@name" follows that HyDE variable (Theme.color), "#hex" is fixed
        themeBarBg: "@bar-bg",
        themeMainBg: "@main-bg",
        themeMainFg: "@main-fg",
        themeActBg: "@wb-act-bg",
        themeActFg: "@wb-act-fg",
        themeHvrBg: "@wb-hvr-bg",
        themeHvrFg: "@wb-hvr-fg",
        themeMenuFg: "@gtk-fg",

        // bar: pills per side, each a list of module file names (modules/); the pills' shapes
        // and padding follow from where they sit (components/Section.qml)
        layout: {
            left: [["SysStats"], ["Workspaces"], ["Media"]],
            center: [["Idle", "Clock", "Dnd"]],
            right: [["Network", "Privacy", "Tray", "Battery"], ["Taskbar"], ["Backlight", "Volume"]],
        },
        hiddenModules: [],     // module file names left out of the bar
        clock24h: false,
        clockSeconds: false,   // ticks the bar every second instead of every minute
        weekStart: 0,          // calendar's first column: 0 locale, 1 Monday, 2 Sunday
        calRefresh: 10,        // min between calendar fetches (opening it always fetches)
        tipDelay: 400,         // ms the pointer rests on a module before its tooltip

        // system stats pill
        sysInterval: 2000,     // ms between samples
        sysColCpu: "#7dcfff",
        sysColRam: "#bb9af7",
        sysColTemp: "#9ece6a",
        numberRoll: true,      // numbers roll to each sample (each roll repaints the bar briefly)

        // network pill graph
        netColDown: "#99ffdd",
        netColUp: "#ffcc66",
        netInterval: 2000,     // ms between samples

        // beat wave every rim/edge effect rides: how far (px) and how long (s)
        beatEffects: true,     // off: no beat wave, pill rims, window-border glow or sparks
        waveReach: 2600,
        waveDur: 1.0,
        // beat detector (Visualizer.detect): a kick is a bass rise above the recent mean +
        // beatSens × sd + beatFloor, at least beatGap s after the last
        beatSens: 0.5,
        beatFloor: 0.01,
        beatGap: 0.2,

        // synced lyrics from lrclib.net under the artist in the Now Playing panel
        lyrics: true,
        lyricsOffset: 0,       // s, + shows lines earlier
        lyricsByWord: true,    // word-timed lyrics fill in word by word (off: whole lines)
        lyricsMusixmatch: true, // ask Musixmatch (word timing) as well as lrclib (lines only)

        // kick colours (Visualizer.kickColor): off, every kick is the cover colour; on, its sound
        // shifts the hue up to kickHue degrees and the lightness up to kickLight either way
        kickTimbre: true,
        kickHue: 43,
        kickLight: 0.14,

        // calendar: the Join pill turns solid this many minutes before a meeting
        meetLead: 10,

        // now playing pill backdrop: 0 columns, 1 ambient field, 2 mini EQ, 3 spectrum strip,
        // 4 waveform tail (shaders/pill.frag `style`)
        mediaStyle: 0,
        // Now Playing panel layout: 0 turntable, 1 poster, 2 waveform, 3 LED matrix, 4 aurora
        panelLayout: 0,
        // turntable layout's ring (shaders/ring.frag `style`): 0 spokes, 1 aura, 2 liquid, 3 LED
        panelStyle: 0,
        // turntable layout's centrepiece: 0 vinyl, 1 cover card, 2 cover orb
        panelCenter: 0,

        // panels (Now Playing, quick settings, hover cards)
        hoverDelay: 220,       // ms the pointer rests on a pill before its card pours out
        liquidSpeed: 1.0,      // pour/drain speed multiplier
        quickEdge: true,       // the right screen edge opens quick settings

        // OSD: how long it stays up after the last change, and the startup arm delay that
        // swallows the values arriving as Pipewire/sysfs load
        osdTimeout: 1500,
        osdArmDelay: 2000,

        // notifications: popup lifetime when one asks for the server default
        notifTimeout: 6000,
        historyMax: 100,       // notifications kept in the history panel

        // battery, while discharging: amber below `warn`, red and one notification below `low`
        batteryWarn: 20,
        batteryLow: 10,
    })

    // ---- live values (what everything binds to) ----
    property string themeBarBg:    defaults.themeBarBg
    property string themeMainBg:   defaults.themeMainBg
    property string themeMainFg:   defaults.themeMainFg
    property string themeActBg:    defaults.themeActBg
    property string themeActFg:    defaults.themeActFg
    property string themeHvrBg:    defaults.themeHvrBg
    property string themeHvrFg:    defaults.themeHvrFg
    property string themeMenuFg:   defaults.themeMenuFg
    property var    layout:        defaults.layout
    property var    hiddenModules: defaults.hiddenModules
    property bool   clock24h:      defaults.clock24h
    property bool   clockSeconds:  defaults.clockSeconds
    property int    weekStart:     defaults.weekStart
    property int    calRefresh:    defaults.calRefresh
    property int    tipDelay:      defaults.tipDelay
    property int    sysInterval:   defaults.sysInterval
    property string sysColCpu:     defaults.sysColCpu
    property string sysColRam:     defaults.sysColRam
    property string sysColTemp:    defaults.sysColTemp
    property bool   numberRoll:    defaults.numberRoll
    property string netColDown:    defaults.netColDown
    property string netColUp:      defaults.netColUp
    property int    netInterval:   defaults.netInterval
    property bool   beatEffects:   defaults.beatEffects
    property real   waveReach:     defaults.waveReach
    property real   waveDur:       defaults.waveDur
    property real   beatSens:      defaults.beatSens
    property real   beatFloor:     defaults.beatFloor
    property real   beatGap:       defaults.beatGap
    property bool   lyrics:        defaults.lyrics
    property real   lyricsOffset:  defaults.lyricsOffset
    property bool   lyricsByWord:  defaults.lyricsByWord
    property bool   lyricsMusixmatch: defaults.lyricsMusixmatch
    property bool   kickTimbre:    defaults.kickTimbre
    property real   kickHue:       defaults.kickHue
    property real   kickLight:     defaults.kickLight
    property int    meetLead:      defaults.meetLead
    property int    mediaStyle:    defaults.mediaStyle
    property int    panelLayout:   defaults.panelLayout
    property int    panelStyle:    defaults.panelStyle
    property int    panelCenter:   defaults.panelCenter
    property int    hoverDelay:    defaults.hoverDelay
    property real   liquidSpeed:   defaults.liquidSpeed
    property bool   quickEdge:     defaults.quickEdge
    property int    osdTimeout:    defaults.osdTimeout
    property int    osdArmDelay:   defaults.osdArmDelay
    property int    notifTimeout:  defaults.notifTimeout
    property int    historyMax:    defaults.historyMax
    property int    batteryWarn:   defaults.batteryWarn
    property int    batteryLow:    defaults.batteryLow

    // `layout` as saved, minus modules that no longer exist, plus ones added since it was
    // saved (each as its own pill at the end of its default side)
    readonly property var barLayout: {
        const sides = ["left", "center", "right"]
        const all = s => [].concat(...s)
        const known = all(sides.map(s => all(defaults.layout[s])))
        const out = {}
        for (const s of sides)
            out[s] = (layout[s] ?? []).map(p => p.filter(m => known.includes(m))).filter(p => p.length)
        const placed = all(sides.map(s => all(out[s])))
        for (const s of sides)
            for (const m of all(defaults.layout[s])) if (!placed.includes(m)) out[s].push([m])
        return out
    }
    // dir -1/1: one place along the bar, stepping across pill and side boundaries as it
    // goes (a pill left empty disappears); 0: split it off into its own pill
    function moveModule(name, dir) {
        const t = []   // modules, "|" after each pill, "~" between sides
        for (const s of ["left", "center", "right"]) {
            if (t.length) t.push("~")
            for (const p of barLayout[s]) t.push(...p, "|")
        }
        const i = t.indexOf(name)
        if (i < 0) return
        if (dir === 0) t.splice(i, 1, "|", name, "|")
        else if (i + dir >= 0 && i + dir < t.length) [t[i], t[i + dir]] = [t[i + dir], t[i]]
        const pills = s => s.split("|").map(p => p.trim().split(/\s+/).filter(m => m)).filter(p => p.length)
        const [l, c, r] = t.join(" ").split("~").map(pills)
        layout = { left: l, center: c, right: r }
    }

    function moduleShown(name) { return !hiddenModules.includes(name) }
    function setModuleShown(name, on) {
        hiddenModules = on ? hiddenModules.filter(m => m !== name) : hiddenModules.concat([name])
    }

    // ---- persistence ----
    property bool loaded: false

    function serialize() {
        const o = {}
        for (const k in defaults) o[k] = root[k]
        return JSON.stringify(o, null, 2)
    }
    // debounced: a slider drag fires many changes a second
    function save() { if (loaded) saveTimer.restart() }
    Timer { id: saveTimer; interval: 400; onTriggered: settingsFile.setText(root.serialize()) }
    Component.onCompleted: { for (const k in defaults) root[k + "Changed"].connect(save) }

    function reset() {
        for (const k in defaults) root[k] = defaults[k]
        if (loaded) settingsFile.setText(serialize())
    }

    // FileView won't create the directory, and without it nothing was ever saved
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/quickshell-bar"] }
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell-bar/settings.json"
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text())
                for (const k in root.defaults) if (o[k] !== undefined) root[k] = o[k]
            } catch (e) {}
            root.loaded = true
        }
        onLoadFailed: root.loaded = true   // first run: no file yet, keep defaults
    }
}
