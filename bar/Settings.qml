pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User-tunable values, edited live by SettingsPanel.qml and persisted to
// ~/.config/quickshell-bar/settings.json. Referenced bare as `Settings.*` (import qs).
// Numerically-delicate internals (the beat detector's EMA window, sd weighting and strength
// floor in Visualizer.qml) are deliberately NOT exposed: they were tuned offline against
// recorded cava frames and only make sense as a set.
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

        // bar
        hiddenModules: [],     // module file names (Config.qml) left out of the bar
        clock24h: false,

        // system stats pill
        sysInterval: 2000,     // ms between samples
        sysColCpu: "#7dcfff",
        sysColRam: "#bb9af7",
        sysColTemp: "#9ece6a",
        numberRoll: true,      // numbers roll to each sample (each roll repaints the bar briefly)

        // network pill graph
        netColDown: "#99ffdd",
        netColUp: "#ffcc66",

        // beat wave every rim/edge effect rides: how far (px) and how long (s)
        beatEffects: true,     // off: no beat wave, pill rims, window-border glow or sparks
        waveReach: 2600,
        waveDur: 1.0,

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
    property var    hiddenModules: defaults.hiddenModules
    property bool   clock24h:      defaults.clock24h
    property int    sysInterval:   defaults.sysInterval
    property string sysColCpu:     defaults.sysColCpu
    property string sysColRam:     defaults.sysColRam
    property string sysColTemp:    defaults.sysColTemp
    property bool   numberRoll:    defaults.numberRoll
    property string netColDown:    defaults.netColDown
    property string netColUp:      defaults.netColUp
    property bool   beatEffects:   defaults.beatEffects
    property real   waveReach:     defaults.waveReach
    property real   waveDur:       defaults.waveDur
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
    property int    batteryWarn:   defaults.batteryWarn
    property int    batteryLow:    defaults.batteryLow

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
