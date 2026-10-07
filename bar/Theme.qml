pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours come from the same files waybar's style.css imports, so HyDE theme
// switches still recolour the bar. Defaults are the current theme.css values.
Singleton {
    id: root

    property color barBg: Qt.rgba(0, 0, 0, 0.1)
    property color mainBg: "#24283b"
    property color mainFg: "#7aa2f7"
    property color actBg: "#bb9af7"
    property color actFg: "#b4f9f8"
    property color hvrBg: "#7aa2f7"
    property color hvrFg: "#cfc9c2"
    // GTK menus (waybar's tray/power menus) take text colour from the GTK theme
    property color menuFg: "#c0caf5"

    // global.css: JetBrainsMono Nerd Font 10px; border-radius.css: 10pt
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 10
    readonly property real radius: 13.33

    function g(cp) { return String.fromCodePoint(cp) }

    FileView {
        id: wallbash
        path: Quickshell.env("HOME") + "/.cache/hyde/wallbash/gtk.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply()
    }
    // HyDE's wallbash renders the bar colours into ~/.config/waybar/theme.css from its
    // own templates (waybar.dcol / <theme>/waybar.theme), with or without waybar
    // installed, but skips the write if that directory is missing. Keep it around.
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/waybar"] }
    FileView {
        id: theme
        path: Quickshell.env("HOME") + "/.config/waybar/theme.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.apply(); gtkFg.running = true }
    }

    Process {
        id: gtkFg
        command: ["sh", "-c", `
            n=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
            for d in ~/.themes ~/.local/share/themes /usr/share/themes; do
                f="$d/$n/gtk-3.0/gtk.css"
                [ -f "$f" ] && grep -ohE '@define-color theme_fg_color [^;]+' "$f" | head -1 | cut -d' ' -f3 && break
            done`]
        stdout: StdioCollector { onStreamFinished: { const c = text.trim(); if (c) root.menuFg = c } }
    }

    function apply() {
        const defs = {}
        const re = /@define-color\s+([\w-]+)\s+([^;]+);/g
        for (const css of [wallbash.text(), theme.text()]) {
            let m
            while ((m = re.exec(css)) !== null) defs[m[1]] = m[2].trim()
        }
        const resolve = (v, depth) => {
            if (v === undefined || depth > 8) return undefined
            if (v.startsWith("@")) return resolve(defs[v.slice(1)], depth + 1)
            const rgba = v.match(/rgba?\(([^)]+)\)/)
            if (!rgba) return v
            const p = rgba[1].split(",").map(Number)
            return Qt.rgba(p[0] / 255, p[1] / 255, p[2] / 255, p.length > 3 ? p[3] : 1)
        }
        const set = (prop, key) => { const c = resolve(defs[key], 0); if (c !== undefined) root[prop] = c }
        set("barBg", "bar-bg")
        set("mainBg", "main-bg")
        set("mainFg", "main-fg")
        set("actBg", "wb-act-bg")
        set("actFg", "wb-act-fg")
        set("hvrBg", "wb-hvr-bg")
        set("hvrFg", "wb-hvr-fg")
    }
}
