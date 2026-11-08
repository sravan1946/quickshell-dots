pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User-tunable values, edited live by SettingsPanel.qml and persisted to
// ~/.config/quickshell-bar/settings.json. Referenced bare as `Settings.*` (import qs).
// The kick detector's floor and min gap are exposed; the rest of it (scripts/kicks.py) was
// tuned offline against recorded audio.
//
// To add one: a key in `defaults` and a matching property. Saving, loading and reset()
// all walk `defaults`, so nothing else needs touching.
Singleton {
    id: root

    // ---- defaults: the single source of truth (first run + reset) ----
    readonly property var defaults: ({
        // colours: "@name" follows that HyDE variable (Theme.color), "#hex" is fixed
        themeMainBg: "@main-bg",
        themeMainFg: "@main-fg",
        themeActBg: "@wb-act-bg",
        themeActFg: "@wb-act-fg",
        themeHvrBg: "@wb-hvr-bg",
        themeHvrFg: "@wb-hvr-fg",

        clock24h: false,
        weekStart: 0,          // calendar's first column: 0 locale, 1 Monday, 2 Sunday
        calRefresh: 10,        // min between calendar fetches (opening it always fetches)
        hoverDelay: 150,       // ms the pointer rests on a bar item before its panel drops

        // usage rings and graph
        sysInterval: 2000,     // ms between samples
        sysColCpu: "#7dcfff",
        sysColRam: "#bb9af7",

        // network rates and graph
        netColDown: "#99ffdd",
        netColUp: "#ffcc66",
        netInterval: 2000,     // ms between samples

        // beat wave every rim/edge effect rides: how far (px) and how long (s)
        beatEffects: true,     // off: no beat wave, pill rims, window-border glow or sparks
        waveReach: 1500,       // leaves the music at ~4000 px/s, across the bar in ~0.25 s
        waveDur: 1.1,
        // kick detector (scripts/kicks.py): a kick is the bass band rising by more than
        // kickFloor dB in 30 ms, at least kickGap s after the last (scored on 20 tracks 2026-10-27)
        kickFloor: 4,
        kickGap: 0.18,
        kickMargin: 5,         // dB: a kick peaks within this of the song's loud low end (lower: fewer false ones, misses quiet kicks)
        kickOffset: 0,         // s, + shows kicks earlier than they're heard (the sink's latency is taken off already)

        // synced lyrics from lrclib.net under the artist in the Now Playing panel
        lyrics: true,
        lyricsOffset: 0,       // s, + shows lines earlier
        lyricsMusixmatch: true, // ask Musixmatch (word timing) as well as lrclib (lines only)
        lyricsInBar: false,    // the line being sung takes the bar's title while it's sung

        // kick colours (Visualizer.kickColor): off, every kick is the cover colour; on, its sound
        // shifts the hue up to kickHue degrees and the lightness up to kickLight either way
        kickTimbre: true,
        kickHue: 43,
        kickLight: 0.14,

        // calendar: the Join pill turns solid this many minutes before a meeting
        meetLead: 10,

        // OSD: how long it stays up after the last change, and the startup arm delay that
        // swallows the values arriving as Pipewire/sysfs load
        osdTimeout: 1500,
        osdArmDelay: 2000,

        // notifications: popup lifetime when one asks for the server default
        notifTimeout: 6000,
        notifDrop: true,       // notifications drop out of the bell instead of popping up at the side
        historyMax: 100,       // notifications kept in the history panel

        // battery, while discharging: amber below `warn`, red and one notification below `low`
        batteryWarn: 20,
        batteryLow: 10,
    })

    // ---- live values (what everything binds to) ----
    property string themeMainBg:   defaults.themeMainBg
    property string themeMainFg:   defaults.themeMainFg
    property string themeActBg:    defaults.themeActBg
    property string themeActFg:    defaults.themeActFg
    property string themeHvrBg:    defaults.themeHvrBg
    property string themeHvrFg:    defaults.themeHvrFg
    property bool   clock24h:      defaults.clock24h
    property int    weekStart:     defaults.weekStart
    property int    calRefresh:    defaults.calRefresh
    property int    sysInterval:   defaults.sysInterval
    property string sysColCpu:     defaults.sysColCpu
    property string sysColRam:     defaults.sysColRam
    property string netColDown:    defaults.netColDown
    property string netColUp:      defaults.netColUp
    property int    netInterval:   defaults.netInterval
    property bool   beatEffects:   defaults.beatEffects
    property real   waveReach:     defaults.waveReach
    property real   waveDur:       defaults.waveDur
    property real   kickFloor:     defaults.kickFloor
    property real   kickGap:       defaults.kickGap
    property real   kickMargin:    defaults.kickMargin
    property real   kickOffset:    defaults.kickOffset
    property bool   lyrics:        defaults.lyrics
    property real   lyricsOffset:  defaults.lyricsOffset
    property bool   lyricsMusixmatch: defaults.lyricsMusixmatch
    property bool   lyricsInBar:   defaults.lyricsInBar
    property bool   kickTimbre:    defaults.kickTimbre
    property real   kickHue:       defaults.kickHue
    property real   kickLight:     defaults.kickLight
    property int    meetLead:      defaults.meetLead
    property int    hoverDelay:    defaults.hoverDelay
    property int    osdTimeout:    defaults.osdTimeout
    property int    osdArmDelay:   defaults.osdArmDelay
    property int    notifTimeout:  defaults.notifTimeout
    property bool   notifDrop:     defaults.notifDrop
    property int    historyMax:    defaults.historyMax
    property int    batteryWarn:   defaults.batteryWarn
    property int    batteryLow:    defaults.batteryLow

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
